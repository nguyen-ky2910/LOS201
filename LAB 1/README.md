# LAB 1 — Building and Booting an Embedded Linux System on ARMv7

## Overview

This project builds a minimal Embedded Linux system for an ARMv7-A Cortex-A9 target and boots it on the QEMU `vexpress-a9` machine.

Instead of using a prebuilt Linux distribution, the system is assembled manually from:

- Linux Kernel 5.15
- Device Tree for ARM Versatile Express (`vexpress-v2p-ca9.dtb`)
- U-Boot 2022.04
- BusyBox 1.35.0
- A manually constructed minimal Root Filesystem
- initramfs
- QEMU ARM system emulation

The final result is a working ARM Linux system that reaches an interactive BusyBox root shell.

---

## 1. Objectives

The main objectives of the lab are:

1. Understand the complete Embedded Linux boot sequence.
2. Cross-compile a Linux kernel for ARMv7-A.
3. Configure the kernel for the Versatile Express platform.
4. Build and test U-Boot for Cortex-A9.
5. Understand the role of the Device Tree.
6. Build BusyBox for ARM.
7. Construct a minimal Linux Root Filesystem manually.
8. Package the RootFS as initramfs.
9. Boot the complete system on QEMU.
10. Verify CPU, memory, filesystems, processes and SMP operation.
11. Practice systematic boot debugging.

---

## 2. Target Platform

| Item | Configuration |
|---|---|
| Architecture | ARMv7-A |
| CPU | ARM Cortex-A9 |
| QEMU machine | `vexpress-a9` |
| RAM | 512 MB |
| Virtual CPUs | 2 |
| Linux Kernel | 5.15 |
| Bootloader | U-Boot 2022.04 |
| Userspace | BusyBox 1.35.0 |
| Root filesystem | initramfs |
| UART console | PL011 / `ttyAMA0` |
| Baud rate | 115200 |

---

## 3. Repository Structure

```text
LAB 1/
├── configs/
│   ├── kernel.config
│   ├── busybox.config
│   └── uboot.config
├── output/
│   ├── zImage
│   ├── vexpress-v2p-ca9.dtb
│   ├── initramfs.cpio.gz
│   ├── u-boot
│   ├── u-boot.bin
│   └── SHA256SUMS.txt
├── rootfs/
│   ├── bin/
│   ├── sbin/
│   ├── usr/
│   ├── dev/
│   ├── proc/
│   ├── sys/
│   ├── tmp/
│   ├── etc/
│   │   ├── hostname
│   │   ├── passwd
│   │   ├── inittab
│   │   └── init.d/
│   │       └── rcS
│   └── init
├── scripts/
│   ├── boot_qemu.sh
│   ├── boot_uboot.sh
│   └── create_dev_nodes.sh
├── logs/
├── BUILD_INFO.txt
└── README.md
```

The full upstream Linux, U-Boot and BusyBox source trees are intentionally not committed. Only project-specific configuration files, outputs, scripts and the custom RootFS are stored.

---

## 4. High-Level Architecture

```text
                    HOST LINUX
                        |
        +---------------+---------------+
        |                               |
        v                               v
 ARM Cross Compiler                  QEMU
        |                               |
        +---------------+---------------+
                        |
                        v
             ARM Cortex-A9 / vexpress-a9
                        |
                        v
                Linux Kernel 5.15
                        |
                        v
                 Device Tree Blob
                        |
                        v
                    initramfs
                        |
                        v
                   /sbin/init
                        |
                        v
                  /etc/inittab
                        |
                        v
               /etc/init.d/rcS
                        |
                        v
                  BusyBox Shell
                        |
                        v
                       / #
```

U-Boot is built and tested separately to study the role of a real embedded bootloader. The final Linux test uses QEMU direct-kernel boot so the kernel, DTB and initramfs can be validated together.

---

# 5. Development Process

## 5.1 Cross-Compilation Environment

