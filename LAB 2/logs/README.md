# LAB 2 Logs

This directory is reserved for raw execution logs.

Verified during the completed run:

- QEMU boot succeeded.
- lab2_driver was automatically loaded by rcS.
- /dev/lab2 was created with major 240 and minor 0.
- Character-device read/write tests passed.
- /proc/lab2_info worked.
- sysfs attributes buffer_len, open_count and last_data worked.
- dmesg confirmed open/read/write/release operations.

The MTD/JFFS2 test was not executed because the current AlmaLinux host kernel does not provide nandsim and has JFFS2 disabled.
