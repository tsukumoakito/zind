const std = @import("std");
const mem = std.mem;
const ascii = std.ascii;
const Io = std.Io;
const File = Io.File;
const Dir = Io.Dir;
const Child = std.process.Child;
const Allocator = mem.Allocator;

pub const ParseError = error{
    FileNotFound,
    ReadError,
    VersionNotFound,
    BufferTooSmall,
    InvokeError,
};

pub fn findZigVersion(allocator: Allocator, io: Io, exe_path: []const u8, out_buffer: []u8) ParseError![]const u8 {
    const cwd = Dir.cwd();

    const file = Dir.openFile(cwd, io, exe_path, .{}) catch return findZigVersionByInvoke(allocator, io, exe_path, out_buffer);
    defer file.close(io);

    var stream_buffer: [16384]u8 = undefined;
    var reader = file.reader(io, &stream_buffer);

    while (true) {
        const chunk = reader.interface.take(8192) catch break;
        if (chunk.len == 0) break;

        var offset: usize = 0;
        while (mem.find(u8, chunk[offset..], "zig ")) |pos| {
            const start = offset + pos + 4;
            const len = findVersionLength(chunk[start..]);

            if (len > 0) {
                const version = chunk[start .. start + len];
                if (version.len > out_buffer.len) return error.BufferTooSmall;
                @memcpy(out_buffer[0..version.len], version);
                return out_buffer[0..version.len];
            }
            offset = start;
        }
        if (chunk.len < 8192) break;
    }

    return findZigVersionByInvoke(allocator, io, exe_path, out_buffer);
}

fn findZigVersionByInvoke(allocator: Allocator, io: Io, exe_path: []const u8, out_buffer: []u8) ParseError![]const u8 {
    var child = std.process.spawn(io, .{
        .argv = &[_][]const u8{ exe_path, "version" },
        .stdout = .pipe,
        .stderr = .ignore,
        .stdin = .ignore,
    }) catch return error.InvokeError;

    const stdout_file = child.stdout orelse return error.InvokeError;
    defer stdout_file.close(io);

    var stream_buffer: [1024]u8 = undefined;
    var reader = stdout_file.reader(io, &stream_buffer);

    const output = reader.interface.allocRemaining(allocator, .limited(out_buffer.len)) catch return error.ReadError;
    defer allocator.free(output);

    const term = child.wait(io) catch return error.InvokeError;
    if (term != .exited or term.exited != 0) return error.InvokeError;

    const raw_v = mem.trim(u8, output, " \n\r\t");
    if (raw_v.len == 0) return error.VersionNotFound;
    if (raw_v.len > out_buffer.len) return error.BufferTooSmall;

    @memcpy(out_buffer[0..raw_v.len], raw_v);
    return out_buffer[0..raw_v.len];
}

fn findVersionLength(bytes: []const u8) usize {
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        const c = bytes[i];
        if (!ascii.isDigit(c) and c != '.' and c != '-' and c != '+') break;
    }
    return i;
}