The host system is x86-64 while the target is ARMv7. Therefore the Linux kernel, U-Boot and BusyBox must be cross-compiled.

Typical environment variables are:

```bash
export ARCH=arm
export CROSS_COMPILE=<ARM-toolchain-prefix>
```

The exact toolchain used for the working build is recorded in:

```text
BUILD_INFO.txt
```

The key concept is:

```text
Host machine:   x86-64 Linux
Target system:  ARMv7 Cortex-A9
```

The compiler executes on the host but generates binaries for ARM.

---

# 6. Linux Kernel

## 6.1 Kernel Configuration

Linux 5.15 is configured for the ARM Versatile Express platform.

A typical starting configuration is:

```bash
make vexpress_defconfig
```

Important options include:

- ARMv7 CPU support
- ARM Versatile Express platform support
- Initial RAM filesystem / initrd support
- Device Tree support
- ARM AMBA PL011 serial driver
- SMP support

The final kernel configuration is preserved in:

```text
configs/kernel.config
```

## 6.2 Kernel Build

Typical build command:

```bash
make -j$(nproc) zImage dtbs modules
make modules_prepare
```

Important outputs:

```text
arch/arm/boot/zImage
arch/arm/boot/dts/vexpress-v2p-ca9.dtb
```

These are copied to:

```text
output/zImage
output/vexpress-v2p-ca9.dtb
```

## 6.3 Role of `zImage`

`zImage` is the compressed ARM Linux kernel image. It contains the kernel code responsible for CPU initialization, memory management, scheduling, interrupts, drivers, filesystems, processes and system calls.

At this point, however, the kernel alone is not yet a complete operating system. A userspace Root Filesystem is still required.

---

# 7. Device Tree

The project uses:

```text
output/vexpress-v2p-ca9.dtb
```

The Device Tree describes hardware information that cannot be discovered automatically by the kernel, including:

- CPU configuration
- memory regions
- UART devices
- interrupt controller
- timers
- platform peripherals
- device addresses

The kernel image and Device Tree must describe the same target platform. Using the wrong DTB may lead to incorrect memory mapping, missing peripherals, invalid interrupts, no serial console or boot failure.

---

# 8. First Kernel Boot Test

Before building the RootFS, the kernel can be booted directly using only:

- `zImage`
- `vexpress-v2p-ca9.dtb`

Conceptually:

```text
QEMU
  |
  +--> zImage
  |
  +--> vexpress-v2p-ca9.dtb
```

The kernel starts successfully but later fails because no valid Root Filesystem is available.

A typical error is:

```text
Kernel panic - not syncing:
VFS: Unable to mount root fs
```

This intermediate failure is useful because it confirms that:

1. the ARM kernel can execute,
2. the QEMU platform is correct,
3. the Device Tree is accepted,
4. userspace is still missing.

That leads directly to the RootFS stage.

---

# 9. U-Boot

## 9.1 Purpose

U-Boot is an embedded bootloader. On a real target it can:

- initialize low-level hardware,
- locate the Linux kernel,
- load the kernel into RAM,
- load the Device Tree,
- load an initramfs,
- prepare kernel command-line parameters,
- transfer control to Linux.

## 9.2 Build

U-Boot 2022.04 is configured for Versatile Express Cortex-A9.

Typical build flow:

```bash
make vexpress_ca9x4_defconfig
make -j$(nproc)
```

Generated files include:

```text
output/u-boot
output/u-boot.bin
```

The build configuration is preserved as:

```text
configs/uboot.config
```

## 9.3 U-Boot Shell

The repository provides:

```text
scripts/boot_uboot.sh
```

A successful U-Boot start reaches:

```text
=>
```

Useful commands explored in the lab include:

```text
version
bdinfo
printenv
setenv
saveenv
bootz
```

These commands help inspect the board, environment variables and boot configuration.

---

# 10. ARM Memory Map

For `vexpress-a9`, system RAM begins around:

```text
0x60000000
```

This matters when loading the kernel, DTB and initramfs manually with U-Boot.

