#!/bin/sh
#by manper 20250529
# 一次性脚本(没有循环、不常驻)。
# s88: 原来文件后半段「每 10 秒轮询 usb0/eth3、自动建 usbwan 接口」的死循环已删除
# (它在上面的 exit 0 之后, 本来就不会执行); USB 网卡 / 手机共享的插拔处理改由
# /etc/hotplug.d/net/30-mwrt-usbnic 触发 /usr/bin/mwrt-usbnic, 见那个脚本。
rm -f /www/luci-static/resources/view/status/include/21_ethinfo.js
rm -f /www/luci-static/resources/view/status/include/11_modem.js
rm -f /usr/lib/lua/luci/view/admin_status/index/mwan.htm

touch /usr/bin/modemflag2.conf
touch /usr/bin/modemflag.conf

if lsusb | grep -q "5700"; then
    if [ ! -f /usr/bin/modemflag.conf ]; then
        if [ ! -f /usr/bin/modemflag2.conf ]; then
            sendat 1 'AT^SETAUTODIAL=1,1'
            sendat 1 'AT^SETAUTODIAL=0'
            sendat 1 'AT^SETAUTODIAL=1,1'
            sendat 1 'AT^TDPMCFG=0,0,0,0'
            sendat 1 'AT+CGDCONT=1,"IPV4V6"'
            sendat 1 'AT^LEDSWITCH=1'
            sendat 1 'AT^SETE5STICK=0'
            sendat 1 'AT^SETMODE=4'
            touch /usr/bin/modemflag2.conf
            echo "切换完成，重启设备..." > /tmp/lucimsg.file
            sleep 10
            reboot
            exit 0
        else
            touch /usr/bin/modemflag.conf
        fi
    fi
else
    echo "未检测到5700模组，跳过初始化"
fi


exit 0
