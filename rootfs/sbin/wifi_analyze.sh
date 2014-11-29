#!/bin/sh

echo "2.4G:"
echo " Environment description (RSSI, Client module name and number)"
iwpriv wl1 set Debug=3
iwpriv wl1 show driverinfo
iwpriv wl1 show stainfo
iwpriv wl1 show bainfo
Iwpriv wl1 stat
echo "EEPROM dump"
iwpriv wl1 e2p
echo "MAC/RF dump"
Iwpriv wl1 mac
Iwpriv wl1 rf
iwpriv wl1 set Debug=0
echo
echo "5G:"
echo " Environment description (RSSI, Client module name and number)"
iwpriv wl0 set Debug=3
iwpriv wl0 show driverinfo
iwpriv wl0 show stainfo
iwpriv wl0 show bainfo
Iwpriv wl0 stat
echo "EEPROM dump"
iwpriv wl0 e2p
echo "MAC/RF dump"
Iwpriv wl0 mac
Iwpriv wl0 rf
iwpriv wl0 set Debug=0

