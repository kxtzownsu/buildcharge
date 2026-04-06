# buildcharge

buildroot-like project that allows you to build a mainline linux kernel & initramfs compatible with depthcharge (also works on QEMU for testing)

>[!IMPORTANT]
>The name of this project is NOT finalized and may change at any point. To submit name requests, dm me on discord: [@kxtzownsu](https://discord.com/users/952792525637312552)

## Building
Usage:
```bash
make <architecture> <variables>
# acceptable architectures are x86_64 and arm64/aarch64 (identical)
```

## Important variables:
Note, `bool` means 0 or 1, not true or false. <br>
`KERNEL_VERSION` (int), the ChromeOS kernver to give the kernel. <br>
`RECOVERY` (bool), whether or not to sign with recovery keys. <br>
`USE_ALL_CORES` (bool), whether to use all CPU cores to compile the kernel (uses half if false).

## Cleaning
`make clean-<architecture>`: cleans bzimage, initramfs, and final kernel for \<arch\> <br>
`make fullclean`: cleans everything (will require re-downloading build env, recompiling kernel, etc..) <br>

## Configuration
`USE_DEFAULT_CONFIG` (bool), whether or not to regenerate the .config from the default (default true). <br>
`make menuconfig`: generates .config with a TUI (`make <arch>` will create it from the defaults if it doesn't exist, so this is optional)

## Licensing
The project is licensed under the GPLv2 license with the exception of the following folders:
- `scripts/kconfig`: All Right Reserved (c) kxtzownsu 2026
