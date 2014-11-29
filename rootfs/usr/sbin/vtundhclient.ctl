#!/bin/sh
export LANG=C

#run start/stop

#
. /lib/lib.scripthelper.sh
#

#Wed Jun 26 10:35:24 GMT 2013 /usr/sbin/vtundhclient.ctl
#start tap1 0.0.0.0 0 58.68.235.243 465
# $1	$2	$3   $4	  $5		 $6
op=$1

#echo "`date` $0" > /tmp/vtundhcp.log
#echo $@ >> /tmp/vtundhcp.log
#env >> /tmp/vtundhcp.log
#set >> /tmp/vtundhcp.log
#echo "---" >> /tmp/vtundhcp.log

killdhclient(){
	#stop all vtund-dhclient first
	for sig in 15 9
	do
		alivecnt=0
		for onefile in $(ls -A /var/run/udhcpc-vtund-* 2>/dev/null)
		do
			onepid=$(cat $onefile 2>/dev/null)
			test -z "$onepid" && continue
			kill -0 "$onepid" || continue
			kill -$sig "$onepid" 2>/dev/null
			if [ $sig -eq 9 ]
				then
				dlog "WARNING: $onefile($onepid) stop failed, KILLED."
			fi
			kill -$sig "$onepid" 2>/dev/null
			test $? -eq 0 && let alivecnt=$alivecnt+1
		done
		test $alivecnt-gt 0 && sleep 2
	done
}

killdhclient

if [ "$op" = 'stop' ]
	then

	#remove firewall,it is start by vtundhclient.script
	/usr/sbin/traffic.set.firewall stop
	if [ $? -ne 0 ]
	then
		dlog "ERROR: $0, /usr/sbin/traffic.set.firewall stop failed."
		exit 1
	else
		dlog "INFO: $0, /usr/sbin/traffic.set.firewall stop ok."
	fi

	rm -f /tmp/vpnclient.env
	rm -f /tmp/traffic.route.env

	dlog "INFO: $0, $op end."
	echo "`date` INFO: $0, $op end."
	exit 0
else
	op='start'
fi
VPNINTERFACE=$2
VPNSERVERIP=$5
dlog "INFO: IFACE $VPNINTERFACE, SERVER $VPNSERVERIP"
if [ -z "$VPNINTERFACE" ]
	then
	dlog "ERROR: $0, VPNINTERFACE no defined."
	echo "`date` ERROR: $0, VPNINTERFACE no defined."
	exit 1
fi
#
if [ -z "$VPNSERVERIP" ]
then
	dlog "ERROR: $0, vtund server ip no found."
	echo "`date` ERROR: $0, vtund server ip no found."
	exit 1
fi
checkproclock 0
if [ $? -ne 0 ]
	then
	dlog "INFO: waiting 30 seconds for PID: $(getlockedprocpid)"
fi

checkproclock 30
if [ $? -ne 0 ]
	then
	dlog "ERROR: exit for another running, PID: $(getlockedprocpid)"
	exit 1
fi
setproclock
#
LOCALGW=$(getdefaultrouteip)
if [ -z "$LOCALGW" ]
then
	dlog "ERROR: $0, local gateway no found."
	echo "`date` ERROR: $0, local gateway no found."
	exit 1
fi
/sbin/route add -host $VPNSERVERIP gw $LOCALGW 2>/dev/null
isok=`/sbin/route add -host $VPNSERVERIP gw $LOCALGW 2>&1 | grep -c 'File exists'`
if [ $isok -eq 0 ]
then
	dlog "ERROR: $0, set route for vtund server ip $VPNSERVERIP failed: /sbin/route add -host $VPNSERVERIP gw $LOCALGW"
	exit 1
#else
#	dlog "INFO: $0, set route for vtund server ip $VPNSERVERIP ok: /sbin/route add -host $VPNSERVERIP gw $LOCALGW"
fi
cat <<EOF>/tmp/vpnclient.env
VPNINTERFACE=$VPNINTERFACE
LOCALGW=$LOCALGW
VPNSERVERIP=$VPNSERVERIP
EOF
if [ $? -ne 0 ]
then
	dlog "ERROR: $0, save network env failed."
	echo "`date` ERROR: $0, save network env failed."
	exit 1
fi
#set firewall, it is stop by vtundhclient.ctl
/usr/sbin/traffic.set.firewall start
if [ $? -ne 0 ]
then
	dlog "ERROR: $0, /usr/sbin/traffic.set.firewall start failed."
#else
#	dlog "INFO: $0, /usr/sbin/traffic.set.firewall started."
fi
#
/sbin/udhcpc -p /var/run/udhcpc-vtund-${VPNINTERFACE}.pid -s /usr/sbin/vtundhclient.script -b -t 120 -i ${VPNINTERFACE} -C -o
if [ $? -ne 0 ]
	then
	dlog "ERROR: start failed: /sbin/udhcpc -p /var/run/udhcpc-vtund-${VPNINTERFACE}.pid -s /usr/sbin/vtundhclient.script -b -t 120 -i ${VPNINTERFACE} -C -o"
	exit 1
else
	wcnt=0
	timeout=10
	dhcpid=$(cat /var/run/udhcpc-vtund-${VPNINTERFACE}.pid)
	while [ $wcnt -le $timeout -a -z "$dhcpid" ]
	do
		dhcpid=$(cat /var/run/udhcpc-vtund-${VPNINTERFACE}.pid)
		test -n "$dhcpid" && break
		sleep 1
		let wcnt=$wcnt+1
	done
	if [ -z "$dhcpid" ]
		then
		dlog "ERROR: /sbin/udhcpc -p /var/run/udhcpc-vtund-${VPNINTERFACE}.pid -s /usr/sbin/vtundhclient.script -b -t 120 -i ${VPNINTERFACE} -C -o"
		dlog "ERROR: udhcpc start failed after $timeout seconds, for ${VPNINTERFACE} at $VPNSERVERIP"
		exit 1
	else
		dlog "INFO: udhcpc($dhcpid) ok for ${VPNINTERFACE} at $VPNSERVERIP"
		exit 0
	fi
fi
#dlog "INFO: $0, $op done."
#
