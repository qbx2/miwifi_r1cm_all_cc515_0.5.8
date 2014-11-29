#!/bin/sh
if [ "$ACTION" = "ASSOC" -a -n "$STA" ]; then 
	if [ "$(/sbin/uci get portalfilter.global.state 2>/dev/null)" == "on"  ]; then
		/usr/bin/logger -t "portalfilter" "welcome $STA"
		/usr/bin/lua /usr/sbin/portalfilter -d $STA
	fi
fi