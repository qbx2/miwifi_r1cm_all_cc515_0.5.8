#!/bin/sh

authorize=`uci get misc.iwevent.authorize`

if [ "$authorize" = "1" ]; then
    [ "$ACTION" = "AUTHORIZE" ] && [ -n "$STA" ] && {
        feedPush "{\"type\":1,\"data\":{\"mac\":\"$STA\"}}"
    }
else
    [ "$ACTION" = "ASSOC" ] && [ -n "$STA" ] && {
        feedPush "{\"type\":1,\"data\":{\"mac\":\"$STA\"}}"
    }
fi

[ "$ACTION" = "DISASSOC" ] && [ -n "$STA" ] && {
    feedPush "{\"type\":2,\"data\":{\"mac\":\"$STA\"}}"
}
