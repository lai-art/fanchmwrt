#!/bin/sh
# 检查是否已经有锁文件存在
lock_file="/var/run/network_status_update.lock"
exec 200>$lock_file
flock -n 200 || exit 1

# C5800 接了 AK68 且 ATSD 已通(/tmp/mwrt-ak68.atsd 由 mwrt-ak68 守护立)时: 信号灯/制式灯跟 AK68 里的模组走,
# AT 经 ATSD 发(mwrt-akat), 模组种类按 AK68 实际型号选分支。没有这个文件(其它机型、没接 AK68)时下面一行都不生效。
sendat() {
    if [ -e /tmp/mwrt-ak68.atsd ]; then
        shift
        /usr/bin/mwrt-akat "$@"
    else
        command sendat "$@"
    fi
}

while true
do
    modconf=$(cat /tmp/modconf.conf)
    if [ -e /tmp/mwrt-ak68.atsd ]; then
        case "$(jsonfilter -i /tmp/mwrt-ak68.json -e '@.kind' 2>/dev/null)" in
            rm520n) modconf=RM520N ;;
            mt5700) modconf=MT5700M-CN ;;
        esac
    fi
    if [ ! -f "/tmp/ledflag.conf" ]; then
        if echo "$modconf" | grep -q "RM520N"; then
            network_mode=$(sendat 2 at+qnwinfo | grep '+QNWINFO' | awk -F\" '{print $2}' | tr -d '\r')
            OX=$( sendat 2 "AT+CSQ" |grep "+CSQ:")
            OX=$(echo $OX | tr 'a-z' 'A-Z')
            CSQ=$(echo "$OX" | grep -o "+CSQ: [0-9]\{1,2\}" | grep -o "[0-9]\{1,2\}")
            if [ $CSQ = "99" ]; then
                CSQ="0"
                echo 0 > /sys/class/leds/hc:blue:cmode5/brightness
                echo 0 > /sys/class/leds/hc:blue:cmode4/brightness
                echo 0 > /sys/class/leds/hc:blue:sig1/brightness
                echo 0 > /sys/class/leds/hc:blue:sig2/brightness
                echo 0 > /sys/class/leds/hc:blue:sig3/brightness
                echo 1 > /sys/class/leds/hc:blue:int/brightness
            fi
            if [ -n "$CSQ" ]; then
                RSRQ=$(($CSQ * 100/31))
                if [ "$RSRQ" -ge 99 ]; then
                    echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig2/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig3/brightness
                elif [ "$RSRQ" -ge 95 ] && [ "$RSRQ" -lt 99 ]; then
                    echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig2/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig3/brightness
                elif [ "$RSRQ" -ge 90 ] && [ "$RSRQ" -lt 95 ]; then
                    echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig2/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig3/brightness
                elif [ "$RSRQ" -ge 85 ] && [ "$RSRQ" -lt 90 ]; then
                    echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig2/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig3/brightness
                elif [ "$RSRQ" -ge -80 ] && [ "$RSRQ" -lt 85 ]; then
                    echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig2/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig3/brightness
                elif [ "$RSRQ" -ge 65 ] && [ "$RSRQ" -lt 80 ]; then
                    echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig2/brightness
                    echo 0 > /sys/class/leds/hc:blue:sig3/brightness
                elif [ "$RSRQ" -ge 1 ] && [ "$RSRQ" -lt 65 ]; then
                    echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                    echo 0 > /sys/class/leds/hc:blue:sig2/brightness
                    echo 0 > /sys/class/leds/hc:blue:sig3/brightness
                else
                    echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                    echo 0 > /sys/class/leds/hc:blue:sig2/brightness
                    echo 0 > /sys/class/leds/hc:blue:sig3/brightness
               fi
            else
                echo 0 > /sys/class/leds/hc:blue:cmode5/brightness
                echo 0 > /sys/class/leds/hc:blue:cmode4/brightness
                echo 0 > /sys/class/leds/hc:blue:sig1/brightness
                echo 0 > /sys/class/leds/hc:blue:sig2/brightness
                echo 0 > /sys/class/leds/hc:blue:sig3/brightness
                echo 1 > /sys/class/leds/hc:blue:int/brightness
            fi
        elif echo "$modconf" | grep -q "MT5700"; then
            network_mode=$(sendat 1 'AT^HCSQ?')
            OUTPUT=$(sendat 1 'AT^MONSC' | sed -n '2p')
            # 检查输出是否包含NR（即网络类型为NR）
            echo $OUTPUT | grep 'NR' &> /dev/null
            if [ $? -ne 0 ]; then
                echo $OUTPUT | grep 'LTE' &> /dev/null
                if [ $? -ne 0 ]; then
                    echo 0 > /sys/class/leds/hc:blue:cmode5/brightness
                    echo 0 > /sys/class/leds/hc:blue:cmode4/brightness
                    echo 0 > /sys/class/leds/hc:blue:sig1/brightness
                    echo 0 > /sys/class/leds/hc:blue:sig2/brightness
                    echo 0 > /sys/class/leds/hc:blue:sig3/brightness
                    echo 1 > /sys/class/leds/hc:blue:int/brightness
                    #echo 1 > /sys/class/leds/red:wan/brightness
                    sleep 9
                    continue
                else
                    #LTE 4G解析数据
                    #echo 1 > /sys/class/leds/blue:wlan/brightness
                    RSRQ=$(echo $OUTPUT | cut -d ',' -f9)
                    RSRQ=$(echo $OUTPUT | cut -d ',' -f9 | sed 's/[^-.0-9]//g')
                    # 根据 RSRQ 的值设置 CSQ_PER
                    if [ "$RSRQ" -ge -3 ]; then
                        echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                        echo 1 > /sys/class/leds/hc:blue:sig2/brightness
                        echo 1 > /sys/class/leds/hc:blue:sig3/brightness
                    elif [ "$RSRQ" -ge -5 ] && [ "$RSRQ" -lt -3 ]; then
                        echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                        echo 1 > /sys/class/leds/hc:blue:sig2/brightness
                        echo 1 > /sys/class/leds/hc:blue:sig3/brightness
                    elif [ "$RSRQ" -ge -10 ] && [ "$RSRQ" -lt -5 ]; then
                        echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                        echo 1 > /sys/class/leds/hc:blue:sig2/brightness
                        echo 1 > /sys/class/leds/hc:blue:sig3/brightness
                    elif [ "$RSRQ" -ge -11 ] && [ "$RSRQ" -lt -10 ]; then
                        echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                        echo 1 > /sys/class/leds/hc:blue:sig2/brightness
                        echo 1 > /sys/class/leds/hc:blue:sig3/brightness
                    elif [ "$RSRQ" -ge -12 ] && [ "$RSRQ" -lt -11 ]; then
                        echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                        echo 1 > /sys/class/leds/hc:blue:sig2/brightness
                        echo 1 > /sys/class/leds/hc:blue:sig3/brightness
                    elif [ "$RSRQ" -ge -15 ] && [ "$RSRQ" -lt -12 ]; then
                        echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                        echo 1 > /sys/class/leds/hc:blue:sig2/brightness
                        echo 0 > /sys/class/leds/hc:blue:sig3/brightness
                    elif [ "$RSRQ" -ge -17 ] && [ "$RSRQ" -lt -15 ]; then
                        echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                        echo 0 > /sys/class/leds/hc:blue:sig2/brightness
                        echo 0 > /sys/class/leds/hc:blue:sig3/brightness
                    else
                        echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                        echo 0 > /sys/class/leds/hc:blue:sig2/brightness
                        echo 0 > /sys/class/leds/hc:blue:sig3/brightness
                    fi
                fi
            else
                RSRQ=$(echo $OUTPUT | cut -d ',' -f10)
                RSRQ=$(echo $OUTPUT | cut -d ',' -f10 | sed 's/[^-.0-9]//g')
                if [ "$RSRQ" -ge -3 ]; then
                    echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig2/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig3/brightness
                elif [ "$RSRQ" -ge -5 ] && [ "$RSRQ" -lt -3 ]; then
                    echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig2/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig3/brightness
                elif [ "$RSRQ" -ge -10 ] && [ "$RSRQ" -lt -5 ]; then
                    echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig2/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig3/brightness
                elif [ "$RSRQ" -ge -11 ] && [ "$RSRQ" -lt -10 ]; then
                    echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig2/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig3/brightness
                elif [ "$RSRQ" -ge -12 ] && [ "$RSRQ" -lt -11 ]; then
                    echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig2/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig3/brightness
                elif [ "$RSRQ" -ge -15 ] && [ "$RSRQ" -lt -12 ]; then
                    echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                    echo 1 > /sys/class/leds/hc:blue:sig2/brightness
                    echo 0 > /sys/class/leds/hc:blue:sig3/brightness
                elif [ "$RSRQ" -ge -17 ] && [ "$RSRQ" -lt -15 ]; then
                    echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                    echo 0 > /sys/class/leds/hc:blue:sig2/brightness
                    echo 0 > /sys/class/leds/hc:blue:sig3/brightness
                else
                    echo 1 > /sys/class/leds/hc:blue:sig1/brightness
                    echo 0 > /sys/class/leds/hc:blue:sig2/brightness
                    echo 0 > /sys/class/leds/hc:blue:sig3/brightness
                fi
            fi
            # 判断网络模式并更新LED状态
            if echo "$network_mode" | grep -Eq "5G|NR"; then
                # 包含TDD，点亮hc:blue:cmode5，熄灭hc:blue:cmode4
                echo 1 > /sys/class/leds/hc:blue:cmode5/brightness
                echo 0 > /sys/class/leds/hc:blue:cmode4/brightness
                echo 0 > /sys/class/leds/hc:blue:int/brightness
                echo 1 > /sys/class/leds/blue:wlan/brightness
                echo 1 > /sys/class/leds/red:wan/brightness
            elif echo "$network_mode" | grep -q "LTE"; then
                # 包含LTE，点亮hc:blue:cmode4，熄灭hc:blue:cmode5
                echo 1 > /sys/class/leds/hc:blue:cmode4/brightness
                echo 0 > /sys/class/leds/hc:blue:cmode5/brightness
                echo 0 > /sys/class/leds/hc:blue:int/brightness
                echo 1 > /sys/class/leds/blue:wlan/brightness
                echo 0 > /sys/class/leds/red:wan/brightness
            else
                # 其他网络，熄灭hc:blue:cmode5和hc:blue:cmode4
                echo 0 > /sys/class/leds/hc:blue:cmode5/brightness
                echo 0 > /sys/class/leds/hc:blue:cmode4/brightness
                echo 0 > /sys/class/leds/hc:blue:sig1/brightness
                echo 0 > /sys/class/leds/hc:blue:sig2/brightness
                echo 0 > /sys/class/leds/hc:blue:sig3/brightness
                echo 1 > /sys/class/leds/hc:blue:int/brightness
                echo 0 > /sys/class/leds/blue:wlan/brightness
                echo 1 > /sys/class/leds/red:wan/brightness
            fi
            sleep 9
        fi
        sleep 9
    fi
    sleep 9
done

# 释放锁
flock -u 200


