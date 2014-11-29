#!/bin/sh

root_path=$1
root_bin=$root_path/bin
root_lib=$root_path/lib
root_user=$root_path/usr

umount $root_lib -l
umount $root_bin -l
umount $root_user/lib -l
umount $root_path/userdata -l
