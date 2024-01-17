const std = @import("std");
const builtin = @import("builtin");
const ansi = @import("ansi.zig");
const io = std.io;
const json = std.json;
const http = std.http;
const fs = std.fs;
const path = fs.path;

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
    \\      zigu 0                  Will resolve to latest 0.x.x version (i.e. 0.11.0) if any  
    \\      zigu 0.10               Will resolve to latest 0.10 version (i.e. 0.10.1) if any
    \\      zigu 1                  Will resolve to latest 1.x.x version if any 
;
const OS = @tagName(builtin.os.tag);
const ARCH = @tagName(builtin.cpu.arch);

const LIGTHBLUE = ansi.Fg.formatRgb(249, 178, 255);

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
        println(HELP_MESSAGE);
        return;
    }

    const query_version: []const u8 = args[1];

    if (std.mem.eql(u8, query_version, "help")) {
        println(HELP_MESSAGE);
        return;
    } else if (std.mem.eql(u8, query_version, "system")) {
        printlnf("{s}-{s}", .{ ARCH, OS });
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

    // TODO:  Find a way to capture only stdout
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "zig", "env" },
    });
    // We don't need stderr
    allocator.free(result.stderr);
    defer allocator.free(result.stdout);

    if (result.term.Exited != 0) {
        printlnf("{s}Zig exit with code: {s}{d}", .{ ansi.Fg.Red, ansi.Fg.Yellow, result.term.Exited });
        return;
    }

    const zig_output = try json.parseFromSlice(json.Value, allocator, result.stdout, .{});
    defer zig_output.deinit();

    const zig_version = zig_output.value.object.get("version");
    var zig_commit: ?[]const u8 = null;
    if (zig_version) |v| {
        const vstr = v.string;

        printlnf("< Current Zig Version: " ++ LIGTHBLUE ++ "{s}" ++ ansi.Reset, .{vstr});

        if (std.mem.eql(u8, vstr, query_version)) {
            println("> " ++ ansi.Fg.Green ++ "You are using the latest version" ++ ansi.Reset);
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
        println("Zig folder not found. Will extract to `zig` in current directory");
    } else {
        printlnf("< Zig folder: " ++ LIGTHBLUE ++ "{s}" ++ ansi.Reset, .{zig_folder});
    }

    var str_buffer: [ARCH.len + OS.len + 1]u8 = undefined;
    const system = try std.fmt.bufPrint(&str_buffer, "{s}-{s}", .{ ARCH, OS });
    printlnf("< Your system is: " ++ LIGTHBLUE ++ "{s}" ++ ansi.Reset ++ "\n", .{system});

    request_thread.join();

    if (zig_index_json == null) {
        println("Something went wrong while getting all zig versions");
        return;
    }

    const zig_index = zig_index_json.?;

    const is_nightly = std.mem.eql(u8, query_version, "nightly") or std.mem.eql(u8, query_version, "master");

    const target_version = blk: {
        if (is_nightly) {
            const master = zig_index.value.object.get("master") orelse {
                println("Nightly version not found");
                return;
            };

            const master_version = master.object.get("version").?;
            printlnf("> Nightly version: " ++ ansi.Fg.Green ++ "{s}" ++ ansi.Reset, .{master_version.string});

            const master_date = master.object.get("date").?;
            printlnf("> Nightly version date: " ++ ansi.Fg.Green ++ "{s}" ++ ansi.Reset ++ "\n", .{master_date.string});

            if (zig_version != null and std.mem.eql(u8, master_version.string, zig_version.?.string)) {
                println("> " ++ ansi.Fg.Green ++ "You are using the latest nightly version" ++ ansi.Reset);
                return;
            }

            break :blk master;
        } else if (std.mem.eql(u8, query_version, "latest")) {
            const keys = zig_index.value.object.keys();

            // Dirty way to get latest version
            // MAYBE:  TODO:  Implement version sorting so we can get latest version properly
            const latest = keys[1];

            printlnf("> Latest version: " ++ ansi.Fg.Green ++ "{s}", .{latest});

            const latest_version = zig_index.value.object.get(latest).?;
            const latest_date = latest_version.object.get("date").?;
            printlnf("> Latest version date: " ++ ansi.Fg.Green ++ "{s}\n", .{latest_date.string});

            if (zig_version != null and std.mem.eql(u8, latest, zig_version.?.string)) {
                println("> " ++ ansi.Fg.Green ++ "You are using the latest stable version" ++ ansi.Reset);
                return;
            }

            break :blk latest_version;
        } else if (std.mem.eql(u8, query_version, "list")) {
            println("> Available versions:");
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

                println(ansi.Fg.Red ++ "Version not found" ++ ansi.Reset);
                return;
            };

            const date = version_obj.object.get("date").?;
            printlnf("> Version: " ++ ansi.Fg.Green ++ "{s}" ++ ansi.Reset ++ "\n> Version date: " ++ ansi.Fg.Green ++ "{s}" ++ ansi.Reset ++ "\n", .{ resolve_version, date.string });

            if (zig_version != null and std.mem.eql(u8, resolve_version, zig_version.?.string)) {
                println("> " ++ ansi.Fg.Green ++ "You are using the same version" ++ ansi.Reset);
                return;
            }

            break :blk version_obj;
        }
    };

    const build = target_version.object.get(system) orelse {
        printlnf(ansi.Fg.Red ++ "This version is not available for your system ({s})" ++ ansi.Reset, .{system});
        return;
    };
    const file_url = build.object.get("tarball").?.string;

    printf("< " ++ ansi.Fg.Yellow ++ "Downloading " ++ ansi.Fg.Magenta ++ "{s}" ++ ansi.Reset ++ "...", .{file_url});

    const downloaded_file = try get(&client, &headers, file_url);

    const cwd = std.fs.cwd();
    const file_name = path.basename(file_url);

    try cwd.writeFile2(.{
        .data = downloaded_file,
        .sub_path = file_name,
    });

    allocator.free(downloaded_file);

    try cwd.makePath(zig_folder);

    printf(ansi.ClearLine ++ "\r> " ++ ansi.Fg.Yellow ++ "Extracting to " ++ ansi.Fg.Magenta ++ "{s}" ++ ansi.Reset ++ "...", .{zig_folder});

    const tar = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "tar", "-xf", file_name, "-C", zig_folder, "--strip-components", "1" },
    });

    if (tar.term != .Exited or tar.term.Exited != 0) {
        println("\rSomething went wrong while extracting tarball");
        printlnf("Tar error: {s}", .{tar.stderr});
    } else {
        printlnf(ansi.ClearLine ++ "\r> " ++ ansi.Fg.Green ++ "Successfully extracted to " ++ ansi.Fg.Magenta ++ "{s}" ++ ansi.Reset, .{zig_folder});

        if (is_nightly and
            std.mem.containsAtLeast(u8, file_name, 1, "+") and
            zig_commit != null)
        blk: {
            var iter = std.mem.splitScalar(u8, file_name, '+');
            _ = iter.next().?;

            const commit_and_ext = iter.next() orelse break :blk;
            const commit_hash = path.stem(commit_and_ext);

            printlnf("\n> Changelog: {s}{s}..{s}", .{ ZIG_REPO_COMPARE, zig_commit.?, commit_hash });
        }
    }

    cwd.deleteFile(file_name) catch {};
}

fn print(comptime msg: []const u8) void {
    stdout_writer.writeAll(msg) catch return;
}

fn println(comptime msg: []const u8) void {
    stdout_writer.writeAll(msg ++ "\n") catch return;
}

fn printf(comptime fmt: []const u8, args: anytype) void {
    stdout_writer.print(fmt, args) catch return;
}

fn printlnf(comptime fmt: []const u8, args: anytype) void {
    stdout_writer.print(fmt ++ "\n", args) catch return;
}

fn getZigJsonIndex(client: *http.Client, headers: *http.Headers, out: *?json.Parsed(json.Value)) !void {
    const body = try get(client, headers, ZIG_VERSION_INDEX);

    out.* = try json.parseFromSlice(json.Value, client.allocator, body, .{});
    client.allocator.free(body);
}

/// Return response body. Caller owns returned body
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
