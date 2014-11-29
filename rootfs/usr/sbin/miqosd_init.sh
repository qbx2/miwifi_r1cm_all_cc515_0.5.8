#!/bin/sh

QOS_VER="CTF"
if [ $# -eq "1" -a $1 == "std" ]; then
    QOS_VER="STD"
fi

QOS0="miqos0"   # for XiaoQiang forward
QOS1="miqos1"   # for XiaoQiang input/output
QOSM="miqosm"	# for IP mark
QOSC="miqosc"   # for package flow recognization

IPT="/usr/sbin/iptables -t mangle"
SIP=`uci get network.lan.ipaddr 2>/dev/null`
SMASK=`uci get network.lan.netmask 2>/dev/null`
SIPMASK="$SIP/$SMASK"

#clear miqos 1stly before construct links
$IPT -D FORWARD -j $QOS0 &>/dev/null
if [ $QOS_VER == "STD" ]; then
    $IPT -D INPUT -j $QOS1 &>/dev/null
    $IPT -D OUTPUT -j $QOS1 &>/dev/null
fi

#flush miqos0 miqos1 miqosc and miqosm
$IPT -F $QOS0 &>/dev/null
$IPT -X $QOS0 &>/dev/null

if [ $QOS_VER == "STD" ]; then
    $IPT -F $QOS1 &>/dev/null
    $IPT -X $QOS1 &>/dev/null
fi

$IPT -F $QOSC &>/dev/null
$IPT -X $QOSC &>/dev/null

$IPT -F $QOSM &>/dev/null
$IPT -X $QOSM &>/dev/null

#init QOS0 QOS1 QOSC and QOSM
$IPT -N $QOS0 &>/dev/null
$IPT -N $QOSC &>/dev/null
$IPT -N $QOSM &>/dev/null
if [ $QOS_VER == "STD" ]; then
    $IPT -N $QOS1 &>/dev/null
fi

#FORWARD to miqos link
$IPT -A FORWARD -j $QOS0 &>/dev/null

#add hook for xiaoqiang's I/O
if [ $QOS_VER == "STD" ]; then
    $IPT -A INPUT -j $QOS1
    $IPT -A OUTPUT -j $QOS1

    #set priority for XQ as lowest priority
    $IPT -A $QOS1 -j CONNMARK --restore-mark --nfmask 0x000fffff --ctmask 0xfff00000
    $IPT -A $QOS1 -m connmark ! --mark 0/0xff000000 -j RETURN
    #$IPT -A $QOS1 -m connmark ! --mark 0/0xff000000 -m connmark ! --mark 0/0x00f00000 -j RETURN
    $IPT -A $QOS1 -j MARK --set-mark 0x01000000/0xff000000
    # set communication between xq and cloud as the highest priority
    $IPT -A $QOS1 -p tcp -m multiport --dports 1880:1890 -j MARK --set-mark 0x00100000/0x00f00000
    $IPT -A $QOS1 -j CONNMARK --save-mark --nfmask 0xfff00000 --ctmask 0x000fffff
fi

#restore IP MARK
$IPT -A $QOS0 -j CONNMARK --restore-mark --nfmask 0x000fffff --ctmask 0xfff00000
#restore packets category MARK
#$IPT -A $QOS0 -m connmark ! --mark 0/0x00f00000 -j CONNMARK --restore-mark --nfmask 0xff0fffff --ctmask 0x00f00000
#short path
$IPT -A $QOS0 -m connmark ! --mark 0/0xff000000 -m connmark ! --mark 0/0x00f00000 -j RETURN

# goto IP MARK link
$IPT -A $QOS0 -m connmark --mark 0/0xff000000 -j $QOSM

# goto packet category MARK link
$IPT -A $QOS0 -m connmark --mark 0/0x00f00000 -j $QOSC

#save mark to ct mark
$IPT -A $QOS0 -j CONNMARK --save-mark --nfmask 0xfff00000 --ctmask 0x000fffff

#IP mark link
$IPT -A $QOSM ! -d $SIPMASK -j IP4MARK --addr src
$IPT -A $QOSM -d $SIPMASK -j IP4MARK --addr dst

#child qosc link will be changed by QoS script
#QOSC

