#!/bin/sh /etc/rc.common
# Copyright (C) 2010-2012 OpenWrt.org

START=99
STOP=20

list_alldir(){  
	for file in `ls $1 | grep [^a-zA-Z]\.manifest$`  
	do  
		if [ -f $1/$file ];then
			#is_supervisord=$(grep "is_supervisord" $1/$file | cut -d'=' -f2 | cut -d'"' -f2)
			#echo "is_supervisord is $is_supervisord"
			status=$(grep -n "^status " $1/$file | cut -d'=' -f2 | cut -d'"' -f2)
			echo "status is $status"
			plugin_id=$(grep "plugin_id" $1/$file | cut -d'=' -f2 | cut -d'"' -f2)
			echo "plugin_id is $plugin_id"
			chown -R $plugin_id:$plugin_id /userdisk/appdata/$plugin_id/
			if [ "$status"x = "5"x ];then
				pluginControllor -b $plugin_id &
			fi  
		fi  
	done  
}  

start()
{
	copy_chroot_files.sh
	pluginControllor -u
	#chown -R plugin:plugin /userdisk/appdata
	list_alldir /userdisk/appdata/app_infos
}
