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

const LIGHTBLUE_STRING_TEMPLATE = ansi.Fg.rgb("{s}", 249, 178, 255);
const GREEN_STRING_TEMPLATE = ansi.Fg.green("{s}", null);

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

    if (std.ascii.eqlIgnoreCase(query_version, "help")) {
        println(HELP_MESSAGE);
        return;
    } else if (std.ascii.eqlIgnoreCase(query_version, "system")) {
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

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                printlnf(ansi.Fg.red("Zig exit with code: ", null) ++ ansi.Fg.yellow("{d}", null), .{result.term.Exited});
                return;
            }
        },
        else => {
            printlnf(ansi.Fg.red("Unexpected error with Zig: ", null) ++ ansi.Fg.yellow("{s}", null), .{@tagName(result.term)});
            return;
        },
    }

    const zig_output = try json.parseFromSlice(json.Value, allocator, result.stdout, .{});
    defer zig_output.deinit();

    const zig_version = zig_output.value.object.get("version");
    var zig_commit: ?[]const u8 = null;
    if (zig_version) |v| {
        const vstr = v.string;

        printlnf("< " ++ ansi.Fg.high_blue("Current Zig Version: ", null) ++ LIGHTBLUE_STRING_TEMPLATE, .{vstr});

        if (std.mem.eql(u8, vstr, query_version)) {
            println("> " ++ ansi.Fg.green("You are using the latest version", null));
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
        printlnf("< " ++ ansi.Fg.high_blue("Zig folder: ", null) ++ LIGHTBLUE_STRING_TEMPLATE, .{zig_folder});
    }

    var str_buffer: [ARCH.len + OS.len + 1]u8 = undefined;
    const system = try std.fmt.bufPrint(&str_buffer, "{s}-{s}", .{ ARCH, OS });
    printlnf("< " ++ ansi.Fg.high_blue("Your system is: ", null) ++ LIGHTBLUE_STRING_TEMPLATE ++ "\n", .{system});

    request_thread.join();

    if (zig_index_json == null) {
        println("Something went wrong while getting all zig versions");
        return;
    }

    const zig_index = zig_index_json.?;

    const is_nightly = std.ascii.eqlIgnoreCase(query_version, "nightly") or std.ascii.eqlIgnoreCase(query_version, "master");
    var new_nightly_commit_hash: ?[]const u8 = null;

    const target_version = blk: {
        if (is_nightly) {
            const master = zig_index.value.object.get("master") orelse {
                println(ansi.Fg.red("Nightly version not found", null));
                return;
            };

            const master_version = master.object.get("version").?.string;
            printlnf("> " ++ ansi.Fg.high_magenta("Nightly version: ", null) ++ GREEN_STRING_TEMPLATE, .{master_version});

            const master_date = master.object.get("date").?;
            printlnf("> " ++ ansi.Fg.high_magenta("Nightly version date: ", null) ++ GREEN_STRING_TEMPLATE ++ "\n", .{master_date.string});

            if (zig_version != null and std.mem.eql(u8, master_version, zig_version.?.string)) {
                println("> " ++ ansi.Fg.green("You are using the latest nightly version", null));
                return;
            }

            if (is_nightly and std.mem.containsAtLeast(u8, master_version, 1, "+")) {
                var iter = std.mem.splitScalar(u8, master_version, '+');
                _ = iter.next().?;
                new_nightly_commit_hash = iter.next();
            }

            break :blk master;
        } else if (std.ascii.eqlIgnoreCase(query_version, "latest")) {
            const keys = zig_index.value.object.keys();

            // Dirty way to get latest version
            // MAYBE:  TODO:  Implement version sorting so we can get latest version properly
            const latest = keys[1];

            printlnf("> " ++ ansi.Fg.high_cyan("Latest version: ", null) ++ GREEN_STRING_TEMPLATE, .{latest});

            const latest_version = zig_index.value.object.get(latest).?;
            const latest_date = latest_version.object.get("date").?;
            printlnf("> " ++ ansi.Fg.high_cyan("Latest version date: ", null) ++ GREEN_STRING_TEMPLATE ++ "\n", .{latest_date.string});

            if (zig_version != null and std.mem.eql(u8, latest, zig_version.?.string)) {
                println("> " ++ ansi.Fg.green("You are using the latest stable version", null));
                return;
            }

            break :blk latest_version;
        } else if (std.ascii.eqlIgnoreCase(query_version, "list")) {
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

                println("> " ++ ansi.Fg.red("Version not found", null));
                return;
            };

            const date = version_obj.object.get("date").?;
            printlnf("> " ++ ansi.Fg.yellow("Version: ", null) ++ GREEN_STRING_TEMPLATE ++ "\n> " ++ ansi.Fg.yellow("Version date: ", null) ++ GREEN_STRING_TEMPLATE ++ "\n", .{ resolve_version, date.string });

            if (zig_version != null and std.mem.eql(u8, resolve_version, zig_version.?.string)) {
                println("> " ++ ansi.Fg.green("You are using the same version", null));
                return;
            }

            break :blk version_obj;
        }
    };

    const build = target_version.object.get(system) orelse {
        printlnf("> " ++ ansi.Fg.red("This version is not available for your system ({s})", null), .{system});
        return;
    };
    const file_url = build.object.get("tarball").?.string;

    printf("< " ++ ansi.Fg.yellow("Downloading ", null) ++ ansi.Fg.magenta("{s}", .Bold) ++ "...", .{file_url});

    const downloaded_file = try get(&client, &headers, file_url);

    const cwd = std.fs.cwd();
    const file_name = path.basename(file_url);

    try cwd.writeFile2(.{
        .data = downloaded_file,
        .sub_path = file_name,
    });
    defer cwd.deleteFile(file_name) catch {};

    allocator.free(downloaded_file);

    try cwd.makePath(zig_folder);

    printf(ansi.ClearLine ++ "\r> " ++ ansi.Fg.yellow("Extracting to ", null) ++ ansi.Fg.magenta("{s}", .Bold) ++ "...", .{zig_folder});

    const tar = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "tar", "-xf", file_name, "-C", zig_folder, "--strip-components", "1" },
    });

    if (tar.term != .Exited or tar.term.Exited != 0) {
        println("\rSomething went wrong while extracting tarball");
        printlnf("Tar error: {s}", .{tar.stderr});
    } else {
        printlnf(ansi.ClearLine ++ "\r> " ++ ansi.Fg.green("Successfully extracted to ", null) ++ ansi.Fg.magenta("{s}", .Bold), .{zig_folder});

        if (is_nightly and
            std.mem.containsAtLeast(u8, file_name, 1, "+") and
            zig_commit != null and
            new_nightly_commit_hash != null)
        {
            printlnf("\n> " ++ ansi.Fg.green("Changelog: ", null) ++ ansi.Fg.cyan(ZIG_REPO_COMPARE ++ "{s}..{s}", null), .{ zig_commit.?, new_nightly_commit_hash.? });
        }
    }
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
