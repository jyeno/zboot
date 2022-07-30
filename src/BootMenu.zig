const std = @import("std");
const uefi = std.os.uefi;
const BootEntry = @import("BootEntry.zig");
const utils = @import("utils.zig");

const L = std.unicode.utf8ToUtf16LeStringLiteral; // Like L"str" in C compilers
const File = uefi.protocols.FileProtocol;

const BootMenu = @This();

current_entry: u8 = 0,
entries: []BootEntry,
arena: std.heap.ArenaAllocator,
boot_services: *uefi.tables.BootServices,

pub fn init(allocator: std.mem.Allocator, boot_services: *uefi.tables.BootServices, entries_dir: *File) BootMenu {
    var arena = std.heap.ArenaAllocator.init(allocator);
    var buf: [4096]u8 align(8) = undefined;
    const entries = b: {
        var entries_tmp = std.ArrayList(BootEntry).init(arena.allocator());
        while (true) {
            var bufsiz = buf.len;
            entries_dir.read(&bufsiz, &buf).err() catch |e| {
                utils.putsLiteral("yo man err:");
                utils.puts(@errorName(e));
                break;
            };
            if (bufsiz == 0) break;
            const file_info = @ptrCast(*uefi.protocols.FileInfo, &buf);
            const filename = std.mem.span(file_info.getFileName());
            if (!std.mem.eql(u16, filename, L(".")) and !std.mem.eql(u16, filename, L(".."))) {
                var entry_file: *File = undefined;
                if (entries_dir.open(&entry_file, filename, File.efi_file_mode_read, File.efi_file_archive) == uefi.Status.Success) {
                    const new_entry = BootEntry.fromFile(arena.allocator(), filename, entry_file.reader()) catch |e| {
                        utils.putsLiteral("Failed to parse the following file:");
                        utils.puts16(filename);
                        utils.printf("\r\nDue to following error: {s}", .{@errorName(e)});
                        continue;
                    };
                    entries_tmp.append(new_entry) catch {
                        utils.putsLiteral("Out of memory. Entries may be missing");
                    };
                }
            }
        }
        break :b entries_tmp.toOwnedSlice();
    };

    std.sort.sort(BootEntry, entries, {}, bootEntrySortReverse);

    return .{ .arena = arena, .boot_services = boot_services, .entries = entries };
}

pub fn deinit(self: *BootMenu) void {
    self.arena.deinit();
}

pub fn selectEntry(self: *BootMenu) !BootEntry {
    while (true) {
        self.displayEntries();
        const input_event = [_]uefi.Event{
            uefi.system_table.con_in.?.wait_for_key,
        };
        var index: usize = undefined;
        try self.boot_services.waitForEvent(1, &input_event, &index).err();
        var input_key: uefi.protocols.InputKey = undefined;
        uefi.system_table.con_in.?.readKeyStroke(&input_key).err() catch continue;

        const keycode = input_key.scan_code;
        if (keycode == 1) { // up key
            if (self.current_entry == 0) {
                self.current_entry = @intCast(u8, self.entries.len - 1);
            } else {
                self.current_entry -= 1;
            }
        } else if (keycode == 2) { // down key
            if (self.current_entry == self.entries.len - 1) {
                self.current_entry = 0;
            } else {
                self.current_entry += 1;
            }
        } else {
            switch (input_key.unicode_char) {
                13 => return self.entries[self.current_entry],
                else => {},
            }
        }
    }
}

fn displayEntries(self: *const BootMenu) void {
    utils.clearScreen();
    for (self.entries) |entry, index| {
        if (index == self.current_entry) {
            utils.printf("> ", .{});
        } else {
            utils.printf("  ", .{});
        }
        utils.printf("{s}\r\n", .{entry.title.?});
    }
}

pub fn bootEntrySortReverse(_: void, lhs: BootEntry, rhs: BootEntry) bool {
    return BootEntry.order(lhs, rhs) == .gt;
}
