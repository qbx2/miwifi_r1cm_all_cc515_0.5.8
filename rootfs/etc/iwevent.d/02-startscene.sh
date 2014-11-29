#!/bin/sh

[ -n "$ACTION" ] && [ -n "$STA" ] && {
    startscene.lua $ACTION $STA
}
