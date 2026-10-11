# LAB 2 — Linux Character Device Driver, procfs/sysfs, and BusyBox Auto-load

## Overview

LAB 2 extends the minimal ARMv7 Embedded Linux system built in LAB 1 by adding a custom Linux kernel module and integrating it into the boot process.

The project implements a character device driver named `lab2_driver` and exposes it to userspace through:

- `/dev/lab2` — character device interface
- `/proc/lab2_info` — driver statistics through procfs
- `/sys/class/lab2_class/lab2/` — individual driver attributes through sysfs

The driver is cross-compiled for ARMv7 against the Linux 5.15 source tree from LAB 1, copied into the BusyBox RootFS, automatically loaded by `/etc/init.d/rcS`, packaged into a new initramfs, and booted on QEMU `vexpress-a9`.

The final system successfully boots, loads the kernel module automatically, creates the device node, and passes character-device, procfs, and sysfs tests.

> Note: the MTD/JFFS2 section of the original lab was not completed on the current AlmaLinux host because the running host kernel does not provide `nandsim` and has JFFS2 disabled. The driver and BusyBox integration portions were completed and verified successfully.

---

## 1. Objectives

The main goals of this lab are:

1. Understand the lifecycle of a Linux kernel module.
2. Implement a complete character device driver.
3. Support `open`, `read`, `write`, and `release`.
4. Transfer data safely between kernel space and user space using `copy_to_user()` and `copy_from_user()`.
5. Protect shared driver state with a mutex.
6. Export driver statistics through procfs.
7. Export individual driver attributes through sysfs.
8. Integrate the module into the BusyBox boot sequence.
9. Automatically create `/dev/lab2`.
10. Cross-compile the module for ARMv7.
11. Package the updated RootFS as an initramfs.
12. Boot and test the complete system on QEMU.

---

## 2. Target Platform

| Component | Configuration |
|---|---|
| Architecture | ARMv7-A |
| CPU | ARM Cortex-A9 |
| QEMU machine | `vexpress-a9` |
| Linux Kernel | 5.15 |
| RootFS | BusyBox initramfs |
| Driver | `lab2_driver.ko` |
| Device node | `/dev/lab2` |
| Major number | 240 |
| procfs entry | `/proc/lab2_info` |
| sysfs class | `/sys/class/lab2_class/lab2/` |
| Host environment | AlmaLinux |
| Cross compiler | ARM GNU toolchain |

---

## 3. Repository Structure

```text
LAB 2/
├── driver/
│   ├── lab2_driver.c
│   ├── Makefile
│   ├── lab2_driver.ko
│   ├── Module.symvers
│   └── modules.order
│
├── rootfs/
│   ├── bin/
│   ├── sbin/
│   ├── usr/
│   │   └── bin/
│   │       ├── test_driver.sh
│   │       └── test_procfs.sh
│   ├── etc/
│   │   ├── inittab
│   │   └── init.d/
│   │       └── rcS
│   ├── lib/
│   │   └── modules/
│   │       └── 5.15.0/
│   │           └── lab2_driver.ko
│   └── ...
│
├── output/
│   ├── initramfs_lab2.cpio.gz
│   └── SHA256SUMS.txt
│
├── scripts/
│   ├── boot_qemu.sh
│   ├── rebuild_initramfs.sh
│   └── create_dev_nodes.sh
│
├── logs/
│   └── README.md
│
├── BUILD_INFO.txt
└── README.md
```

The Linux kernel image and Device Tree are reused from `LAB 1`.

---

## 4. System Architecture

```text
                       USER SPACE
  +--------------------------------------------------+
  | BusyBox shell                                    |
  |                                                  |
  | echo / cat <----> /dev/lab2                      |
  | cat -----------> /proc/lab2_info                 |
  | cat -----------> /sys/class/lab2_class/lab2/*    |
  +--------------------------+-----------------------+
                             |
                    system calls / VFS
                             |
                             v
                       KERNEL SPACE
  +--------------------------------------------------+
  |                 lab2_driver.ko                   |
  |                                                  |
  | file_operations                                  |
  |   - open                                         |
  |   - read                                         |
  |   - write                                        |
  |   - release                                      |
  |                                                  |
  | device_buffer[1024]                              |
  | open_count                                       |
  | mutex                                            |
  |                                                  |
  | procfs  -> /proc/lab2_info                       |
  | sysfs   -> /sys/class/lab2_class/lab2/           |
  +--------------------------------------------------+
```

---

## 5. Character Device Design

The driver registers a character device using a fixed experimental major number:

```text
major = 240
minor = 0
```

The userspace interface is:

```text
/dev/lab2
```

