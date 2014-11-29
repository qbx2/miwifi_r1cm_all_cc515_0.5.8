#!/bin/sh
#run in daemon
#
. /lib/lib.scripthelper.sh
#
getmonitorpid(){
	echo "$(ps w| grep monitor | grep ' /bin/sh ' | grep -v "stopallmonitor" | grep -v 'grep'| awk '{print $1}')"
}
#
if [ "$1" = 'boot' ]
	then
	##run in daemon
	procdaemon mute
	#
	elog "INFO: waitting 30 seconds for all monitor started."
	sleep 30
	#
fi
#
monitorpidlist=$(getmonitorpid)
kill $monitorpidlist 2>/dev/null
sleep 1
monitorpidlist=$(getmonitorpid)
#
wcnt=0
timeout=30
while [ $wcnt -le $timeout ]
do
	if [ "$1" = 'kill' ]
		then
		kill -9 "$lckpid" 2>/dev/null
	else
		kill $monitorpidlist 2>/dev/null
	fi
	test $wcnt -eq 0 && elog "INFO: waitting for PID: $monitorpidlist"
	monitorpidlist=$(getmonitorpid)
	test -z "$monitorpidlist" && break
	let wcnt=$wcnt+1
	sleep 1
done
if [ -n "$monitorpidlist" ]
	then
	elog "ERROR: all monitor stop failed: $monitorpidlist"
	ps w| grep monitor | grep ' /bin/sh ' | grep -v "stopallmonitor" | grep -v 'grep' | pipelog elog
	exit 1
else
	elog "INFO: all monitor stop ok."
	exit 0
fi