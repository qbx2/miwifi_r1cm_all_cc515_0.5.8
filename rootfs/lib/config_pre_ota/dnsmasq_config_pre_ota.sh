#!/bin/sh
#
#FILE_TARGET: /lib/config_pre_ota/dnsmasq_config_pre_ota.sh
#

#save dhcp ip range
#dhcp.lan.start=100
#dhcp.lan.limit=150

ipstart=$(uci -c /data/etc get dhcp.lan.start 2>/dev/null)
iplimit=$(uci -c /data/etc get dhcp.lan.limit 2>/dev/null)

if [ -z "$ipstart" -o -z "$iplimit" ]
	then
	exit 0
fi

mkdir -p /data/tmp/ && echo "$ipstart $iplimit" > /data/tmp/dhcp-range.txt
if [ $? -ne 0 ]
	then
	echo "ERROR: save $ipstart $iplimit failed."
	exit 1
fi
echo "INFO: save $ipstart $iplimit ok."
exit 0
#