The device uses Linux `file_operations` to connect normal file operations to driver callbacks.

Conceptually:

```text
open("/dev/lab2")
        |
        v
     VFS layer
        |
        v
lab2_driver file_operations
        |
        +--> lab2_open()
        +--> lab2_read()
        +--> lab2_write()
        +--> lab2_release()
```

---

## 6. Data Flow

### Write

Example:

```bash
echo "Hello from userspace" > /dev/lab2
```

Flow:

```text
Userspace buffer
      |
      v
write() system call
      |
      v
VFS
      |
      v
lab2_write()
      |
      v
copy_from_user()
      |
      v
device_buffer
```

### Read

Example:

```bash
cat /dev/lab2
```

Flow:

```text
device_buffer
      |
      v
lab2_read()
      |
      v
copy_to_user()
      |
      v
Userspace buffer
      |
      v
Terminal output
```

`copy_to_user()` and `copy_from_user()` are required because userspace pointers and kernel-space pointers belong to different virtual-address contexts and must be accessed through the kernel's safe user-copy APIs.

---

## 7. Mutex Protection

The driver uses a kernel mutex to protect shared state such as:

```text
device_buffer
buffer_len
open_count
```

Without synchronization, multiple processes could access or modify the buffer at the same time, creating race conditions.

Example:

```text
Process A              Process B
---------              ---------
write("AAAA")
                       write("BBBB")
update buffer
                       update buffer
```

Without locking, the final buffer contents and counters could become inconsistent.

The mutex serializes access to critical sections.

---

## 8. procfs Interface

The driver creates:

```text
/proc/lab2_info
```

This acts as a human-readable status interface.

It reports information such as:

- driver name
- major number
- buffer size
- current data length
- open count
- last stored data

Example:

```bash
cat /proc/lab2_info
```

procfs is useful here because the information is presented as a combined driver-status report.

---

## 9. sysfs Interface

The driver also creates a sysfs device:

```text
/sys/class/lab2_class/lab2/
```

Important attributes include:

```text
buffer_len
open_count
last_data
```

Each attribute is exposed as a separate file.

Example:

```bash
cat /sys/class/lab2_class/lab2/buffer_len
cat /sys/class/lab2_class/lab2/open_count
cat /sys/class/lab2_class/lab2/last_data
```

This makes driver properties easy to access individually from scripts and applications.

---

## 10. Cross-Compiling the Kernel Module

The module is built using the Linux 5.15 kernel source tree from LAB 1.

The module Makefile uses KBuild rather than invoking GCC directly.

Typical build flow:

```bash
cd driver
make clean
make
```

Important result:

```text
lab2_driver.ko
```

The verified module format is:

```text
ELF 32-bit LSB relocatable, ARM, EABI5
```

This confirms that the module targets ARM rather than the x86-64 host.

---

## 11. RootFS Integration

The compiled module is installed into:

```text
/lib/modules/5.15.0/lab2_driver.ko
```

inside the target RootFS.

Two test scripts are included:

```text
/usr/bin/test_driver.sh
/usr/bin/test_procfs.sh
```

These scripts exercise the userspace interfaces of the driver.

---

## 12. BusyBox Boot Integration

The LAB 1 RootFS is extended so the kernel module is loaded automatically during boot.

BusyBox `init` reads:

```text
/etc/inittab
```

which executes:

```text
/etc/init.d/rcS
```

The LAB 2 `rcS` performs the following steps:

1. Mount `/proc`.
2. Mount `/sys`.
3. Mount `/tmp`.
4. Attempt to mount `devtmpfs`.
5. Ensure essential device nodes exist.
6. Set the hostname.
7. Load `lab2_driver.ko`.
8. Create `/dev/lab2`.
9. Set device permissions.
10. Continue to the BusyBox shell.

Boot flow:

```text
Linux Kernel
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
    +--> mount proc/sysfs/tmp
    |
    +--> insmod lab2_driver.ko
    |
    +--> create /dev/lab2
    |
    v
BusyBox shell
```

---

## 13. Building the LAB 2 initramfs

The updated RootFS is packaged as:

```text
output/initramfs_lab2.cpio.gz
```

Typical command:

```bash
cd rootfs
find . | cpio -H newc -o | gzip > ../output/initramfs_lab2.cpio.gz
```

The project also includes:

```text
scripts/rebuild_initramfs.sh
```

to automate this step.

---

## 14. Booting LAB 2

LAB 2 reuses the Linux kernel and Device Tree built in LAB 1.

From inside the `LAB 2` directory:

```bash
./scripts/boot_qemu.sh
```

Equivalent QEMU configuration:

```bash
qemu-system-arm   -M vexpress-a9   -cpu cortex-a9   -m 512M   -smp 2   -nographic   -kernel "../LAB 1/output/zImage"   -dtb "../LAB 1/output/vexpress-v2p-ca9.dtb"   -initrd output/initramfs_lab2.cpio.gz   -append 'console=ttyAMA0,115200 rdinit=/sbin/init mem=512M'
```

Successful initialization produced:

```text
[ LAB-02 ] Starting system initialization...
[ LAB-02 ] Loading lab2_driver module...
lab2_driver: initializing module
lab2_driver: /proc/lab2_info created
lab2_driver: loaded, major=240
[ LAB-02 ] lab2_driver loaded OK
[ LAB-02 ] /dev/lab2 created (major=240, minor=0)
[ LAB-02 ] System initialization complete!
```

The system then reached:

```text
/ #
```

---

## 15. Verification

### Module auto-load

```bash
lsmod
```

Verified result:

```text
lab2_driver ... Live ... (O)
```

The `(O)` flag indicates an out-of-tree kernel module.

This is expected because `lab2_driver` is a custom module built outside the main Linux kernel source tree.

---

### Device node

```bash
ls -la /dev/lab2
```

Verified device:

```text
character device
major = 240
minor = 0
```

---

### Character-device test

The test script performs:

- module loading when needed,
- device-node creation,
- write,
- read,
- multiple write/read cycles,
- kernel-log inspection.

Example data used during testing:

```text
Hello from userspace, LAB-02!
Message_1
Message_2
Message_3
```

Kernel logs confirmed successful calls to:

```text
open
write
read
release
```

---

### procfs/sysfs test

The test wrote:

```text
Embedded Linux Lab2 Test Data
```

Verified sysfs state:

```text
buffer_len = 30
open_count = 1
last_data = Embedded Linux Lab2 Test Data
```

The sysfs directory successfully contained:

```text
buffer_len
open_count
last_data
dev
uevent
```

---

## 16. Kernel Log Evidence

`dmesg` confirmed the complete module lifecycle and I/O operations.

Observed events included:

```text
lab2_driver: initializing module
lab2_driver: /proc/lab2_info created
lab2_driver: loaded, major=240
lab2_driver: device opened
lab2_driver: received ... bytes
lab2_driver: sent ... bytes to user
lab2_driver: device closed
lab2_driver: module unloaded
```

This confirms that the driver callbacks are actually being executed by the kernel.

---

# 17. MTD / JFFS2 Section

The original LAB 2 also contains an MTD/JFFS2 exercise using a simulated NAND flash device.

The intended flow is:

```text
nandsim
   |
   v
MTD subsystem
   |
   v
/dev/mtd0
   |
   v
JFFS2
   |
   v
mount / persistence test
```

However, this section was not completed on the current AlmaLinux host.

Checks on the running host kernel showed:

```text
mtdblock   available
nandsim    unavailable
JFFS2      disabled
```

The host kernel configuration reported:

```text
CONFIG_MTD_BLOCK=m
CONFIG_JFFS2_FS is not set
```

and the `nandsim` module was not available.

The original lab explicitly expects this section to be performed on a host kernel with `nandsim` and JFFS2 support, typically Ubuntu.

Therefore:

```text
Part A — Character driver        COMPLETED
Part B — procfs / sysfs          COMPLETED
Part C — MTD / JFFS2             NOT COMPLETED ON THIS HOST
Part D — BusyBox auto-load       COMPLETED
```

This limitation is documented rather than hidden because it reflects the actual capabilities of the host kernel used for the experiment.

---

# 18. Problems Encountered and Solutions

## Problem 1 — Host kernel does not provide `nandsim`

### Symptom

```text
modinfo: ERROR: Module nandsim not found
```

### Investigation

The host kernel and installed module packages were checked.

`mtdblock` was available, but `nandsim` was not present.

### Resolution

The MTD/JFFS2 portion was separated from the driver/QEMU work.

The rest of LAB 2 does not depend on `nandsim`, so Parts A, B and D were completed normally.

To complete Part C in the future, use:

- an Ubuntu host kernel containing `nandsim` and JFFS2,
- or a custom host kernel configured with the required MTD/JFFS2 options.

---

## Problem 2 — JFFS2 is disabled in the AlmaLinux host kernel

Kernel configuration check:

```text
# CONFIG_JFFS2_FS is not set
```

Without JFFS2 support, the host cannot mount a JFFS2 filesystem for the required persistence test.

This is a host-kernel capability issue rather than a failure in the ARM target driver.

---

## Problem 3 — Keeping the module inside RootFS synchronized

