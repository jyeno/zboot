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
    utils.clearScreen();
    for (self.entries) |entry| {
        utils.printf("  {s}\r\n", .{entry.title.?});
    }
    while (true) {
        self.enableCurrentLineSelection(true);

        const input_key = self.readKey() catch continue;
        const keycode = input_key.scan_code;

        self.enableCurrentLineSelection(false);
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
                'e' => {
                    self.editCurrentEntryOptions() catch |err| switch (err) {
                        error.editCanceled => continue,
                        else => return err,
                    };
                    return self.entries[self.current_entry];
                },
                '1'...'9' => {
                    const num = @intCast(u8, input_key.unicode_char) - '1';
                    if (num >= self.entries.len) continue;

                    return self.entries[num];
                },
                else => {},
            }
        }
    }
}

// TODO improve, the line centered at middle of screen
fn enableCurrentLineSelection(self: *const BootMenu, is_selected: bool) void {
    utils.moveCursor(0, self.current_entry);
    if (is_selected) {
        utils.printf(">", .{});
    } else {
        utils.printf(" ", .{});
    }
}

fn editCurrentEntryOptions(self: *BootMenu) !void {
    var options = try self.arena.allocator().dupe(u8, self.entries[self.current_entry].options.?);
    var array = std.ArrayList(u8).fromOwnedSlice(self.arena.allocator(), options);
    defer array.deinit();

    var size: usize = array.items.len;
    var pos: usize = size;
    // TODO set attribute to differentiate the line edit
    utils.moveCursor(1, self.entries.len + 2);
    utils.enableCursor(false);
    utils.printf("{s}", .{array.items});
    const rowEditor = self.entries.len + 2;
    while (true) {
        utils.moveCursor(pos, rowEditor);
        const input_key = self.readKey() catch continue;

        if (input_key.scan_code != 0) {
            switch (input_key.scan_code) {
                0x03 => { // right arrow
                    if (pos < size) pos += 1;
                },
                0x04 => { // left arrow
                    if (pos > 0) pos -= 1;
                },
                0x05 => pos = 0, // home key
                0x06 => pos = size, // end key
                0x08 => { // delete key
                    if (size == 0 or pos == size) continue;

                    _ = array.orderedRemove(pos);
                    size -= 1;
                    pos -= 1;
                    utils.printf("{s} ", .{array.items[pos..size]});
                },
                0x17 => { // ESC key, exit without changing the options
                    utils.moveCursor(1, rowEditor);
                    for (array.items) |_| {
                        utils.printf(" ", .{});
                    }
                    return error.editCanceled;
                },
                else => {},
            }
        } else {
            switch (input_key.unicode_char) {
                8 => { // delete from buffer
                    if (pos == 0) continue;

                    _ = array.orderedRemove(pos - 1);
                    size -= 1;
                    pos -= 1;
                    utils.printf("{s} ", .{array.items[pos - 1 .. size]});
                },
                13 => break, // Enter key
                27...127 => { // valid range of printable ASCII chararacters
                    try array.insert(pos, @intCast(u8, input_key.unicode_char));
                    utils.printf("{s}", .{array.items[pos - 1 .. size]});
                    pos += 1;
                    size += 1;
                },
                else => {},
            }
        }
    }
    // as it is used the arena allocator, we dont need to free'd the old options
    self.entries[self.current_entry].options = array.toOwnedSlice();
}

fn readKey(self: *const BootMenu) !uefi.protocols.InputKey {
    const input_event = [_]uefi.Event{
        uefi.system_table.con_in.?.wait_for_key,
    };
    var index: usize = undefined;
    try self.boot_services.waitForEvent(1, &input_event, &index).err();
    var input_key: uefi.protocols.InputKey = undefined;
    try uefi.system_table.con_in.?.readKeyStroke(&input_key).err();
    return input_key;
}

fn bootEntrySortReverse(_: void, lhs: BootEntry, rhs: BootEntry) bool {
    return BootEntry.order(lhs, rhs) == .gt;
}
