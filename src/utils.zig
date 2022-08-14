const std = @import("std");
const File = uefi.protocols.FileProtocol;
const mem = std.mem;
const uefi = std.os.uefi;
const L = std.unicode.utf8ToUtf16LeStringLiteral; // Like L"str" in C compilers

var con_out: *uefi.protocols.SimpleTextOutputProtocol = undefined;

// needs to be executed before any other function that has output
pub fn initOutput() !void {
    con_out = uefi.system_table.con_out orelse return error.OutputNotEnabled;
}

pub fn clearScreen() void {
    _ = con_out.clearScreen();
}

pub fn puts(msg: []const u8) void {
    for (msg) |c| {
        // https://github.com/ziglang/zig/issues/4372
        const c_ = [2]u16{ c, 0 };
        _ = con_out.outputString(@ptrCast(*const [1:0]u16, &c_));
    }
    _ = con_out.outputString(&[_:0]u16{ '\r', '\n', 0 });
}

pub fn puts16(msg: [:0]const u16) void {
    _ = con_out.outputString(msg);
    _ = con_out.outputString(&[_:0]u16{ '\r', '\n', 0 });
}

pub fn putsLiteral(comptime msg: []const u8) void {
    _ = con_out.outputString(L(msg ++ "\r\n"));
}

pub fn moveCursor(column: usize, row: usize) void {
    _ = con_out.setCursorPosition(column, row);
}

pub fn printf(comptime format: []const u8, args: anytype) void {
    var buf: [128]u8 = undefined;
    const ret = std.fmt.bufPrint(&buf, format, args) catch {
        putsLiteral("[[not enough memory to display message]]");
        return;
    };
    for (ret) |c| {
        // https://github.com/ziglang/zig/issues/4372
        const c_ = [2]u16{ c, 0 };
        _ = con_out.outputString(@ptrCast(*const [1:0]u16, &c_));
    }
}

pub fn getFileInfoAlloc(alloc: mem.Allocator, file: *File) !*uefi.protocols.FileInfo {
    var bufsiz: usize = 256;
    var ret = try alloc.alignedAlloc(u8, 8, 256);
    while (true) {
        file.getInfo(&uefi.protocols.FileInfo.guid, &bufsiz, ret.ptr).err() catch |e| switch (e) {
            error.BufferTooSmall => {
                ret = try alloc.realloc(ret, bufsiz);
                continue;
            },
            else => return e,
        };
        break;
    }
    return @ptrCast(*uefi.protocols.FileInfo, ret.ptr);
}