A conceptual layout is:

```text
0x60000000  Device Tree area
0x60100000  Kernel image area
0x64000000  initramfs area
```

The selected addresses must:

- be inside valid RAM,
- not overlap,
- match the platform memory map.

Incorrect addresses may produce image corruption, invalid execution or silent boot hangs.

---

# 11. BusyBox

BusyBox provides a compact collection of Unix/Linux commands from one main executable.

Examples include:

```text
sh
ls
cat
mount
ps
hostname
reboot
```

BusyBox 1.35.0 is cross-compiled for ARM. The configuration is preserved as:

```text
configs/busybox.config
```

## 11.1 Why Static Linking Is Used

BusyBox is built as a statically linked binary.

With static linking, the binary contains the code it needs from the C library instead of depending on shared libraries during early boot.

This is useful for a minimal initramfs because it:

- reduces runtime dependencies,
- simplifies the RootFS,
- avoids missing-library failures,
- makes early userspace easier to debug.

---

# 12. Building the Minimal Root Filesystem

The RootFS is assembled manually using a minimal Linux filesystem hierarchy:

```text
/
├── bin
├── sbin
├── usr
├── dev
├── proc
├── sys
├── tmp
└── etc
```

BusyBox tools are placed into the appropriate directories. The resulting RootFS is preserved in:

```text
rootfs/
```

---

# 13. Startup Files

## 13.1 `/init`

The early init script prepares userspace and transfers control to BusyBox init.

Conceptually:

```text
Kernel
  |
  v
/init
  |
  v
/sbin/init
```

## 13.2 `/etc/inittab`

BusyBox `init` reads:

```text
/etc/inittab
```

This file defines system initialization actions. In this project it launches:

```text
/etc/init.d/rcS
```

and later provides an interactive shell.

## 13.3 `/etc/init.d/rcS`

`rcS` performs basic startup tasks, including mounting:

```text
/proc
/sys
/tmp
```

It also performs basic system initialization such as hostname setup.

These pseudo filesystems are essential because they expose kernel and system state to userspace.

---

# 14. Device Nodes

A minimal RootFS requires important device nodes such as:

```text
/dev/console
/dev/null
/dev/zero
/dev/random
```

These are special filesystem objects represented by major/minor device numbers.

Git does not preserve such device nodes in the same way as a filesystem archive. Therefore the repository provides:

```text
scripts/create_dev_nodes.sh
```

for reconstruction when necessary.

The bootable filesystem used by QEMU is also preserved inside:

```text
output/initramfs.cpio.gz
```

---

# 15. Creating initramfs

After the RootFS is complete, it is packaged using `cpio` and compressed with gzip.

Typical command:

```bash
cd rootfs
find . | cpio -H newc -o | gzip > initramfs.cpio.gz
```

The final image is stored as:

```text
output/initramfs.cpio.gz
```

Conceptually:

```text
BusyBox
   +
Filesystem hierarchy
   +
Startup configuration
   +
Device nodes
       |
       v
     RootFS
       |
     cpio
       |
     gzip
       |
       v
initramfs.cpio.gz
```

---

# 16. Final Boot Sequence

The complete boot process is:

```text
QEMU starts
    |
    v
ARM Cortex-A9 virtual machine
    |
    v
Linux Kernel starts
    |
    v
Device Tree is parsed
    |
    v
CPU / memory / drivers initialized
    |
    v
initramfs unpacked into RAM
    |
    v
Kernel starts userspace init
    |
    v
/sbin/init
    |
    v
/etc/inittab
    |
    v
/etc/init.d/rcS
    |
    v
Mount /proc, /sys and /tmp
    |
    v
BusyBox console
    |
    v
/ #
```

---

# 17. Running the Final System

From inside the `LAB 1` directory:

```bash
./scripts/boot_qemu.sh
```

Equivalent QEMU configuration:

