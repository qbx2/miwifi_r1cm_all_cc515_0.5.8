#!/bin/sh

check_err() {
  if [ -n "$err_msg" ]; then
    echo "$err_msg" >> /dev/kmsg 2> /dev/null
    exit 1
  fi
}

sandbox_dir=/userdisk/debug_app
sandbox_source=/opt/plugin_sandbox
rm -rf $sandbox_dir/.created || err_msg="failed to remove $sandbox_dir/.created"
check_err

(mkdir -p $sandbox_dir/tmp && \
 mkdir -p $sandbox_dir/root && \
 mkdir -p $sandbox_dir/var/run && \
 mkdir -p $sandbox_dir/var/log) || \
err_msg="failed to create dirs"
check_err

chmod -R 777 $sandbox_dir 2> /dev/null

(rm -rf $sandbox_dir/etc && \
 mkdir -p $sandbox_dir/etc/init.d) && \
 cp $sandbox_source/dropbear.init $sandbox_dir/etc/init.d/dropbear || \
err_msg="failed to create /etc/init.d/dropbear in sandbox"
check_err

mkdir -p $sandbox_dir/usr/sbin
mkdir -p $sandbox_dir/sbin
mkdir -p $sandbox_dir/usr/bin
mkdir -p $sandbox_dir/usr/share/libubox

cat $sandbox_source/sandbox_white_list.conf 2> /dev/null | while read line
do
  (rm -rf $sandbox_dir/$line) || err_msg="Failed to remove $sandbox_dir/$line"
  check_err
  if [ -d /rom/$line ]; then
    (mkdir $sandbox_dir/$line && \
     cp -rf /rom/$line/* $sandbox_dir/$line/) || \
    err_msg="Failed to copy $line from rom to sandbox"
    check_err
  elif [ -f /rom/$line ]; then
    (cp -rf /rom/$line $sandbox_dir/$line) || \
    err_msg="Failed to copy $line from rom to sandbox"
    check_err
  else
    err_msg="$line does not exsist in rom"
    check_err
  fi
done


(cp $sandbox_source/passwd $sandbox_dir/etc/ && \
 chmod 644 $sandbox_dir/etc/passwd) || \
err_msg="failed to install /etc/passwd in sandbox"
check_err
echo plugin:x:1000:1000:plugin:/:/bin/ash >> $sandbox_dir/etc/passwd

(cp $sandbox_source/group $sandbox_dir/etc/ && \
 chmod 644 $sandbox_dir/etc/group) || \
err_msg="failed to install /etc/group in sandbox"
check_err
echo plugin:!:1000: >> $sandbox_dir/etc/group

(cp $sandbox_source/shadow $sandbox_dir/etc/ && \
 chmod 600 $sandbox_dir/etc/shadow) || \
err_msg="failed to install /etc/shadow in sandbox"
check_err
echo plugin:\$1\$ouGm2OAu\$PazR54iv1UqvFVwGK5Jt11:16205:0:99999:7::: >> $sandbox_dir/etc/shadow

(mkdir -p $sandbox_dir/etc/config/ && \
 cp $sandbox_source/dropbear $sandbox_dir/etc/config/ && \
 chmod 644 $sandbox_dir/etc/config/dropbear) || \
err_msg="failed to install /etc/config/dropbear in sandbox"
check_err

cp /bin/busybox $sandbox_dir/sbin/passwd
chmod u+s $sandbox_dir/sbin/passwd
chmod 755 $sandbox_dir/sbin
chmod 777 $sandbox_dir/etc
/bin/sync || err_msg="failed to /bin/sync"
check_err

touch $sandbox_dir/.created
