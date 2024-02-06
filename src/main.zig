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
const HELP_MESSAGE = std.fmt.comptimePrint(
    \\ {s}:
    \\      zigu <command>
    \\
    \\ {s}:
    \\      list                    Show all available versions
    \\      latest                  Install latest stable version
    \\      nightly | master        Install latest nightly version
    \\      [version]               Install specified version. 
    \\                              Will resolve to a latest version with the provided prefix
    \\      help                    Show this help message
    \\
    \\ {s}:
    \\      zigu latest
    \\
    \\      zigu 0                  Will resolve to latest 0.x.x version (i.e. 0.11.0) if any  
    \\      zigu 0.10               Will resolve to latest 0.10 version (i.e. 0.10.1) if any
    \\      zigu 1                  Will resolve to latest 1.x.x version if any 
, .{ ansi.Fg.white("Usage", .Underline), ansi.Fg.white("Commands", .Underline), ansi.Fg.white("Examples", .Underline) });

const SYSTEM = std.fmt.comptimePrint("{s}-{s}", .{ @tagName(builtin.cpu.arch), @tagName(builtin.os.tag) });

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
        println(SYSTEM);
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

    var zig_version: ?[]const u8 = null;
    var zig_commit: ?[]const u8 = null;
    var zig_folder: []const u8 = undefined;
    var zig_output: ?json.Parsed(json.Value) = null;
    defer if (zig_output) |o| o.deinit();

    blk: {
        // TODO:  Find a way to capture only stdout
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "zig", "env" },
        }) catch |err| {
            switch (err) {
                error.FileNotFound => {
                    zig_folder = "zig";
                    println(std.fmt.comptimePrint("! {s}", .{ansi.Fg.red("Zig folder not found. Will extract to `zig` in current directory", .Bold)}));
                    break :blk;
                },
                else => return err,
            }
        };
        // We don't need stderr
        allocator.free(result.stderr);
        defer allocator.free(result.stdout);

        switch (result.term) {
            .Exited => |code| {
                if (code != 0) {
                    printlnf(ansi.Fg.red("! Zig exit with code: ", null) ++ ansi.Fg.yellow("{d}", null), .{result.term.Exited});
                    return;
                }
            },
            else => {
                printlnf(ansi.Fg.red("! Unexpected error with Zig: ", null) ++ ansi.Fg.yellow("{s}", null), .{@tagName(result.term)});
                return;
            },
        }

        zig_output = try json.parseFromSlice(json.Value, allocator, result.stdout, .{});
        // defer zig_output.deinit();

        const zv = zig_output.?.value.object.get("version");
        if (zv) |v| {
            zig_version = v.string;

            printlnf("< " ++ ansi.Fg.highBlue("Current Zig Version: ", .Bold) ++ LIGHTBLUE_STRING_TEMPLATE, .{zig_version.?});

            if (std.mem.eql(u8, zig_version.?, query_version)) {
                println("> " ++ ansi.Fg.green("You are using the latest version", null));
                return;
            } else if (std.mem.containsAtLeast(u8, zig_version.?, 1, "+")) {
                var iter = std.mem.splitScalar(u8, zig_version.?, '+');
                _ = iter.next().?;
                zig_commit = iter.next();
            }
        }

        const zig_executable = zig_output.?.value.object.get("zig_exe").?;
        zig_folder = path.dirname(zig_executable.string) orelse "zig";
        printlnf("< " ++ ansi.Fg.highBlue("Zig folder: ", .Bold) ++ LIGHTBLUE_STRING_TEMPLATE, .{zig_folder});
    }

    printlnf("< " ++ ansi.Fg.highBlue("Your system is: ", .Bold) ++ LIGHTBLUE_STRING_TEMPLATE ++ "\n", .{SYSTEM});

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
            printlnf("> " ++ ansi.Fg.highMagenta("Nightly version: ", .Bold) ++ GREEN_STRING_TEMPLATE, .{master_version});

            const master_date = master.object.get("date").?;
            printlnf("> " ++ ansi.Fg.highMagenta("Nightly version date: ", .Bold) ++ GREEN_STRING_TEMPLATE ++ "\n", .{master_date.string});

            if (zig_version != null and std.mem.eql(u8, master_version, zig_version.?)) {
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

            printlnf("> " ++ ansi.Fg.highCyan("Latest version: ", .Bold) ++ GREEN_STRING_TEMPLATE, .{latest});

            const latest_version = zig_index.value.object.get(latest).?;
            const latest_date = latest_version.object.get("date").?;
            printlnf("> " ++ ansi.Fg.highCyan("Latest version date: ", .Bold) ++ GREEN_STRING_TEMPLATE ++ "\n", .{latest_date.string});

            if (zig_version != null and std.mem.eql(u8, latest, zig_version.?)) {
                println("> " ++ ansi.Fg.green("You are using the latest stable version", null));
                return;
            }

            break :blk latest_version;
        } else if (std.ascii.eqlIgnoreCase(query_version, "list")) {
            println(std.fmt.comptimePrint("> {s}:", .{ansi.Fg.green("Available versions", .Underline)}));
            for (zig_index.value.object.keys(), 0..) |key, idx| {
                if (key.len == 0) continue;

                if (std.mem.eql(u8, key, "master")) {
                    const nightly_version = zig_index.value.object.get("master").?.object.get("version").?.string;
                    printlnf("\t" ++ ansi.Fg.highMagenta("Nightly: ", .Bold) ++ ansi.Fg.yellow("{s}", null), .{nightly_version});
                } else {
                    printf("\t" ++ LIGHTBLUE_STRING_TEMPLATE, .{key});
                }

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
            printlnf("> " ++ ansi.Fg.yellow("Version: ", .Bold) ++ GREEN_STRING_TEMPLATE ++ "\n> " ++ ansi.Fg.yellow("Version date: ", .Bold) ++ GREEN_STRING_TEMPLATE ++ "\n", .{ resolve_version, date.string });

            if (zig_version != null and std.mem.eql(u8, resolve_version, zig_version.?)) {
                println("> " ++ ansi.Fg.green("You are using the same version", null));
                return;
            }

            break :blk version_obj;
        }
    };

    const build = target_version.object.get(SYSTEM) orelse {
        printlnf("> " ++ ansi.Fg.red("This version is not available for your system ({s})", null), .{SYSTEM});
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
        printlnf(ansi.ClearLine ++ "\r> " ++ ansi.Fg.green("Successfully extracted to ", null) ++ ansi.Fg.magenta("{s}", .Underline), .{zig_folder});

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
