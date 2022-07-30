const std = @import("std");
const uefi = std.os.uefi;
const BootEntry = @import("BootEntry.zig");
const utils = @import("utils.zig");

const BootMenu = @This();

current_entry: u8 = 0,
entries: *const []BootEntry,
allocator: std.mem.Allocator,
boot_services: *uefi.tables.BootServices,

// TODO should read and generate entries
pub fn init(allocator: std.mem.Allocator, boot_services: *uefi.tables.BootServices, entries: *const []BootEntry) BootMenu {
    return .{ .allocator = allocator, .boot_services = boot_services, .entries = entries };
}

pub fn deinit(self: *BootMenu) void {
    self.allocator.free(self.entries);
}

// planning, have a while waiting for the key entered
// after that reset the screen and print the values again
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
                13 => return self.entries.*[self.current_entry],
                else => {},
            }
        }
    }
}

fn displayEntries(self: *const BootMenu) void {
    utils.clearScreen();
    for (self.entries.*) |entry, index| {
        if (index == self.current_entry) {
            utils.printf("> ", .{});
        } else {
            utils.printf("  ", .{});
        }
        utils.printf("{s}\r\n", .{entry.title.?});
    }
}
