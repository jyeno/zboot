# zboot

EFI stub chainloader compatible with systemd-boot's configuration files.

## How to

```sh
zig build run-qemu
```

## TODO

- Respect kernel memory requirements (loading at specific locations, etc.) even if UEFI implementation doesn't
- Use Linux UEFI protocols [like this](https://github.com/u-boot/u-boot/commit/ec80b4735a593961fe701cc3a5d717d4739b0fd0) instead of cheating with EFI stub parameters
- Nicer selection interface
- Improve Command-line editing