```bash
qemu-system-arm \
  -M vexpress-a9 \
  -cpu cortex-a9 \
  -m 512M \
  -smp 2 \
  -nographic \
  -kernel output/zImage \
  -dtb output/vexpress-v2p-ca9.dtb \
  -initrd output/initramfs.cpio.gz \
  -append 'console=ttyAMA0,115200 rdinit=/sbin/init mem=512M'
```

### Main QEMU Parameters

| Parameter | Purpose |
|---|---|
| `-M vexpress-a9` | Emulate the Versatile Express A9 board |
| `-cpu cortex-a9` | Use a Cortex-A9 CPU model |
| `-m 512M` | Provide 512 MB RAM |
| `-smp 2` | Emulate two CPU cores |
| `-nographic` | Route serial console to the terminal |
| `-kernel` | Load the Linux kernel |
| `-dtb` | Load the Device Tree |
| `-initrd` | Load the initramfs |
| `console=ttyAMA0,115200` | Select the PL011 serial console |
| `rdinit=/sbin/init` | Start BusyBox init |
| `mem=512M` | Describe system RAM to Linux |

---

# 18. Successful Result

A successful boot eventually reaches:

```text
/ #
```

This prompt means:

```text
/  = current directory is the filesystem root
#  = the shell is running as root
```

At this point the system has successfully completed:

```text
Kernel boot
    ↓
Device Tree initialization
    ↓
initramfs setup
    ↓
userspace startup
    ↓
BusyBox init
    ↓
interactive shell
```

To leave QEMU when using `-nographic`:

```text
Ctrl+A, then X
```

---

# 19. Verification Commands

## Kernel and Architecture

```bash
uname -a
```

## CPU Information

```bash
cat /proc/cpuinfo
```

Focused view:

```bash
cat /proc/cpuinfo | grep -E 'processor|model|Features'
```

## RAM

```bash
cat /proc/meminfo | head -5
```

The total memory should be close to the 512 MB configured in QEMU.

## Mounted Filesystems

```bash
mount
```

This verifies pseudo filesystems such as `proc`, `sysfs` and `tmpfs`.

## Processes

```bash
ps
```

## SMP

```bash
cat /sys/devices/system/cpu/possible
```

With `-smp 2`, the expected CPU range is:

```text
0-1
```

---

# 20. Problems Encountered and Solutions

## Problem 1 — Kernel Panic: No Root Filesystem

### Symptom

The kernel starts but eventually reports a VFS failure such as:

```text
Kernel panic - not syncing:
VFS: Unable to mount root fs
```

### Cause

The kernel and DTB are valid, but Linux has no userspace filesystem to mount as `/`.

### Solution

Build BusyBox, construct the RootFS, package it as:

```text
initramfs.cpio.gz
```

and pass it to QEMU using `-initrd`.

After this change, the kernel can enter userspace successfully.

---

## Problem 2 — Incorrect Boot Addresses

### Symptom

Manual U-Boot booting may hang or fail.

### Cause

The kernel, DTB or initramfs may have been placed outside valid RAM or in overlapping regions.

### Solution

Use addresses inside the `vexpress-a9` RAM region beginning around `0x60000000` and ensure the loaded images do not overlap.

---

## Problem 3 — No Terminal Output

### Symptom

The machine appears to boot but no Linux shell is visible.

### Cause

The serial console may be configured for the wrong UART.

### Solution

Use the PL011 console:

```text
console=ttyAMA0,115200
```

with:

```text
-nographic
```

so QEMU redirects the UART console to the host terminal.

---

## Problem 4 — Userspace Cannot Start

### Cause

A dynamically linked BusyBox requires ARM shared libraries. Missing runtime libraries can prevent `/sbin/init` or `/bin/sh` from running.

### Solution

Use static linking for BusyBox so the minimal RootFS remains self-contained.

---

## Problem 5 — Device Nodes and Git

### Cause

Files such as `/dev/console` and `/dev/null` are special device nodes rather than normal files.

### Solution

Provide:

```text
scripts/create_dev_nodes.sh
```

