# LAB 01 — Building an Embedded Linux System on ARMv7

## Overview

This project builds a minimal Embedded Linux system from individual components and boots it on an emulated ARM Cortex-A9 platform using QEMU.

Instead of using a prebuilt Linux distribution, the system is assembled manually from:

- Linux Kernel 5.15
- Device Tree for ARM Versatile Express
- U-Boot 2022.04
- BusyBox 1.35.0
- Minimal Root Filesystem
- initramfs
- QEMU vexpress-a9

The final result is a working ARMv7 Linux system that boots successfully into an interactive BusyBox root shell.

---

## Objectives

The main goals of this lab are:

1. Understand the complete Embedded Linux boot sequence.
2. Cross-compile Linux for ARMv7-A.
3. Build and test U-Boot for Cortex-A9.
4. Understand the purpose of the Device Tree.
5. Build a minimal BusyBox userspace.
6. Construct a Root Filesystem manually.
7. Package the RootFS as initramfs.
8. Boot the complete system using QEMU.
9. Verify CPU, memory, filesystem and process information.
10. Practice debugging the Linux boot process.

---

## Target Platform

| Component | Configuration |
|---|---|
| Architecture | ARMv7-A |
| CPU | ARM Cortex-A9 |
| QEMU machine | vexpress-a9 |
| RAM | 512 MB |
| CPU cores | 2 |
| Linux Kernel | 5.15 |
| Bootloader | U-Boot 2022.04 |
| Userspace | BusyBox 1.35.0 |
| Root filesystem | initramfs |
| Console | PL011 UART / ttyAMA0 |
| Baud rate | 115200 |

---

## System Architecture

```text
Host Linux
    │
    ├── ARM Cross Compiler
    ├── KBuild / Make
    └── QEMU
          │
          ▼
QEMU vexpress-a9 / Cortex-A9
          │
          ▼
Linux Kernel 5.15
          │
          ├── Device Tree
          │
          ▼
      initramfs
          │
          ▼
     /sbin/init
          │
          ▼
    /etc/inittab
          │
          ▼
 /etc/init.d/rcS
          │
          ▼
    BusyBox Shell
          │
          ▼
         / #
```

---

## 1. Linux Kernel

The Linux 5.15 kernel was configured and cross-compiled for the ARM Versatile Express platform.

Important kernel features include:

- ARMv7 CPU support
- Versatile Express platform support
- Device Tree support
- Initial RAM filesystem support
- PL011 serial console support
- SMP support

The main kernel artifact is:

```text
output/zImage
```

The working build produced a zImage of approximately 4.9 MB.

---

## 2. Device Tree

The project uses:

```text
output/vexpress-v2p-ca9.dtb
```

The Device Tree describes hardware information that the kernel needs during boot, including CPU topology, memory layout, UART, interrupt controllers and platform peripherals.

Using the correct DTB is essential because the kernel and Device Tree must describe the same hardware platform.

---

## 3. U-Boot

U-Boot 2022.04 was built for the Versatile Express Cortex-A9 platform.

Generated artifacts include:

```text
output/u-boot
output/u-boot.bin
```

U-Boot was used to study the bootloader environment and commands such as:

```text
version
bdinfo
printenv
setenv
saveenv
bootz
```

For the final system test, QEMU direct kernel boot is used so the kernel, DTB and initramfs can be tested directly.

---

## 4. ARM Memory Map

The vexpress-a9 platform maps RAM starting near:

```text
0x60000000
```

This matters when loading the Linux kernel, Device Tree and initramfs manually from U-Boot.

Incorrect addresses can cause invalid execution, corrupted images or overlap between boot components.

---

## 5. BusyBox

BusyBox provides a compact userspace containing common Linux utilities such as:

```text
sh
ls
cat
mount
ps
hostname
reboot
```

BusyBox was built as a statically linked ARM binary.

Static linking avoids dependency on external shared libraries during early boot and makes the initramfs self-contained.

---

## 6. Minimal Root Filesystem

The RootFS was assembled manually using a minimal Linux filesystem hierarchy:

```text
/
├── bin/
├── sbin/
├── usr/
├── dev/
├── proc/
├── sys/
├── tmp/
├── etc/
└── init
```

Important initialization files include:

```text
/init
/etc/inittab
/etc/init.d/rcS
/etc/passwd
/etc/hostname
```

The startup sequence is:

```text
Kernel
  ↓
/sbin/init
  ↓
/etc/inittab
  ↓
/etc/init.d/rcS
  ↓
BusyBox shell
```

---

## 7. initramfs

The complete RootFS was packaged into:

```text
output/initramfs.cpio.gz
```

