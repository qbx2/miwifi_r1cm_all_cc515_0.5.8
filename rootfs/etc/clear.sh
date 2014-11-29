#!/bin/sh 

# this script will be called when reset router.

#uninstall all plugins
#rm -rf /userdisk/datacenterConfig/DataBase/*
rm -rf /userdisk/BroadLink

rm -rf /userdisk/appdata
rm -rf /userdisk/kuaipan
rm -rf /userdisk/ThunderDB

rm -rf /userdisk/cachecenter

#curl http://127.0.0.1:9000/unbind
touch /etc/reset_flag_file