After rebuilding the driver, the copy inside the RootFS can become stale.

A binary comparison was used:

```bash
cmp driver/lab2_driver.ko rootfs/lib/modules/5.15.0/lab2_driver.ko
```

The verified files matched before the final initramfs was packaged.

---

## Problem 4 — Auto-load and test-script interaction

The final boot script automatically loads `lab2_driver`.

The original test scripts also perform `insmod`.

Running a test script after auto-load can therefore produce an already-loaded-module condition.

During full testing, the module was removed before running scripts that load it themselves.

This ensured that both the automatic boot integration and standalone test scripts could be validated.

---

## Problem 5 — Device-node permissions

The boot script sets:

```text
chmod 666 /dev/lab2
```

After unloading/reloading the module during testing, device-node permissions may differ depending on how the node is recreated.

For root-only QEMU testing this does not prevent operation, but permissions can be restored with:

```bash
chmod 666 /dev/lab2
```

---

# 19. Debugging Strategy

A useful debugging order for this project is:

```text
Module does not build
        |
        v
Check KBuild / KDIR / ARCH / CROSS_COMPILE

Module builds but insmod fails
        |
        v
Check architecture / vermagic / kernel log

Module loads but /dev/lab2 fails
        |
        v
Check major number / mknod / permissions

Read/write fails
        |
        v
Check file_operations / copy_to_user / copy_from_user

/proc fails
        |
        v
Check proc_create / seq_file callbacks

/sys fails
        |
        v
Check device_create / attribute group

Module works manually but not at boot
        |
        v
Check rootfs path / rcS / inittab / initramfs packaging
```

---

# 20. Main Outputs

## Driver source

```text
driver/lab2_driver.c
```

## Kernel module

```text
driver/lab2_driver.ko
```

## RootFS module copy

```text
rootfs/lib/modules/5.15.0/lab2_driver.ko
```

## Test scripts

```text
rootfs/usr/bin/test_driver.sh
rootfs/usr/bin/test_procfs.sh
```

## Final bootable initramfs

```text
output/initramfs_lab2.cpio.gz
```

---

# 21. Reproducibility

The repository preserves:

- driver source,
- Makefile,
- compiled ARM module,
- RootFS integration,
- BusyBox initialization files,
- test scripts,
- final initramfs,
- boot scripts,
- build metadata,
- SHA-256 hashes.

The Linux kernel and Device Tree are reused from LAB 1 to avoid duplicating large artifacts unnecessarily.

---

# 22. Final Results

| Requirement | Result |
|---|---|
| ARM kernel module build | ✅ |
| `lab2_driver.ko` ARM EABI5 | ✅ |
| Character device registration | ✅ |
| `/dev/lab2` | ✅ |
| `open()` | ✅ |
| `read()` | ✅ |
| `write()` | ✅ |
| `release()` | ✅ |
| `copy_to_user()` | ✅ |
| `copy_from_user()` | ✅ |
| Mutex protection | ✅ |
| `/proc/lab2_info` | ✅ |
| sysfs attributes | ✅ |
| BusyBox `rcS` integration | ✅ |
| Automatic module loading | ✅ |
| Automatic `/dev/lab2` creation | ✅ |
| LAB 2 initramfs packaging | ✅ |
| QEMU boot | ✅ |
| Full driver test | ✅ |
| procfs/sysfs test | ✅ |
| MTD/JFFS2 on current AlmaLinux host | ⚠️ Not supported by current host kernel |

---

# 23. What This Lab Demonstrates

LAB 1 created a bootable Embedded Linux system.

LAB 2 extends that system by introducing kernel-space development.

The complete path is now:

```text
Userspace application
        |
        v
Linux system call
        |
        v
VFS
        |
        v
Custom kernel module
        |
        +--> character device
        +--> internal buffer
        +--> procfs
        +--> sysfs
```

This project provides practical experience with:

- Linux kernel modules
- character device drivers
- major/minor numbers
- kernel/user memory boundaries
- VFS `file_operations`
- `copy_to_user()`
- `copy_from_user()`
- mutex synchronization
- procfs
- seq_file
- sysfs
- kobjects
- BusyBox init
- boot-time module loading
- ARM cross-compilation
- initramfs integration
- QEMU debugging
- kernel log analysis

It also provides the foundation for more advanced driver work such as `ioctl`, misc devices, interrupts, DMA, platform drivers and real hardware access.

---

## Status

**LAB 2 driver and BusyBox integration completed successfully.**

**MTD/JFFS2 remains pending because the current AlmaLinux host kernel does not provide the required `nandsim` and JFFS2 support.**
