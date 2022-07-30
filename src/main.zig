const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const uefi = std.os.uefi;
const allocator = uefi.pool_allocator;
const File = uefi.protocols.FileProtocol;
const Device = uefi.protocols.DevicePathProtocol;
const L = std.unicode.utf8ToUtf16LeStringLiteral; // Like L"str" in C compilers

const BootEntry = @import("BootEntry.zig");
const BootMenu = @import("BootMenu.zig");
const utils = @import("utils.zig");

fn bootEntrySortReverse(_: void, lhs: BootEntry, rhs: BootEntry) bool {
    return BootEntry.order(lhs, rhs) == .gt;
}

pub fn main() usize {
    const boot_services = uefi.system_table.boot_services orelse return 1;
    utils.initOutput() catch return 1;

    // Get metadata about image
    const image_meta = boot_services.openProtocolSt(uefi.protocols.LoadedImageProtocol, uefi.handle) catch {
        utils.putsLiteral("error: can't query information about boot image");
        return 1;
    };
    // Find device where it's stored
    const root_handle = image_meta.device_handle orelse {
        utils.putsLiteral("error: can't get handle of root device");
        return 1;
    };
    const uefi_root = boot_services.openProtocolSt(uefi.protocols.SimpleFileSystemProtocol, root_handle) catch {
        utils.putsLiteral("error: can't init root volume");
        return 1;
    };

    // Get root dir
    var root_dir: *File = undefined;
    if (uefi_root.openVolume(&root_dir) != uefi.Status.Success) {
        utils.puts("error: can't open root volume");
        return 1;
    }
    var entries_dir: *File = undefined;
    if (root_dir.open(&entries_dir, L("\\loader\\entries"), File.efi_file_mode_read, File.efi_file_directory) != uefi.Status.Success) {
        utils.puts("error: can't load entries directory");
        return 1;
    }

    utils.clearScreen();

    var buf: [4096]u8 align(8) = undefined;
    const entries = b: {
        var entries_tmp = std.ArrayList(BootEntry).init(uefi.pool_allocator);
        while (true) {
            var bufsiz = buf.len;
            entries_dir.read(&bufsiz, &buf).err() catch |e| {
                utils.putsLiteral("yo man err:");
                utils.puts(@errorName(e));
                break;
            };
            if (bufsiz == 0) break;
            const file_info = @ptrCast(*uefi.protocols.FileInfo, &buf);
            const filename = mem.span(file_info.getFileName());
            if (!mem.eql(u16, filename, L(".")) and !mem.eql(u16, filename, L(".."))) {
                var entry_file: *File = undefined;
                if (entries_dir.open(&entry_file, filename, File.efi_file_mode_read, File.efi_file_archive) == uefi.Status.Success) {
                    const new_entry = BootEntry.fromFile(uefi.pool_allocator, filename, entry_file.reader()) catch |e| {
                        utils.putsLiteral("Failed to parse the following file:");
                        // _ = utils.printf("{s}\r\n", .{filename});
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
    defer uefi.pool_allocator.free(entries);
    std.sort.sort(BootEntry, entries, {}, bootEntrySortReverse);

    var menu = BootMenu.init(uefi.pool_allocator, boot_services, &entries);
    // defer menu.deinit() TODO

    // TODO: use this when implementing Linux memory requirements and co.
    //var img_file: *File = undefined;
    //root_dir.open(&img_file, entries[0].payload.linux, File.efi_file_mode_read, File.efi_file_archive).err() catch |e| {
    //    utils.puts(entries[0].payload.linux);
    //    utils.printf("File pointed to by first entry can't be loaded: {s}", .{@errorName(e)});
    //    return 1;
    //};
    //const img_contents = img_file.reader().readAllAlloc(uefi.pool_allocator, 2048 * 1024 * 1024) catch {
    //    utils.putsLiteral("out of memery");
    //    return 1;
    //};
    // TODO: real parsing
    const entry = menu.selectEntry() catch return 1;

    const root_devpath = boot_services.openProtocolSt(uefi.protocols.DevicePathProtocol, root_handle) catch |e| {
        utils.printf("Problem with root device path: {s}", .{@errorName(e)});
        return 1;
    };
    const img_devpath = root_devpath.create_file_device_path(uefi.pool_allocator, entry.payloadFilename()) catch |e| {
        utils.printf("Problem with payload device path: {s}", .{@errorName(e)});
        return 1;
    };
    var next_handle = b: {
        var tmp: ?uefi.Handle = undefined;
        boot_services.loadImage(false, uefi.handle, img_devpath, null, 0, &tmp).err() catch |e| {
            utils.printf("Error loading image: {s}", .{@errorName(e)});
            return 1;
        };
        if (tmp) |hndl| {
            break :b hndl;
        } else {
            utils.putsLiteral("Image is not loaded.");
            return 1;
        }
    };
    const next_image_meta = boot_services.openProtocolSt(uefi.protocols.LoadedImageProtocol, next_handle) catch |e| {
        utils.printf("Error loading information for payload image: {s}", .{@errorName(e)});
        return 1;
    };

    const cmdline = entry.commandLine(uefi.pool_allocator) catch {
        utils.putsLiteral("Not enough memory to load commandline as UCS-2.");
        return 1;
    };
    defer uefi.pool_allocator.free(cmdline);
    _ = utils.puts16(cmdline);
    _ = utils.putsLiteral("");
    next_image_meta.load_options = @ptrCast(*anyopaque, cmdline.ptr);
    next_image_meta.load_options_size = @intCast(u32, (cmdline.len + 1) * @sizeOf(u16));
    _ = boot_services.startImage(next_handle, null, null);

    utils.putsLiteral("I'm alive, oh no.");
    _ = uefi.system_table.boot_services.?.stall(5 * 1000 * 1000);
    return 0;
}

test {
    _ = BootEntry;
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}

test {
    _ = @import("version_order.zig");
    _ = @import("boot_entry.zig");
}
