#!/bin/sh



root_path=$1
root_data=$root_path/userdata

umount $root_data

mkdir -p $root_data

mount --bind -r /userdisk/data $root_data
