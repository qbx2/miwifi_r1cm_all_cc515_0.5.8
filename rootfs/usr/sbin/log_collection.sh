#!/bin/sh

redundancy_mode=`uci get misc.log.redundancy_mode`

LOG_TMP_FILE_PATH="/tmp/xiaoqiang.log"
LOG_ZIP_FILE_PATH="/tmp/log.zip"

WIRELESS_FILE_PATH="/etc/config/wireless"
NETWORK_FILE_PATH="/etc/config/network"
MACFILTER_FILE_PATH="/etc/config/macfilter"

LOG_DIR="/data/usr/log/"
LOGREAD_FILE_PATH="/data/usr/log/messages"
LOGREAD0_FILE_PATH="/data/usr/log/messages.0"
PANIC_FILE_PATH="/data/usr/log/panic.message"
TMP_LOG_FILE_PATH="/tmp/messages"
TMP_WIFI_LOG="/tmp/wifi.log"
NETWORK_DETECT_LOG="/data/usr/log/network.log"

cat $TMP_LOG_FILE_PATH >> $LOGREAD_FILE_PATH
> $TMP_LOG_FILE_PATH

echo "==========bootinfo" >> $LOG_TMP_FILE_PATH
bootinfo >> $LOG_TMP_FILE_PATH

echo "==========tmp dir" >> $LOG_TMP_FILE_PATH
ls -lh /tmp/ >> $LOG_TMP_FILE_PATH

echo "==========iwpriv wl0" >> $LOG_TMP_FILE_PATH
iwpriv wl0 e2p >> $LOG_TMP_FILE_PATH

echo "==========iwpriv wl1" >> $LOG_TMP_FILE_PATH
iwpriv wl1 e2p >> $LOG_TMP_FILE_PATH

echo "==========crontab" >> $LOG_TMP_FILE_PATH
crontab -l >> $LOG_TMP_FILE_PATH

echo "==========ifconfig" >> $LOG_TMP_FILE_PATH
ifconfig >> $LOG_TMP_FILE_PATH

#echo "==========network:" >> $LOG_TMP_FILE_PATH
#cat $NETWORK_FILE_PATH >> $LOG_TMP_FILE_PATH

#echo "==========wireless:" >> $LOG_TMP_FILE_PATH
#cat $WIRELESS_FILE_PATH >> $LOG_TMP_FILE_PATH

echo "==========macfilter:" >> $LOG_TMP_FILE_PATH
cat $MACFILTER_FILE_PATH >> $LOG_TMP_FILE_PATH

echo "==========dmesg:" >> $LOG_TMP_FILE_PATH
dmesg >> $LOG_TMP_FILE_PATH

if [ "$redundancy_mode" = "1" ]; then
	zip -r $LOG_ZIP_FILE_PATH $LOG_TMP_FILE_PATH $LOGREAD_FILE_PATH $LOGREAD0_FILE_PATH $PANIC_FILE_PATH $TMP_WIFI_LOG $NETWORK_DETECT_LOG
else
	zip -r $LOG_ZIP_FILE_PATH $LOG_DIR $LOG_TMP_FILE_PATH $PANIC_FILE_PATH $TMP_WIFI_LOG $NETWORK_DETECT_LOG
fi
