#!/bin/sh
#
#TODO: replace file status by fast array or UCI
#
. /lib/lib.scripthelper.sh
#
. /lib/functions.sh

MONITORCFGFILE='/etc/wan.monitor.conf'
#
getnictraffic(){
	local nic rxtx trcnt
	nic="$1"
	rxtx="$2"
	test -z "$rxtx" && echo "0" && return 0
	if [ "$rxtx" = 'rx' ]
		then
		trcnt=$(cat /proc/net/dev | grep "${nic}:" | head -n 1 | awk '{print $2}')
	else
		trcnt=$(cat /proc/net/dev | grep "${nic}:" | head -n 1 | awk '{print $10}')
	fi
	test -z "$trcnt" && trcnt=0
	echo "$trcnt"
	return 0
}
#
getlinkstat(){
	#return flag string
	local ctldest statstr
	ctldest="$1"
	if [ "$ctldest" != 'wan' -a "$ctldest" != 'vpn' -a "$ctldest" != 'dns' ]
		then
		dlog "ERROR: unknow target link $ctldest"
		exit 1
	fi
	if [ "$ctldest" = 'vpn' ]
		then
		upflag="$VPNALIVE"
		downflag="$VPNDIE"
	fi
	if [ "$ctldest" = 'wan' ]
		then
		upflag="$ALIVE"
		downflag="$DIE"
	fi
	if [ "$ctldest" = 'dns' ]
		then
		upflag="$DNSALIVE"
		downflag="$DNSDIE"
	fi
	statstr=''
	#get last flag
	touch $MONITORFILE
	while read onestatline
	do
		echo "$onestatline" | grep -q "^$upflag"
		if [ $? -eq 0 ]
			then
			statstr="$upflag"
		fi
		echo "$onestatline" | grep -q "^$downflag"
		if [ $? -eq 0 ]
			then
			statstr="$downflag"
		fi
	done < $MONITORFILE
	echo "$statstr"
	return 0
}
islinkup(){
	#return 1 for up, 0 for down
	local ctldest statstr
	ctldest="$1"
	case "$ctldest" in
		wan)
			upflag="$ALIVE"
			;;
		vpn)
			upflag="$VPNALIVE"
			;;
		dns)
			upflag="$DNSALIVE"
			;;
		*)
			elog "ERROR: unknow target link $ctldest"
			exit 1
			;;
	esac
	statstr=$(getlinkstat "$ctldest")
	if [ "$statstr" = "$upflag" ]
		then
		#up
		return 1
	else
		#down
		return 0
	fi
}
#
setlinkstat(){
	#
	#TODO: replace file by array
	#
	ctlop="$1"
	ctldest="$2"
	ismute="$3"
	if [ "$ctlop" != 'up' -a "$ctlop" != 'down' ]
		then
		dlog "ERROR: unknow link stat $ctlop"
		exit 1
	fi
	if [ "$ctldest" != 'wan' -a "$ctldest" != 'vpn' -a "$ctldest" != 'dns' ]
		then
		dlog "ERROR: unknow target link $ctldest"
		exit 1
	fi
	if [ "$ctldest" = 'wan' ]
		then
		upflag="$ALIVE"
		downflag="$DIE"
	fi
	if [ "$ctldest" = 'vpn' ]
		then
		upflag="$VPNALIVE"
		downflag="$VPNDIE"
	fi
	if [ "$ctldest" = 'dns' ]
		then
		upflag="$DNSALIVE"
		downflag="$DNSDIE"
	fi
	touch $MONITORFILE 2>/dev/null
	if [ $? -ne 0 ]
		then
		dlog "ERROR: touch $MONITORFILE failed: `touch $MONITORFILE 2>&1`"
		exit 1
	fi
	#
	prestat="$(arrfastget linkstat-${SCRIPTMARK} ${ctldest})"
	if [ "$ctlop" != "$prestat" ]
		then
		ismute='no'
	else
		ismute='mute'
	fi
	sed -i "/$upflag/d" $MONITORFILE
	sed -i "/$downflag/d" $MONITORFILE
	#remove blank line
	sed -i '/^$/d' $MONITORFILE
	arrfastset linkstat-${SCRIPTMARK} ${ctldest} ${ctlop}
	if [ "$ctlop" = 'up' ]
		then
		echo "$upflag" >> $MONITORFILE
		if [ $? -ne 0 ]
		then
			dlog "ERROR: set $ctldest link status to $ctlop, write $MONITORFILE failed."
			exit 1
		fi
		test "$ctldest" = 'wan' && echo "$INETCHK_UP" > $INETCHKFILE
	else
		echo "$downflag" >> $MONITORFILE
		if [ $? -ne 0 ]
		then
			dlog "ERROR: set $ctldest link status to $ctlop, write $MONITORFILE failed."
			exit 1
		fi
		test "$ctldest" = 'wan' && echo "$INETCHK_DOWN" > $INETCHKFILE
	fi
	test "$ismute" != 'mute' && dlog "INFO: set $ctldest link status to $ctlop"
	return 0
}

