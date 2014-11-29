#! /bin/sh

# this script has three usages:
# 1. start udhcpc client, rent an ip address and other info from a DHCP server.
# 2. a call back script of udhcpc, set DHCP information to /etc/config/network
# 3. restart lan swtich port to trigger client DHCP resending.

usage () {
    echo "$0 start [interface]"
    echo "\t default interface is apcli0"
    echo "$0 restart lan"
    echo "$0 help"
    exit 1
}

setup_interface () {
    [ -z "$ip" ] && exit 1
    netmask="${subnet:-255.255.255.0}"
    mtu="${mtu:-1500}"
uci -q batch <<-EOF >/dev/null
set network.lan.proto=static
set network.lan.ipaddr=$ip
set network.lan.netmask=$netmask
set network.lan.gateway=$router
set network.lan.mtu=$mtu
del network.lan.dns
add_list network.lan.dns=$dns
commit network
set xiaoqiang.common.ap_hostname=$hostname
commit xiaoqiang
EOF
    exit 0
}

start_dhcp () {
    model=`cat /proc/xiaoqiang/model`
    hostname="MiWiFi-$model"
    mypath=`dirname $0`
    cd $mypath >/dev/null
    abspath=`pwd`
    cd - >/dev/null
    ifname="$1"
    ifname="${ifname:-apcli0}"
    udhcpc -n -q -s $abspath/`basename $0` -t 3 -T 2 -i "$ifname" -H "$hostname" >/dev/null 2>&1
    exit 0
}

restart_lan () {
    exec /usr/sbin/phyhelper restart
}

case "$1" in
    help)
	usage
    ;;
    start)
	start_dhcp "$2"
    ;;
    restart)
	restart_lan
    ;;
    renew|bound)
	setup_interface
    ;;
esac
