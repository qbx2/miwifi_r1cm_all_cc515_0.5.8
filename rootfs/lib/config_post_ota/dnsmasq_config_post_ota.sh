#!/bin/sh
#
#FILE_TARGET: /lib/config_post_ota/dnsmasq_config_post_ota.sh
#

/sbin/uci -q batch <<-EOF >/dev/null
set dhcp.@dnsmasq[0].leasefile=/tmp/dhcp.leases
set dhcp.@dnsmasq[0].allservers=1
delete dhcp.@dnsmasq[0].domain
commit dhcp
EOF

echo "INFO: uci restore dnsmasq config ok."
exit 0

