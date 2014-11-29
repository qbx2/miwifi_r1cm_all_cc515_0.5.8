#!/bin/sh
#
. /lib/lib.scripthelper.sh
#
dlog "INFO: funtion move to /usr/sbin/sysapi.firewall"
#
exit 0
#
SCRIPTTAG='monitor.ctl'
#
#/usr/sbin/iptraffic.set.firewall
#/usr/sbin/traffic.ctl.monitor
#
MONITORLIST='
#/usr/sbin/firewall.webinitrdr
#/usr/sbin/wan.monitor
#/usr/sbin/dnsmasq.monitor
#/usr/sbin/traffic.set.firewall
#/usr/sbin/iptaccount.set.firewall
#/usr/sbin/initmacfilterctl
#/usr/sbin/dnsmasq.catchall
'
#
#test "$2" != 'debug' && elog "exit for no debug."&&exit 0
#default to start
loaderop='start'
if [ "$(argmatch stop)" = '1' ]
	then
	#blocking stop
	loaderop='stop'
else
	##no blocking running
	#
	procdaemon mute
	#
	#load daemon monitor when firewall/start/restart
	#
	dlog "INFO: running ..."
	#
fi
#
if [ "$loaderop" = 'start' ]
then
	sleep 3
	waitbootcheck
	test $? -ne 0 && conlog "WARNING: bootcheck timeout, go ahead."
fi
if [ "$loaderop" = 'start' ]
	then
	wcnt=0
	local lanip
	lanip=''
	while [ $wcnt -le 90 ]
	do
		lanip=`ifconfig br-lan | awk -F'inet addr:' '{print $2}'|grep -v '^$'|awk '{print $1}'`
		if [ -n "$lanip" ]
		then
			break
		fi
		sleep 1
		let wcnt=$wcnt+1
	done
	if [ -z "$lanip" ]
		then
		conlog ""
		conlog ""
		conlog "ERROR: waiting timeout after $wcnt seconds for ip of br-lan ..."
		conlog ""
		conlog ""
	fi
fi
if [ "$loaderop" = 'start' ]
	then
	LOGGER="dlog"
else
	LOGGER="elog"
fi
test "$loaderop" = 'stop' && proc_ctl stop
errcnt=0
opcnt=0
for onemonitor in $MONITORLIST
do
	stringmatchstart '#' "$onemonitor"
	if [ $? -eq 0 ]
		then
		#echo "DEBUG: skiiped: $onemonitor"
		continue
	fi
	if [ -x "$onemonitor" ]
	then
		let opcnt=$opcnt+1
		$LOGGER "DEBUG: runing $onemonitor $loaderop nowait"
		$onemonitor $loaderop nowait  2>&1|pipelog $LOGGER
		if [ $? -ne 0 ]
		then
			$LOGGER "ERROR: $loaderop failed: $onemonitor $loaderop nowait"
			let errcnt=$errcnt+1
		else
			$LOGGER "DEBUG: $loaderop ok: $onemonitor $loaderop nowait"
		fi
	else
		$LOGGER "WARNING: no executable: $onemonitor"
	fi
	arrfastset $SCRIPTTAG errcnt $errcnt
	arrfastset $SCRIPTTAG opcnt $opcnt
done
errcnt=$(arrfastget $SCRIPTTAG errcnt)
opcnt=$(arrfastget $SCRIPTTAG opcnt)
$LOGGER "INFO: $loaderop $opcnt monitor finish with $errcnt errors."
exit $errcnt
#

