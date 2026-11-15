#!/bin/sh
#by manper 20250529
# s88: 删掉 exit 0 之后的 usbwan 轮询死代码(从未执行); USB 网卡插拔改由 hotplug 触发, 见 /usr/bin/mwrt-usbnic。

if [ ! -f /usr/bin/modemflag.conf ]; then
    sleep 105
    #/usr/share/modem/v6.sh
    touch /usr/bin/modemflag.conf
    #reboot
    #exit 0
fi

rm -f /www/luci-static/resources/view/status/include/21_ethinfo.js
exit 0