The resulting archive is approximately 1.1 MB.

At boot time QEMU loads this archive into memory and Linux uses it as the initial root filesystem.

---

## 8. Complete Boot Flow

```text
QEMU starts virtual ARM hardware
              ↓
Linux Kernel starts
              ↓
Device Tree is parsed
              ↓
CPU and peripherals are initialized
              ↓
initramfs is unpacked
              ↓
/sbin/init starts
              ↓
/etc/inittab is parsed
              ↓
/etc/init.d/rcS runs
              ↓
proc, sysfs and tmpfs are mounted
              ↓
BusyBox shell starts
              ↓
             / #
```

---

## 9. Running the System

From the repository root:

```bash
cd "LAB 1"
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

A successful boot reaches:

```text
/ #
```

This prompt is the root shell of the ARM Linux system running inside QEMU.

Exit QEMU with:

```text
Ctrl+A, then X
```

---

## 10. Verification

Useful commands inside QEMU include:

```bash
uname -a
cat /proc/cpuinfo
cat /proc/cpuinfo | grep -E 'processor|model|Features'
cat /proc/meminfo | head
mount
ps
cat /sys/devices/system/cpu/possible
```

With QEMU configured using `-smp 2`, the expected CPU range is:

```text
0-1
```

---

## 11. Problems Encountered and Solutions

### Problem 1 — Kernel panic without RootFS

The first direct kernel test booted the ARM kernel but eventually failed with a VFS kernel panic.

Cause: the kernel and DTB were available, but no userspace root filesystem had been supplied.

Solution: build BusyBox, create a minimal RootFS, package it as initramfs and pass it to QEMU using `-initrd`.

### Problem 2 — Correct ARM memory addresses

The vexpress-a9 memory map differs from older Versatile platforms.

Using incorrect U-Boot load addresses can cause image overlap or execution outside valid RAM.

Solution: use addresses inside the vexpress-a9 RAM region beginning near `0x60000000`.

### Problem 3 — Console output

The board uses the ARM PL011 UART.

If the kernel receives the wrong console parameter, Linux can run without displaying useful output.

Solution: use:

```text
console=ttyAMA0,115200
```

together with QEMU `-nographic`.

### Problem 4 — Userspace shared-library dependencies

A dynamically linked BusyBox requires ARM shared libraries inside the RootFS.

Missing libraries can prevent `/sbin/init` or `/bin/sh` from executing.

Solution: build BusyBox statically so that the minimal root filesystem remains self-contained.

### Problem 5 — Device nodes and Git

Special Linux device nodes such as `/dev/console` and `/dev/null` cannot be represented as ordinary files in Git.

The repository therefore includes:

```text
scripts/create_dev_nodes.sh
```

The bootable `initramfs.cpio.gz` also preserves the complete filesystem used by QEMU.

---

## 12. Results

The final implementation successfully achieved:

| Component | Result |
|---|---|
| Linux Kernel 5.15 ARM build | ✅ |
| Cortex-A9 Device Tree | ✅ |
| U-Boot build | ✅ |
| U-Boot console | ✅ |
| BusyBox ARM build | ✅ |
| Minimal RootFS | ✅ |
| initramfs packaging | ✅ |
| QEMU ARM boot | ✅ |
| Two-core SMP boot | ✅ |
| BusyBox root shell | ✅ |

Final boot chain:

```text
Kernel
 → Device Tree
 → initramfs
 → /sbin/init
 → inittab
 → rcS
 → BusyBox shell
```

---

## 13. Repository Structure

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
├── scripts/
│   ├── boot_qemu.sh
│   ├── boot_uboot.sh
│   └── create_dev_nodes.sh
├── BUILD_INFO.txt
└── README.md
```

---

## 14. Reproducibility

Build configuration files are preserved in:

```text
configs/kernel.config
configs/busybox.config
configs/uboot.config
```

Environment information is stored in:

```text
BUILD_INFO.txt
```

Checksums for important output artifacts are stored in:

```text
output/SHA256SUMS.txt
```

The large upstream Linux Kernel, U-Boot and BusyBox source trees are intentionally not duplicated in this repository.

Only project-specific configurations, binaries, RootFS content and scripts are preserved.

---

## 15. What I Learned

This lab demonstrates that an Embedded Linux system is the result of several independent layers working together:

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

The project provided practical experience with ARM architecture, cross-compilation, KBuild, Device Tree, bootloaders, memory mapping, BusyBox, initramfs, Linux filesystem hierarchy, QEMU and low-level boot debugging.

It also provides the working base system required for later labs involving Linux kernel modules and custom device drivers.

---

## Final Status

**LAB 01 successfully completed.**
