#!/bin/sh

DEV="eth0"
IFACE4="wan"
IFACE6="wan6"
METRIC=10

# 检查 IPv6 是否存在
check_ipv6_pd() {
    ipv6=$(ip -6 addr show dev "$DEV" scope global | grep -oE "([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}" | head -n 1)
    [ -n "$ipv6" ] && echo "1" || echo "0"
}

# 添加网络到防火墙 zone（避免重复）
add_network_to_zone() {
    local zone="$1"
    local net="$2"
    local networks
    networks=$(uci get firewall.$zone.network 2>/dev/null)

    echo "$networks" | grep -qw "$net" || uci add_list firewall.$zone.network="$net"
}

set_network() {
    # 删除旧接口配置
    uci -q delete network.$IFACE4
    uci -q delete network.$IFACE6
    uci -q delete dhcp.$IFACE6

    # IPv4 WAN
    uci set network.$IFACE4='interface'
    uci set network.$IFACE4.proto='dhcp'
    uci set network.$IFACE4.ifname="$DEV"
    uci set network.$IFACE4.device="$DEV"
    uci set network.$IFACE4.metric="$METRIC"

    # IPv6 WAN6
    uci set network.$IFACE6='interface'
    uci set network.$IFACE6.proto='dhcpv6'
    uci set network.$IFACE6.ifname="@$IFACE4"
    uci set network.$IFACE6.device="@$IFACE4"
    uci set network.$IFACE6.metric="$METRIC"

    # LAN IPv6 开启
    uci set network.lan.ipv6='1'
    uci set network.lan.ip6assign='64'

    # DHCPv6 Relay 配置
    uci set dhcp.$IFACE6='dhcp'
    uci set dhcp.$IFACE6.interface="$IFACE6"
    uci set dhcp.$IFACE6.ra='relay'
    uci set dhcp.$IFACE6.ndp='relay'
    uci set dhcp.$IFACE6.master='1'
    uci set dhcp.$IFACE6.ignore='1'

    uci set dhcp.lan.ra='relay'
    uci set dhcp.lan.ndp='relay'
    uci set dhcp.lan.dhcpv6='relay'

    # 查找或创建 wan zone
    local zone_index=$(uci show firewall | grep -n "=zone" | grep "'wan'" | cut -d: -f1 | head -n 1)
    if [ -z "$zone_index" ]; then
        # 新建 wan zone
        uci add firewall zone
        uci set firewall.@zone[-1].name="wan"
        uci set firewall.@zone[-1].input="REJECT"
        uci set firewall.@zone[-1].output="ACCEPT"
        uci set firewall.@zone[-1].forward="REJECT"
        uci set firewall.@zone[-1].masq="1"
        uci set firewall.@zone[-1].mtu_fix="1"
        uci add_list firewall.@zone[-1].network="$IFACE4"
        uci add_list firewall.@zone[-1].network="$IFACE6"
    else
        # 获取 zone 名称
        zone_name=$(uci show firewall | sed -n "${zone_index}p" | cut -d. -f2 | cut -d= -f1)
        add_network_to_zone "$zone_name" "$IFACE4"
        add_network_to_zone "$zone_name" "$IFACE6"
    fi

    # 提交改动
    uci commit network
    uci commit dhcp
    uci commit firewall

    echo "Network configuration updated successfully"
}

# 执行
set_network

# 如果需要等 IPv6 再设置，可启用此循环
# while true; do
#     has_ipv6=$(check_ipv6_pd)
#     if [ "$has_ipv6" = "1" ]; then
#         set_network
#         break
#     else
#         sleep 5
#     fi
# done
