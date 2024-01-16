const std = @import("std");
const io = std.io;
const json = std.json;
const http = std.http;
const fs = std.fs;
const path = fs.path;

const detect = @import("detect.zig");

const MAX_BODY_SIZE: usize = 1024 * 1024 * 1024;
const ZIG_VERSION_INDEX = "https://ziglang.org/download/index.json";
const ZIG_REPO_COMPARE = "https://github.com/ziglang/zig/compare/";
const HELP_MESSAGE =
    \\ Usage:
    \\      zigu <command>
    \\
    \\ Commands:
    \\      list                    Show all available versions
    \\      latest                  Install latest stable version
    \\      nightly | master        Install latest nightly version
    \\      [version]               Install specified version. 
    \\                              Will resolve to a latest version with the provided prefix
    \\      help                    Show this help message
    \\
    \\ Examples:
    \\      zigu latest
    \\
    \\      zigu 0         
    \\      zigu 0.10               Will resolve to 0.10.1
    \\      zigu 1                  Will resolve to 1.x.x version if any 
;

/// Windows can't have global stdout so we need to declare it in `main`
var stdout_writer: io.Writer(fs.File, std.os.WriteError, fs.File.write) = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    stdout_writer = io.getStdOut().writer();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        print(HELP_MESSAGE);
        return;
    } else if (std.mem.eql(u8, args[1], "help")) {
        print(HELP_MESSAGE);
        return;
    }

    var zig_index_json: ?json.Parsed(json.Value) = null;
    defer {
        if (zig_index_json) |*j| {
            j.deinit();
        }
    }

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    var headers = http.Headers.init(allocator);
    defer headers.deinit();

    const request_thread = try std.Thread.spawn(.{}, getZigJsonIndex, .{ &client, &headers, &zig_index_json });

    const query_version: []const u8 = args[1];

    // TODO:  Find a way to capture only stdout
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "zig", "env" },
    });
    // We don't need stderr
    allocator.free(result.stderr);
    defer allocator.free(result.stdout);

    if (result.term.Exited != 0) {
        printf("Zig exit with code: {d}\n", .{result.term.Exited});
        return;
    }

    const zig_output = try json.parseFromSlice(json.Value, allocator, result.stdout, .{});
    defer zig_output.deinit();

    const zig_version = zig_output.value.object.get("version");
    var zig_commit: ?[]const u8 = null;
    if (zig_version) |v| {
        const vstr = v.string;

        printf("< Current Zig Version: {s}\n", .{vstr});

        if (std.mem.eql(u8, vstr, query_version)) {
            print("Already up to date\n");
            return;
        } else if (std.mem.containsAtLeast(u8, vstr, 1, "+")) {
            var iter = std.mem.splitScalar(u8, vstr, '+');
            _ = iter.next().?;
            zig_commit = iter.next();
        }
    }

    const zig_executable = zig_output.value.object.get("zig_exe");
    const zig_folder = blk: {
        if (zig_executable) |f| {
            break :blk path.dirname(f.string) orelse "zig";
        } else {
            break :blk "zig";
        }
    };

    if (std.mem.eql(u8, zig_folder, "zig")) {
        print("Zig folder not found. Will extract to `zig` in current directory");
    } else {
        printf("< Zig folder: {s}\n", .{zig_folder});
    }

    var ffi_system = detect.arch_os();
    defer detect.free_string(ffi_system.ptr, ffi_system.len);
    const system = ffi_system.toSlice();
    printf("< Your system is: {s}\n\n", .{system});

    request_thread.join();

    if (zig_index_json == null) {
        print("Something went wrong while getting all zig versions\n");
        return;
    }

    const zig_index = zig_index_json.?;

    const is_nightly = std.mem.eql(u8, query_version, "nightly") or std.mem.eql(u8, query_version, "master");

    const target_version = blk: {
        if (is_nightly) {
            const master = zig_index.value.object.get("master") orelse {
                print("Nightly version not found\n");
                return;
            };

            const master_version = master.object.get("version").?;
            printf("> Nightly version: {s}\n", .{master_version.string});

            const master_date = master.object.get("date").?;
            printf("> Nightly version date: {s}\n", .{master_date.string});

            if (zig_version != null and std.mem.eql(u8, master_version.string, zig_version.?.string)) {
                print("> You are using the latest nightly\n");
                return;
            }

            break :blk master;
        } else if (std.mem.eql(u8, query_version, "latest")) {
            const keys = zig_index.value.object.keys();

            // Dirty way to get latest version
            // MAYBE:  TODO:  Implement version sorting so we can get latest version properly
            const latest = keys[1];

            printf("> Latest version: {s}\n", .{latest});

            const latest_version = zig_index.value.object.get(latest).?;
            const latest_date = latest_version.object.get("date").?;
            printf("> Latest version date: {s}\n", .{latest_date.string});

            if (zig_version != null and std.mem.eql(u8, latest, zig_version.?.string)) {
                print("> You are using the latest nightly\n");
                return;
            }

            break :blk latest_version;
        } else if (std.mem.eql(u8, query_version, "list")) {
            print("> Available versions:\n");
            for (zig_index.value.object.keys(), 0..) |key, idx| {
                if (key.len == 0) continue;

                printf("\t{s}", .{key});

                if (idx % 3 == 0) {
                    print("\n");
                } else {
                    print("\t");
                }
            }
            return;
        } else {
            // Dirty way to resolve version
            var resolve_version = query_version;
            const version_obj = zig_index.value.object.get(resolve_version) orelse prefix: {
                for (zig_index.value.object.keys()) |key| {
                    if (std.mem.startsWith(u8, key, resolve_version)) {
                        resolve_version = key;
                        break :prefix zig_index.value.object.get(key).?;
                    }
                }

                print("Version not found\n");
                return;
            };

            const date = version_obj.object.get("date").?;
            printf(
                \\> Verions: {s}
                \\> Version Date: {s}
                \\
            , .{ resolve_version, date.string });

            if (zig_version != null and std.mem.eql(u8, resolve_version, zig_version.?.string)) {
                print("> You are using the same version\n");
                return;
            }

            break :blk version_obj;
        }
    };

    const build = target_version.object.get(system) orelse {
        printf("This version is not available for your system ({s})\n", .{system});
        return;
    };
    const file_url = build.object.get("tarball").?.string;

    printf("> Download link for your system: {s}\n", .{file_url});
    print("< Downloading...");

    const downloaded_file = try get(&client, &headers, file_url);
    defer allocator.free(downloaded_file);

    const cwd = std.fs.cwd();
    const file_name = path.basename(file_url);

    try cwd.writeFile2(.{
        .data = downloaded_file,
        .sub_path = file_name,
    });

    try cwd.makePath(zig_folder);

    printf("\r> Extracting to {s}...", .{zig_folder});

    const tar = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "tar", "-xf", file_name, "-C", zig_folder, "--strip-components", "1" },
    });

    if (tar.term != .Exited or tar.term.Exited != 0) {
        print("\rSomething went wrong while extracting tarball\n");
        printf("Tar error: {s}\n", .{tar.stderr});
    } else {
        printf("\r> Successfully extracted to {s}\n", .{zig_folder});

        if (is_nightly and
            std.mem.containsAtLeast(u8, file_name, 1, "+") and
            zig_commit != null)
        blk: {
            var iter = std.mem.splitScalar(u8, file_name, '+');
            _ = iter.next().?;

            const commit_and_ext = iter.next() orelse break :blk;
            const commit_hash = path.stem(commit_and_ext);

            printf("\n> Changelog: {s}{s}..{s}\n", .{ ZIG_REPO_COMPARE, zig_commit.?, commit_hash });
        }
    }

    cwd.deleteFile(file_name) catch {};
}

fn print(msg: []const u8) void {
    stdout_writer.writeAll(msg) catch return;
}

fn printf(comptime fmt: []const u8, args: anytype) void {
    stdout_writer.print(fmt, args) catch return;
}

fn getZigJsonIndex(client: *http.Client, headers: *http.Headers, out: *?json.Parsed(json.Value)) !void {
    const body = try get(client, headers, ZIG_VERSION_INDEX);

    out.* = try json.parseFromSlice(json.Value, client.allocator, body, .{});
    client.allocator.free(body);
}

/// Return Request object. Free it when done
fn get(client: *http.Client, headers: *http.Headers, url: []const u8) ![]const u8 {
    var request = try client.open(.GET, try std.Uri.parse(url), headers.*, .{});
    defer request.deinit();

    try request.send(.{});
    try request.wait();

    if (request.response.status != .ok) {
        return error.NotOk;
    }

    const body = try request.reader().readAllAlloc(client.allocator, MAX_BODY_SIZE);
    return body;
}
