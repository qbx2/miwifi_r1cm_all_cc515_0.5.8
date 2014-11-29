#!/bin/sh
#

klogger(){
	local msg1="$1"
	local msg2="$2"

	if [ "$msg1" = "-n" ]; then
		echo  -n "$msg2" >> /dev/kmsg 2>/dev/null
	else
		echo "$msg1" >> /dev/kmsg 2>/dev/null
	fi

	return 0
}

hndmsg() {
	if [ -n "$msg" ]; then
		echo "$msg" >> /dev/kmsg 2>/dev/null
		if [ `pwd` = "/tmp" ]; then
			rm -rf $filename 2>/dev/null
		fi
		exit 1
	fi
}

upgrade_uboot() {
	if [ -f uboot.bin ]; then
		klogger -n "Burning uboot..."
		mtd write uboot.bin Bootloader >& /dev/null
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			exit 1
		fi
	fi
}

upgrade_firmware() {
	if [ -f firmware.bin ]; then
		klogger -n "Burning firmware..."
		mtd -r write firmware.bin OS1 >& /dev/null
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			exit 1
		fi
	fi
}


if [ $# = 0 ] || [ $# -gt 2 ] ; then
	klogger "USAGE: $0 factory.bin 0(0:reboot, 1:don't reboot)"
	exit 1;
fi

#check pid exist
pid_file="/tmp/pid_xxxx"
if [ -f $pid_file ]; then
	exist_pid=`cat $pid_file`
	if [ -n $exist_pid ]; then
		kill -0 $exist_pid 2>/dev/null
		if [ $? -eq 0 ]; then
			klogger "Upgrading, exit... $?"
			exit 1
		else
			echo $$ > $pid_file
		fi
	else
		echo $$ > $pid_file
	fi
else
	echo $$ > $pid_file
fi

_ver=`cat /usr/share/xiaoqiang/xiaoqiang_version`
klogger "Begin Ugrading..., current version: $_ver"

echo 3 > /proc/sys/vm/drop_caches
sync

[ -f $1 ] || msg="dir: $1 is not existed, upgrade failed"
hndmsg

dir_name=`dirname $1`
klogger "Change Dir to: $dir_name"
cd $dir_name

filename=`basename $1`
[ -f $filename ] || msg="file: $filename is not existed, upgrade failed"
hndmsg

klogger -n "Verify Image: $filename..."
mkxqimage -v $filename || msg="Check Failed!!!"
hndmsg
klogger "Checksum O.K."

wifi down
rmmod mt7620
rmmod mt76x2e

#update nvram setting when upgrading
nvram set restore_defaults=2
nvram set flag_flash_permission=0
nvram commit

if [ -f "/etc/init.d/sysapihttpd" ] ;then
    /etc/init.d/sysapihttpd stop 2>/dev/null
fi

if [ $dir_name != "/tmp" ]; then
	klogger "Change Dir to /tmp"
        cp $1 /tmp
        cd /tmp
fi

# gently stop pppd, let it close pppoe session
killall -s HUP -q pppd && sleep 1
for i in $(ps w | grep -v "flash.sh" | grep -v "/bin/ash" | grep -v "PID" | awk '{print $1}'); do
        if [ $i -gt 100 ]; then
	        kill -9 $i 2>/dev/null
        fi
done

gpio 1 1
gpio 3 1
gpio 2 0

nvram set flag_ota_reboot=1
nvram set flag_upgrade_push=1
nvram commit

# tell server upgrade is finished
uci set /etc/config/messaging.deviceInfo.UPGRADE_STATUS_UPLOAD=0
uci commit
klogger "messaging.deviceInfo.UPGRADE_STATUS_UPLOAD=`uci get /etc/config/messaging.deviceInfo.UPGRADE_STATUS_UPLOAD`"
klogger "/etc/config/messaging : `cat /etc/config/messaging`"

klogger -n "Begin Upgrading and Rebooting..."
mkxqimage -w $filename || msg="Upgrade Failed!!!"
hndmsg
