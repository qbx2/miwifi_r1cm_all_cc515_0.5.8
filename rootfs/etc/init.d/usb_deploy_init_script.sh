#!/bin/sh /etc/rc.common
# Copyright (C) 2010-2012 OpenWrt.org

START=99
STOP=20

#usbDeployRootPath=$(cat /proc/mounts | grep /dev/sd |head -n1|cut -d' ' -f2);
usbDeployRootPath=

get_root_path(){
cat /proc/mounts | grep /dev/sd | while read line
do
	local dev=$(echo $line | cut -d' ' -f1)
	if [ -n "$dev" ] && [ -e "$dev" ]; then
		usbDeployRootPath=$(echo $line | cut -d' ' -f2)
		echo $usbDeployRootPath > /tmp/usbDeployRootPath.conf
		break
	fi
done
}

list_alldir(){  
	local init_root=$1
	local action=$2
	local hotplugStop=$3
	for file in `ls $init_root`  
	do  
		if [ -f "$init_root/$file" ];then
			$init_root/$file $action $usbDeployRootPath $hotplugStop &
		fi  
	done  
}  

start()
{
	get_root_path
	usbDeployRootPath=$(cat /tmp/usbDeployRootPath.conf)
	if [ -n "$usbDeployRootPath" ];then
		rm -rf /tmp/xiaomi_router
		mkdir -p /tmp/xiaomi_router
		cp -r $usbDeployRootPath/xiaomi_router/init /tmp/xiaomi_router/
		list_alldir $usbDeployRootPath/xiaomi_router/init start
	fi
}

stop()
{
	usbDeployRootPath=$(cat /tmp/usbDeployRootPath.conf)
	rm /tmp/usbDeployRootPath.conf
	if [ -n "$usbDeployRootPath" ];then
		list_alldir /tmp/xiaomi_router/init stop hotplug
		#local dev=$(getdisk mnt | grep "$usbDeployRootPath\$" | cut -d',' -f1)
		#if [ -n "$dev" ] && [ -e "$dev" ] ;then
		#	list_alldir $usbDeployRootPath/xiaomi_router/init stop
		#else
		#	list_alldir /tmp/xiaomi_router/init stop hotplug
		#fi
	fi
}

