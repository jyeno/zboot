const std = @import("std");
const Target = std.Target;

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    // efi binary
    const efi = b.addExecutable("bootx64", "src/main.zig");
    efi.setTarget(.{
        .cpu_arch = Target.Cpu.Arch.x86_64,
        .os_tag = Target.Os.Tag.uefi,
        .abi = Target.Abi.msvc,
    });
    efi.setOutputDir("fat/efi/boot/");
    efi.setBuildMode(mode);
    efi.install();

    const efi_tests = b.addTest("src/main.zig");
    efi_tests.setBuildMode(mode);

    const test_efi_step = b.step("test-efi", "Run unit tests");
    test_efi_step.dependOn(&efi_tests.step);

    const qemu_step = b.step("run-qemu", "Run project in QEMU");

    const prefix = b.option([]const u8, "install-prefix", "custom install prefix path");
    _ = prefix;

    const qemu_args = &.{
        "qemu-system-x86_64",
        "-enable-kvm",
        "-bios",
        "OVMF.fd",
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
    qemu_step.dependOn(&run_qemu.step);
    run_qemu.step.dependOn(&efi.step);
}
