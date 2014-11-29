#!/bin/sh
sandbox_dir=/userdisk/debug_app

umount $sandbox_dir/proc &> /dev/kmsg
umount $sandbox_dir/dev &> /dev/kmsg
umount $sandbox_dir/dev/pts &> /dev/kmsg
umount $sandbox_dir/bin &> /dev/kmsg
umount $sandbox_dir/lib &> /dev/kmsg
umount $sandbox_dir/usr/lib &> /dev/kmsg


mkdir -p $sandbox_dir/proc &> /dev/kmsg
mkdir -p $sandbox_dir/dev &> /dev/kmsg
mkdir -p $sandbox_dir/dev/pts &> /dev/kmsg
mkdir -p $sandbox_dir/bin &> /dev/kmsg
mkdir -p $sandbox_dir/lib &> /dev/kmsg
mkdir -p $sandbox_dir/usr/lib &> /dev/kmsg

mount -t proc proc $sandbox_dir/proc &> /dev/kmsg
mount -t devtmpfs devtmpfs $sandbox_dir/dev &> /dev/kmsg
mount -t devpts devpts $sandbox_dir/dev/pts &> /dev/kmsg
mount --bind -r /lib $sandbox_dir/lib &> /dev/kmsg
mount --bind -r /bin $sandbox_dir/bin &> /dev/kmsg
mount --bind -r /usr/lib $sandbox_dir/usr/lib &> /dev/kmsg
