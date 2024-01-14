const std = @import("std");
const json = std.json;
const http = std.http;
const path = std.fs.path;
const builtin = @import("builtin");
const os = std.os;

const detect = @import("detect.zig");

const ZIG_VERSION_INDEX = "https://ziglang.org/download/index.json";
const MAX_SIZE: usize = 1024 * 1024 * 1024;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut();
    const stdout_writer = stdout.writer();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        stdout_writer.print("Usage: zigu <latest | nightly | [version]>\n", .{}) catch {};
        return;
    }

    var zig_index_json: ?json.Parsed(json.Value) = null;
    defer {
        if (zig_index_json) |*j| {
            j.deinit();
        }
    }

    var client = http.Client{ .allocator = allocator, .next_https_rescan_certs = true };
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
        stdout_writer.print("Zig exit with code: {d}\n", .{result.term.Exited}) catch {};
        return;
    }

    const zig_output = try json.parseFromSlice(json.Value, allocator, result.stdout, .{});
    defer zig_output.deinit();

    const zig_version = zig_output.value.object.get("version");
    if (zig_version) |v| {
        stdout_writer.print("Current Zig Version: {s}\n", .{v.string}) catch {};
        if (std.mem.eql(u8, v.string, query_version)) {
            stdout_writer.writeAll("Already up to date\n") catch {};
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
        stdout_writer.writeAll("Zig folder not found. Will extract to `zig` in current directory") catch {};
    } else {
        stdout_writer.print("Zig folder: {s}\n", .{zig_folder}) catch {};
    }

    var ffi_system = detect.arch_os();
    defer detect.free_string(ffi_system.ptr, ffi_system.len);
    const system = ffi_system.toSlice();
    stdout_writer.print("Your system is: {s}\n", .{system}) catch {};

    request_thread.join();

    if (zig_index_json == null) {
        stdout_writer.writeAll("Something went wrong while getting all zig versions\n") catch {};
        return;
    }

    const zig_index = zig_index_json.?;

    const target_version = blk: {
        if (std.mem.eql(u8, query_version, "nightly")) {
            const master = zig_index.value.object.get("master") orelse {
                stdout_writer.writeAll("Nightly version not found\n") catch {};
                return;
            };

            const master_version = master.object.get("version").?;
            stdout_writer.print("Nightly version: {s}\n", .{master_version.string}) catch {};

            const master_date = master.object.get("date").?;
            stdout_writer.print("Nightly version date: {s}\n", .{master_date.string}) catch {};

            if (zig_version != null and std.mem.eql(u8, master_version.string, zig_version.?.string)) {
                stdout_writer.writeAll("You are using the latest nightly\n") catch {};
                return;
            }

            break :blk master;
        } else if (std.mem.eql(u8, query_version, "latest")) {
            const keys = zig_index.value.object.keys();

            // Dirty way to get latest version
            // MAYBE:  TODO:  Implement version sorting so we can get latest version properly
            const latest = keys[1];

            stdout_writer.print("Latest version: {s}\n", .{latest}) catch {};

            const latest_version = zig_index.value.object.get(latest).?;
            const latest_date = latest_version.object.get("date").?;
            stdout_writer.print("Latest version date: {s}\n", .{latest_date.string}) catch {};

            if (zig_version != null and std.mem.eql(u8, latest, zig_version.?.string)) {
                stdout_writer.writeAll("You are using the latest nightly\n") catch {};
                return;
            }

            break :blk latest_version;
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

                stdout_writer.writeAll("Version not found\n") catch {};
                return;
            };

            const date = version_obj.object.get("date").?;
            stdout_writer.print("Version: {s}\nVersion date: {s}\n", .{ resolve_version, date.string }) catch {};

            if (zig_version != null and std.mem.eql(u8, resolve_version, zig_version.?.string)) {
                stdout_writer.writeAll("You are using the same version\n") catch {};
                return;
            }

            break :blk version_obj;
        }
    };

    const build = target_version.object.get(system) orelse {
        stdout_writer.print("This version is not available for your system ({s})\n", .{system}) catch {};
        return;
    };
    const file_url = build.object.get("tarball").?.string;

    stdout_writer.print("Download link for your system: {s}\n", .{file_url}) catch {};
    stdout_writer.writeAll("Downloading...") catch {};

    const downloaded_file = try get(&client, &headers, file_url);
    defer allocator.free(downloaded_file);

    const cwd = std.fs.cwd();
    const file_name = path.basename(file_url);

    try cwd.writeFile2(.{
        .data = downloaded_file,
        .sub_path = file_name,
    });

    try cwd.makePath(zig_folder);

    stdout_writer.print("\rExtracting to {s}...", .{zig_folder}) catch {};

    const tar = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "tar", "-xf", file_name, "-C", zig_folder, "--strip-components", "1" },
    });

    if (tar.term != .Exited or tar.term.Exited != 0) {
        stdout_writer.writeAll("\rSomething went wrong while extracting tarball\n") catch {};
        stdout_writer.print("Tar error: {s}\n", .{tar.stderr}) catch {};
    } else {
        stdout_writer.print("\rSuccessfully extracted to {s}\n", .{zig_folder}) catch {};
    }

    cwd.deleteFile(file_name) catch {};
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

    const body = try request.reader().readAllAlloc(client.allocator, MAX_SIZE);
    return body;
}