setalllinkstat(){
	ctlop="$1"
	if [ "$ctlop" != 'up' -a "$ctlop" != 'down' ]
		then
		dlog "ERROR: unknow link stat $ctlop"
		exit 1
	fi
	setlinkstat $ctlop wan $2 && setlinkstat $ctlop vpn $2 && setlinkstat $ctlop dns $2
	return $?
}
vpncheck(){
	local vpngwok
	mute="$1"
	if [ ! -s /tmp/traffic.route.env ]
	then
		test "$mute" = '0' && dlog "WARNING: empty /tmp/traffic.route.env."
		return 1
	fi
	. /tmp/traffic.route.env
	if [ -z "$VPNINTERFACE" ]
		then
		test "$mute" = '0' && dlog "WARNING: VPNINTERFACE no exported."
		return 1
	fi
	if [ -z "$VPNGW" ]
		then
		test "$mute" = '0' && dlog "WARNING: VPNGW no exported."
		return 1
	fi
	vpngwerr=0
	vpnrx=$(getnictraffic $VPNINTERFACE rx)
	vpntx=$(getnictraffic $VPNINTERFACE tx)
	#0 for ok
	iplocalcheck $VPNGW
	if [ $? -ne 0 ]
		then
		#test "$mute" = '0' && dlog "WARNING: VPNGW $VPNGW unreachable."
		vpngwerr=1
	fi
	vpn2rx=$(getnictraffic $VPNINTERFACE rx)
	vpn2tx=$(getnictraffic $VPNINTERFACE tx)
	if [ $vpngwerr -ne 0 ]
		then
		if [ "$vpnrx" = "$vpn2rx" -o $vpn2rx -eq 0 ]
			then
			#gateway error and no traffic income
			slog vpnchecknotraffic dlog "WARNING: $VPNGW unreachable, no traffic income from vpn."
			return 1
		else
			slog vpncheckrxtx dlog "INFO: VPNGW $VPNGW unreachable, but traffic income from vpn, it's ok: RX $vpnrx => $vpn2rx TX $vpntx => $vpn2tx"
		fi
	else
		slog vpncheckrxtx release
		slog vpnchecknotraffic release
	fi
	return 0
}
#
wangwcheck(){
	mute="$1"
	#
	#check default gateway
	#
	#TRAFFIC_ALLVPN
	#
	#getactivegatewayip getactivegatewaydev
	#
	NETGW=$(getdefaultrouteip)
	if [ -z "$NETGW" -a "$TRAFFIC_ALLVPN" = 'on' ]
		then
		NETGW=$(getactivegatewayip)
	fi
	if [ -z "$NETGW" ]
		then
		slog wangwcheck_nogw dlog "WARNING: default gateway no found."
		return 3
	fi
	slog wangwcheck_nogw release
	#
	iplocalcheck $NETGW
	if [ $? -ne 0 ]
		then
		slog wangwcheck_localcheck dlog "WARNING: NETGW $NETGW unreachable."
		return 1
	fi
	slog wangwcheck_localcheck release
	return 0
}
wanlinkcheck(){
	mute="$1"
	#check wan port link status
	config_load misc
	config_get wan_link_op switchop wan_connect
	$wan_link_op
	if [ $? -ne 0 ]
	then
	    slog wanlinkcheck dlog "WARNING: wan link cable no connected."
	    return 252
	fi
	slog wanlinkcheck release
	return 0
}
wancheck(){
	local niclinkok
	mute="$1"
	refok=0
	chkcnt=0
	wanlinkcheck
	chkcode=$?
	if [ $chkcode -ne 0 ]
		then
		return $chkcode
	fi
	wangwcheck $mute
	chkcode=$?
	if [ $chkcode -ne 0 ]
		then
		return $chkcode
	fi
	return 0
}
#
dnscheck(){
	#return 0 for ok, 1 for err
	mute="$1"
	refok=0
	chkcnt=0
	#islinkup 'wan'
	## 1 for up, 0 for down
	#if [ $? -eq 0 ]
	#	then
	#	return 1
	#fi
	if [ ! -s "$MONITORCFGFILE" ]
		then
		return 0
	fi
	. $MONITORCFGFILE
	if [ -z "$WANDOMAINLIST" ]
		then
		#no list, it is ok
		return 0
	fi
	for onedomain in $WANDOMAINLIST
	do
		let chkcnt=$chkcnt+1
		#check dns resolver, timeout 5 seconds
		addrlist=`/usr/sbin/nslookupt $onedomain 127.0.0.1 3`
		#dlog "nslookupt $onedomain 127.0.0.1 3 => $addrlist"
		ret=`echo "$addrlist" | awk -F'/' '{print $3}'`
		if [ -n "$ret" ]
			then
			#dlog "nslookupt $onedomain 127.0.0.1 3 => OK"
			let refok=$refok+1
		else
			#dlog "nslookupt $onedomain 127.0.0.1 3 => ERR"
			continue
		fi
	done
	if [ $chkcnt -gt 3 ]
		then
		let needok=$chkcnt/3
	else
		needok=1
	fi
	if [ $refok -lt $needok ]
		then
		return 1
	fi
	return 0
}
logsysteminfo(){
	local logfun="$1"
	test -z "$logfun" && logfun='dlog'
	$logfun "INFO: network info:"
	ifconfig -a 2>&1 | pipelog $logfun
	$logfun "INFO: ---- end of network info ---- "
	$logfun "INFO: routing table:"
	route -n 2>&1 | pipelog $logfun
	$logfun "INFO: ---- end of routing table ---- "
	$logfun "INFO: arp table:"
	arp -n 2>&1 | pipelog $logfun
	$logfun "INFO: ---- end of arp table ---- "
	$logfun "INFO: top info:"
	top -b -n 1 2>&1 | head -n 50 | pipelog $logfun
	$logfun " --- end top --- "
	$logfun "INFO: --- begin df ---"
	df -h 2>&1 | pipelog $logfun
	$logfun "INFO: --- end df ---"
	$logfun "INFO: --- begin interference ---"
	wl -i wl0 interference 2>&1 | pipelog $logfun
	wl -i wl1 interference 2>&1 | pipelog $logfun
	$logfun "INFO: --- end interference ---"

	return 0
}
if [ -s "$MONITORCFGFILE" ]
	then
	. $MONITORCFGFILE
fi
export TRAFFIC_ALLVPN
#
#
