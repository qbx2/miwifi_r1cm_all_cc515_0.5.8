#!/bin/sh

fix_fcgi() {
    pid_file="/var/run/fcgi-cgi.pid"
    [ -f "$pid_file" ] || return
    pid=$(cat "$pid_file")
    kill -1 $pid
    exit 0
}

# check_fcgi hostip
check_fcgi() {
    lanip=$1
    cgi_result=$(curl -sSf -o /dev/null "http://$lanip/cgi-bin/luci/web" 2>&1)
    if [ -n "$cgi_result" ]; then # found error
	echo "$cgi_result" | grep -F "502" && fix_fcgi
    fi
}
