#!/bin/sh

LOG_FILE='/tmp/process_monitor.log'
TMPFILE=`mktemp /tmp/temp.XXXXXX`

PID_LIST=`ls /proc/ | grep -E '^[0-9]+' | grep -v $$`
PROCESS_MAX_NUM=20

for pid in $PID_LIST
do
	[ -d /proc/$pid ] && cat /proc/$pid/cmdline >> $TMPFILE
done

echo "=== process monitor ===" > $LOG_FILE
cat $TMPFILE | grep -v "^$" | while read oneline
do
	num=`ps | grep "$oneline" | grep -v grep | wc -l`
	echo "$num ==== $oneline" >> $LOG_FILE
	if [ $num -ge $PROCESS_MAX_NUM ]
	then
		logger -t process_monitor.sh "$oneline.process num gt $num"
		#killall -q 9 "$oneline"
	fi
done
rm $TMPFILE