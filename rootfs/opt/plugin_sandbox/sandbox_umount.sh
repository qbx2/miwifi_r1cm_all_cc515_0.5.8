#!/bin/sh
sandbox_dir=/userdisk/debug_app

umount $sandbox_dir/proc &> /dev/kmsg
umount $sandbox_dir/dev/pts &> /dev/kmsg
umount $sandbox_dir/dev &> /dev/kmsg
umount $sandbox_dir/lib &> /dev/kmsg
umount $sandbox_dir/bin &> /dev/kmsg
umount $sandbox_dir/usr/lib &> /dev/kmsg
