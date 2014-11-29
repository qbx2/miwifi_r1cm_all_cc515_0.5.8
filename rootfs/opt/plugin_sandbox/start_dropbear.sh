#!/bin/sh
sandbox_dir=/userdisk/debug_app
chroot $sandbox_dir /bin/ash -c "/etc/init.d/dropbear restart" &> /dev/kmsg
