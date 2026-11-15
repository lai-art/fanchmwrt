#!/bin/sh
# Regenerate the modem WEBUI SPA backend config so its websocket host tracks the
# current br-lan LAN IP. Both SPA bundles fetch "/config.json" SAME-ORIGIN from the
# main uhttpd (docroot /www), then open a websocket to at.host:at.port. When the file
# is missing the SPA falls back to a hardcoded 192.168.88.1, which breaks after any LAN
# IP change. Writing the live LAN IP to /www/config.json keeps the WEBUI self-adapting.
#
# Historically this wrote /www/web/config.json (the :8888 uhttpd docroot), but the SPA
# is served same-origin under / by the MAIN server. The 5700 SPA fetches EXACTLY
# "/5700/config.json" (verified in umi*.js), so the authoritative file is
# /www/5700/config.json -- writing only /www/config.json left the SPA reading the
# bundle's stale 192.168.88.1 and connecting ws:// to the wrong host. We write every
# location a bundle might read so the serving layout can't defeat it.
#
# 2026-10-11 端口按模组分流。5700 的后端从 python websocket_server.py(8766) 换成了
# C 写的 webuiserver(8765),FM350 那一侧(/usr/bin/fm350webserver.py)仍然是 8766。
# 两边都读 config.json,所以端口不能再写死一个值:
#   /www/5700/config.json  → 5700 专属,始终 8765
#   /www/config.json       → 根路径回退,有 5700 时 8765,否则 8766
#   /www/web/config.json   → FM350 的 :8889 docroot,始终 8766,不受影响
# 判据和 modeminit 保持一致(lsusb 里有没有 5700),改一处要同时改那边。
ip="$(uci -q get network.lan.ipaddr)"
[ -n "$ip" ] || ip="192.168.1.1"

# 2026-10-11 加 "board" 字段:5700 前端「模组设置 → SIM卡配置 → 切换」读它。
# C2000 系列的卡槽是板级 GPIO 切的(蜂窝 → 卡槽/UI),模组自己的 AT 切卡在这类板子
# 上不对,所以前端见到 "c2000" 就把切换按钮换成引导链接。判据沿用全树惯例:
# model + board_name 转小写含 c2000。
case "$(cat /tmp/sysinfo/model /tmp/sysinfo/board_name 2>/dev/null | tr 'A-Z' 'a-z')" in
    *c2000*) board=c2000 ;;
    *)       board= ;;
esac

mkcfg() { printf '{"status":"true","at":{"host":"%s","port":%s},"board":"%s"}\n' "$ip" "$1" "$board"; }

# 5700 在位时根路径也跟着给 8765,否则新前端会去连已经不存在的 8766。
if lsusb 2>/dev/null | grep -q '5700'; then
    root_port=8765
else
    root_port=8766
fi

# The path the 5700 SPA actually fetches: /5700/config.json. 新前端(V2.2.2)先试
# /cgi-bin/at-ws-info(本机没有这个 CGI),失败后回退读 config.json,所以这个文件
# 仍然是它拿到 ws 地址的唯一来源。
[ -d /www/5700 ] && mkcfg 8765 > /www/5700/config.json

# Root path (some bundles / fallbacks fetch /config.json).
mkcfg "$root_port" > /www/config.json

# Legacy :8888 docroot copy (FM350 web bundle), harmless if that server is unused.
# 这一份永远是 8766 —— fm350webserver.py 还在用这个端口。
mkdir -p /www/web
mkcfg 8766 > /www/web/config.json

# s157 同源入口:350/520 前端也挂到主 uhttpd 的 /350/(符号链接指向 :8889 的 docroot),
# 这样远程维护窗口(只代理设备 80 口)和 HTTPS 访问都能直接打开;前端按文档目录取资源,
# 根路径(:8889)和 /350/ 两种访问方式共用同一份文件,不用再维护第二份。
ln -sfn /www/web /www/350


# s160 通用 WEBUI(5700 前端的 /gen/ 副本,后端 genws:8766,数据来自 QModem):
# 前端取 /gen/config.json;model 字段由 genws 按 QModem 识别出的型号写入,这里重写时沿用旧值。
if [ -d /www/gen ]; then
    gm="$(sed -n 's/.*"model": *"\([^"]*\)".*/\1/p' /www/gen/config.json 2>/dev/null | head -n1)"
    printf '{"status":"true","at":{"host":"%s","port":8766},"board":"%s","model":"%s"}\n' "$ip" "$board" "$gm" > /www/gen/config.json
fi
