#!/bin/sh

LOCK_FILE="/var/run/modem_network_check.lock"
LOG_FILE="/var/log/modem_network_check.log"
V6_FILE="/tmp/last_wwan6_ipv6"
printMsg() {
    local msg="$1"
    logger -t "${PROGRAM}" "${msg}"
} #日志输出调用API

checkv6_and_run() {
    # s195: 蜂窝网卡不一定是 eth2(520 为 wwan0_1)，取 network 里带 modem_config 的接口的 device
    local cell_dev=eth2 sec d
    for sec in $(uci show network 2>/dev/null | sed -n 's/^network\.\([^.]*\)\.modem_config=.*/\1/p'); do
        case "$sec" in *[vV]6*) continue ;; esac
        d=$(uci get network.$sec.device 2>/dev/null)
        [ -n "$d" ] && [ -d "/sys/class/net/$d" ] && { cell_dev="$d"; break; }
    done
    current_v6=$(ip -6 addr show dev "$cell_dev" | grep 'global' | grep -v 'dynamic' | awk '/inet6/ {print $2}' | head -n1)
    if [ ! -f "$V6_FILE" ]; then
        echo "$current_v6" > "$V6_FILE"
    else
        last_v6=$(cat "$V6_FILE")
        if [ "$current_v6" != "$last_v6" ]; then
            printMsg "V6发生变化，重新分配V6地址。"
            uci del network.lan.ip6addr 2>/dev/null
            uci add_list network.lan.ip6addr="$LAN_ADDR"
            uci commit network
            #/usr/share/modem/v6.sh
            echo "$current_v6" > "$V6_FILE"
        fi
    fi
}

uci_load_network() {
    enable_weburl=$(uci -q get mwrt.@ndis[0].enable_weburl)
    if [ -z "$enable_weburl" ]; then
        enable_weburl=0
    fi

    weburl=$(uci -q get mwrt.@ndis[0].weburl)
    if [ -z "$weburl" ]; then
        weburl="www.baidu.com"
    fi

    enable_reconnect=$(uci -q get mwrt.@ndis[0].enable_reconnect)
    if [ -z "$enable_reconnect" ]; then
        enable_reconnect=0
    fi

    check_time=$(uci -q get mwrt.@ndis[0].check_time)
    if [ -z "$check_time" ]; then
        check_time="01:00"
    fi
}


network_check() {
    local failure_count=0
    while true; do
        uci_load_network
        if [ "$enable_weburl" = "1" ]; then
            if ping -c 1 $weburl > /dev/null 2>&1; then
                #echo "Network is OK" 
                echo 1 > /sys/class/leds/blue:wlan/brightness
                echo 1 > /sys/class/leds/red:wan/brightness
                failure_count=0
            else
                #echo "Network check failed" 
                printMsg "健康检查失败，无网络连接！"
                failure_count=$(($failure_count + 1))
            fi

            if [ $failure_count -ge 6 ]; then
            	printMsg "健康检查失败6次"
                #echo "Network failed 6 times, executing recovery script" 
            	echo "检测到模组网络1分钟掉线超过6次，请关注你的网络是否异常。
		        3
		        #ff0000" > /tmp/lucimsg.file
                echo 0 > /sys/class/leds/blue:wlan/brightness
                echo 1 > /sys/class/leds/red:wan/brightness
                #/usr/share/modem/mt5700m.sh
                #/sbin/ifup wan
                #/sbin/ifup wan6
                failure_count=0
            fi
            #checkv6_and_run
            sleep 10

        else
            sleep 60
        fi
    done
}




initialize_uci_defaults() {
    #uci set modem.@ndis[0]=network_check  # 确保节存在

    # 确保每个参数存在并设置默认值
    uci -q get mwrt.@ndis[0].enable_weburl > /dev/null || uci set modem.@ndis[0].enable_weburl=1
    uci -q get mwrt.@ndis[0].weburl > /dev/null || uci set modem.@ndis[0].weburl="www.baidu.com"
    uci -q get mwrt.@ndis[0].enable_reconnect > /dev/null || uci set modem.@ndis[0].enable_reconnect=0
    uci -q get mwrt.@ndis[0].check_time > /dev/null || uci set modem.@ndis[0].check_time="01:00"

    uci commit mwrt  # 提交更改，确保值被保存
}

# 在主逻辑开始时调用初始化函数，确保UCI配置存在并设置默认值
initialize_uci_defaults


# 防止脚本重复运行
if [ -e $LOCK_FILE ]; then
    echo "Script is already running." 
    exit
else
    touch $LOCK_FILE
    trap 'rm -f "${LOCK_FILE}"; exit' INT TERM EXIT
    initialize_uci_defaults
    sleep 2
    uci_load_network
    network_check &
    #if [ "$enable_weburl" = "1" ]; then
        #network_check &
    #fi

    #if [ "$enable_reconnect" = "1" ]; then
        #time_based_reconnect &
    #fi

    wait
    rm $LOCK_FILE
fi
