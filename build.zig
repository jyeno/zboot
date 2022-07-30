const std = @import("std");
const Target = std.Target;

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("bootx64", "src/main.zig");
    exe.setTarget(.{
        .cpu_arch = Target.Cpu.Arch.x86_64,
        .os_tag = Target.Os.Tag.uefi,
        .abi = Target.Abi.msvc,
    });
    exe.setOutputDir("fat/efi/boot/");
    exe.setBuildMode(mode);
    exe.install();

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);

    const run_step = b.step("run", "Run project in QEMU");

    const custom_bios = b.option([]const u8, "bios", "custom bios uefi path for QEMU");

    const ovmf_code_bios = blk: {
        if (custom_bios) |bios_path| break :blk bios_path;

        const bios_possible_paths: []const []const u8 = &.{
            "/usr/share/edk2-ovmf/OVMF_CODE.fd",
            "/usr/share/edk2-ovmf/x64/OVMF_CODE.fd",
        };
        for (bios_possible_paths) |path| {
            std.os.access(path, std.os.F_OK) catch continue;
            break :blk path;
        }
        unreachable; // Cant find bios ovmf_code to run step, consider using -Dbios PATH"
    };

    const qemu_args = &.{
        "qemu-system-x86_64",
        "-enable-kvm",
        "-bios",
        ovmf_code_bios,
        "-hdd",
        "fat::rw:./fat",
        "-display",
        "sdl",
        "-m",
        "1024",
        "-serial",
        "stdio",
    };

    const run_qemu = b.addSystemCommand(qemu_args);
    run_step.dependOn(&run_qemu.step);
    run_qemu.step.dependOn(&exe.step);
}