for reconstruction, while keeping the complete bootable filesystem in:

```text
output/initramfs.cpio.gz
```

---

# 21. Debugging Strategy

The project demonstrates that boot failures are easier to debug stage by stage:

```text
QEMU does not start
        |
        v
Check QEMU binary / machine / CPU arguments

Kernel does not start
        |
        v
Check zImage / ARM architecture / DTB

Kernel starts but no console
        |
        v
Check ttyAMA0 / PL011 / -nographic

Kernel panics mounting root
        |
        v
Check initramfs / -initrd / init

/init or /sbin/init fails
        |
        v
Check permissions / BusyBox architecture / static linking

BusyBox starts but system setup is wrong
        |
        v
Check inittab / rcS / proc / sysfs / device nodes
```

This layered approach avoids treating the entire boot process as one large black box.

---

# 22. Build Artifacts

## Kernel

```text
output/zImage
```

ARM Linux kernel image.

## Device Tree

```text
output/vexpress-v2p-ca9.dtb
```

Hardware description for QEMU `vexpress-a9`.

## Root Filesystem

```text
output/initramfs.cpio.gz
```

Compressed bootable RootFS.

## U-Boot

```text
output/u-boot
output/u-boot.bin
```

Bootloader artifacts.

---

# 23. Reproducibility

The exact project configuration is preserved in:

```text
configs/kernel.config
configs/busybox.config
configs/uboot.config
```

Build environment information is stored in:

```text
BUILD_INFO.txt
```

SHA-256 hashes of important outputs are stored in:

```text
output/SHA256SUMS.txt
```

These files make it easier to identify the exact working build configuration.

---

# 24. Why Upstream Source Trees Are Not Included

The full source trees for:

- Linux Kernel 5.15
- U-Boot 2022.04
- BusyBox 1.35.0

are not duplicated in this repository because they are large upstream open-source projects.

Instead, this repository preserves the project-specific work:

```text
configuration files
       +
compiled artifacts
       +
custom RootFS
       +
startup configuration
       +
boot scripts
       +
build metadata
```

This keeps the repository compact while still documenting the complete implementation.

---

# 25. Final Results

| Requirement | Result |
|---|---|
| ARM cross-compilation environment | ✅ |
| Linux Kernel 5.15 build | ✅ |
| ARMv7 `zImage` | ✅ |
| Cortex-A9 Device Tree | ✅ |
| U-Boot build | ✅ |
| U-Boot shell / environment exploration | ✅ |
| BusyBox ARM build | ✅ |
| Static userspace | ✅ |
| Minimal RootFS | ✅ |
| BusyBox startup configuration | ✅ |
| initramfs packaging | ✅ |
| QEMU `vexpress-a9` boot | ✅ |
| Two-core SMP configuration | ✅ |
| Interactive BusyBox root shell | ✅ |

Final working boot path:

```text
ARM Cortex-A9
      ↓
Linux Kernel 5.15
      ↓
Device Tree
      ↓
initramfs
      ↓
BusyBox init
      ↓
BusyBox shell
      ↓
/ #
```

---

# 26. What I Learned

This lab demonstrates that an Embedded Linux system is not only a kernel. A complete bootable system requires several layers to agree on the same architecture and platform:

```text
Cross Compiler
      +
Bootloader
      +
Linux Kernel
      +
Device Tree
      +
Root Filesystem
      +
Init System
      +
Console
```

The project provides practical experience with:

- ARMv7 architecture
- Cortex-A9
- cross-compilation
- Linux KBuild
- kernel configuration
- Device Tree
- U-Boot
- memory mapping
- BusyBox
- Linux filesystem hierarchy
- initramfs
- BusyBox init
- QEMU system emulation
- serial consoles
- SMP
- boot-log analysis
- low-level Linux debugging

The resulting system is also the foundation for later Embedded Linux work involving kernel modules, character devices, procfs, sysfs and custom device drivers.

---

## Final Status

**LAB 1 — Completed successfully.**
