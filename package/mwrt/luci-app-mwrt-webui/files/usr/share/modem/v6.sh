#!/bin/sh
#fix ipv6Server mode manper 20250611

WAN_IF="eth2" 
LAN_IF="br-lan" 

WAN_IPV6=$(ip -6 addr show dev $WAN_IF | grep 'global' | grep -v 'dynamic' | awk '/inet6/ {print $2}' | head -n1)

if [ -z "$WAN_IPV6" ]; then
    exit 1
fi

PREFIX=$(echo $WAN_IPV6 | cut -d/ -f1 | awk -F: '{printf "%s:%s:%s:%s::/64", $1, $2, $3, $4}')
LAN_ADDR="${PREFIX%/64}1/64"

# ------------------------
uci del network.lan.ip6addr 2>/dev/null
uci add_list network.lan.ip6addr="$LAN_ADDR"
uci commit network
#/etc/init.d/network reload
# ------------------------
#echo 1 > /proc/sys/net/ipv6/conf/$WAN_IF/proxy_ndp
#opkg list-installed | grep -q ndppd
#if [ $? -ne 0 ]; then
    #echo "请先安装ndppd: opkg update && opkg install ndppd"
    #exit 0
#fi

#cat > /etc/ndppd.conf <<EOF
#proxy $LAN_IF {
    #rule $PREFIX {
        #auto
    #}
#}
#EOF

#killall ndppd 2>/dev/null
#ndppd -c /etc/ndppd.conf &
uci set dhcp.lan.dhcpv6='server'
uci set dhcp.lan.ra='server'
uci set dhcp.lan.ra_management='2'
uci set dhcp.lan.ra_default='1'
uci set dhcp.lan.ndp='relay'
uci set dhcp.lan.dhcpv4='server'
uci set dhcp.lan.ra_slaac='1'
uci set dhcp.lan.ip6assign='64'
uci commit dhcp
#/etc/init.d/dnsmasq restart
