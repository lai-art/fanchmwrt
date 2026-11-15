#!/bin/sh
# Mwrt WAN Failover - 优化日志输出
#
# 日志只记"事件": 启动、开关变化、切换线路(及其失败)、互联网通断。
# 状态页(存活状态)直接把这份日志给用户看, 所以周期性的探测结果、内部状态名、
# 点灯动作一概不记; 同一个失败原因在恢复之前只记一次, 不按检测周期刷屏。

CONFIG_FILE="Mwrt-Assurance"
CONFIG_SECTION="wan_failover"
LOG_FILE="/tmp/mwrt_failover.log"

mkdir -p /tmp
[ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"

########################################
# 日志等级控制（DEBUG/INFO/WARN/ERROR）
LOG_LEVEL="INFO"   # 默认只记录 INFO 及以上
MAX_LOG_SIZE=64    # KB，日志轮替阈值(在 /tmp 里就是内存, 512M 机型上不能放大)

should_log() {
    local level="$1"
    case "$LOG_LEVEL" in
        DEBUG) return 0 ;;  # 全部记录
        INFO)  [ "$level" != "DEBUG" ] && return 0 || return 1 ;;
        WARN)  [ "$level" = "WARN" ] || [ "$level" = "ERROR" ] && return 0 || return 1 ;;
        ERROR) [ "$level" = "ERROR" ] && return 0 || return 1 ;;
        *) return 1 ;;
    esac
}

rotate_log() {
    if [ -f "$LOG_FILE" ] && [ "$(du -k "$LOG_FILE" | cut -f1)" -ge "$MAX_LOG_SIZE" ]; then
        mv "$LOG_FILE" "$LOG_FILE.old"
        touch "$LOG_FILE"
    fi
}

log_msg() {
    local level="$1"; shift
    local msg="$*"
    should_log "$level" || return 0
    rotate_log
    local ts; ts=$(date '+%F %T')
    echo "$ts [$level] $msg" >> "$LOG_FILE"
}

# 只记状态本身, 不写日志: 切换动作 switch_to 自己会记一行, 这里再记一行
# "WAN 状态变化: PRIMARY_OK" 对用户是重复的英文内部名
last_state=""
set_state() {
    last_state="$1"
}

# 同一件事(key)的提示, 内容没变就不重复记。切换失败这类问题在恢复之前每隔
# FAIL_THRESHOLD 个周期就会再撞一次, 不去重的话几秒一行。clear_once 在问题
# 消失时调用, 下次再出才会重新记。
# key 只用字母数字下划线(要拼进变量名)。
log_once() {
    local key="$1" level="$2"; shift 2
    local msg="$*"
    eval "[ \"\$_once_$key\" = \"\$msg\" ]" && return 0
    eval "_once_$key=\$msg"
    log_msg "$level" "$msg"
}
clear_once() {
    eval "_once_$1="
}

# 互联网通断。只在翻转时记, 而且新状态要连续两轮一致才算: 单个丢包不刷屏。
# 第一次(启动后)直接记当前状态。
last_net=""
net_new=""
net_n=0
note_net() {
    local v="$1"
    if [ "$v" = "$last_net" ]; then
        net_n=0
        return 0
    fi
    if [ "$v" = "$net_new" ]; then net_n=$((net_n + 1)); else net_new="$v"; net_n=1; fi
    [ -z "$last_net" ] || [ "$net_n" -ge 2 ] || return 0
    last_net="$v"
    net_n=0
    if [ "$v" = "1" ]; then
        log_msg "INFO" "互联网已连通，当前出口 $(active_if)"
    else
        log_msg "WARN" "互联网不通（检测地址 $PING_TARGET 不通）"
    fi
}

########################################
# LED 指示
#   有互联网 -> hc:blue:status 亮, hc:red:error 灭
#   无互联网 -> hc:red:error 亮, hc:blue:status 灭
#
# 直接写 sysfs 的 brightness。这两个灯 max_brightness 都是 1, 所以只有 0/1,
# 没有亮度中间档。
#
# hc:red:error 出厂 trigger 是 default-on —— 内核触发器还挂着的时候我们写
# brightness 只是临时生效, 触发器下次激活就覆盖回去, 所以先把 trigger 置成
# none 把控制权拿过来。hc:blue:status 出厂已经是 none, 一并置一次不影响。
#
# 每处都先判断节点可写再写: 这个脚本在别的板子上也跑, 那些板子没有这两个
# LED 节点, 找不到就安静跳过 —— 不报错、不刷日志、不影响故障切换本身。
# 同机上的 hc:red:int / hc:blue:cmode4 / hc:blue:cmode5 不碰。
LED_OK="/sys/class/leds/hc:blue:status"
LED_ERR="/sys/class/leds/hc:red:error"

led_write() {
    local led="$1"; local val="$2"
    [ -w "$led/brightness" ] && echo "$val" > "$led/brightness" 2>/dev/null
    return 0
}

# 摘触发器本身就是"抢灯"动作, 所以跟 set_leds 一样受 /tmp/ledflag.conf 门控。
#
# mwrt-ledsched 熄灯前会先把每个灯的 trigger/brightness 快照进
# mwrt_led.main.restore, 然后自己写 /tmp/ledflag.conf 让我们站开 (见它的
# do_off); 恢复时按快照把 trigger 写回去。我们在那期间摘触发器, 它记下的
# 现场就跟硬件对不上了 —— 用户点"恢复"会拿回一个 trigger=none 的灯。
#
# 原先这里不判断标记, 而本脚本在"保存并应用"后会被重起一次, 于是每次重起
# 都会从 ledsched 手里把灯抢走。改成标记在就跳过, 等标记撤销后由 set_leds
# 补做一次 (led_armed 记住做过没有)。
led_armed=0
led_init() {
    local led
    [ -f /tmp/ledflag.conf ] && return 0
    for led in "$LED_OK" "$LED_ERR"; do
        [ -w "$led/trigger" ] && echo none > "$led/trigger" 2>/dev/null
    done
    led_armed=1
    return 0
}

# 只在状态翻转时写, 免得每个检测周期都去动一次 sysfs
last_led=""
set_leds() {
    local online="$1"

    # /tmp/ledflag.conf 是本机既有的"灯光总开关"标记:
    #   /usr/bin/led.sh 选 1(全开) 写 "1"、选 2(全关) 写 "2"、
    #   选 3(恢复真实状态) 删掉它;
    #   /etc/init.d/modeminit 在有 /usr/bin/ledflagc.conf 时也会写 "0" 并全灭。
    # 标记在就别抢灯 —— 用户明确要求"全开/全关"的时候, 我们插一脚会让
    # hc:blue:status 自己跳回来, 看起来像坏了。等他选 3 再接回去。
    if [ -f /tmp/ledflag.conf ]; then
        # 清掉记忆: 标记一撤销, 下一轮立刻按真实状态重刷一次
        last_led=""
        # 标记期间 led_init 是跳过的, 撤销后得补一次, 否则 hc:red:error 的
        # default-on 还挂着, 我们写的 brightness 会被触发器盖回去
        led_armed=0
        return 0
    fi

    # 标记撤销后补做一次摘触发器 (启动时标记就在, 或 ledsched 刚恢复完)
    [ "$led_armed" = "1" ] || led_init

    # 点灯不记日志: 通断由 note_net 记(带防抖), 灯只是它的显示
    [ "$last_led" = "$online" ] && return 0
    if [ "$online" = "1" ]; then
        led_write "$LED_ERR" 0
        led_write "$LED_OK"  1
    else
        led_write "$LED_OK"  0
        led_write "$LED_ERR" 1
    fi
    last_led="$online"
}

########################################
get_config_value() {
    local option="$1"; local default="$2"
    local value
    value=$(uci get ${CONFIG_FILE}.${CONFIG_SECTION}.${option} 2>/dev/null)
    if [ -n "$value" ]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# s195: 备用口自适应。配置的网卡真实存在就原样用(5700/C2000 的 eth2 不变)；
# 不存在(或填 auto/留空)时，找 network 里带 modem_config 的蜂窝接口，取其 device
# (520 为 wwan0_1)，都没有才退回配置值。只在配置口不存在时才起 uci 进程。
resolve_secondary() {
    local cfg="$1" s d
    case "$cfg" in ""|auto) ;; *) [ -d "/sys/class/net/$cfg" ] && { echo "$cfg"; return; } ;; esac
    for s in $(uci show network 2>/dev/null | sed -n 's/^network\.\([^.]*\)\.modem_config=.*/\1/p'); do
        case "$s" in *[vV]6*) continue ;; esac
        d=$(uci get network.$s.device 2>/dev/null)
        [ -n "$d" ] || d=$(uci get network.$s.ifname 2>/dev/null)
        [ -n "$d" ] && [ -d "/sys/class/net/$d" ] && { echo "$d"; return; }
    done
    echo "${cfg:-eth2}"
}

get_iface_name_by_dev() {
    local dev="$1"
    uci show network 2>/dev/null | grep "device='$dev'" | awk -F. '{print $2}' | awk -F= '{print $1}' | head -n 1
}

# netifd 记的权威网关。默认路由被删掉之后它依然有效 —— 这正是切换之后
# 想把主口探回来时的处境。
#
# l3_device 和 device 都查: PPPoE 时 device=eth0 而 l3_device=pppoe-wan,
# 配置里填的是哪个都要能查到。
ubus_gateway() {
    local dev="$1"
    local sel gw
    command -v ubus >/dev/null 2>&1 || return 1
    command -v jsonfilter >/dev/null 2>&1 || return 1
    for sel in l3_device device; do
        gw=$(ubus call network.interface dump 2>/dev/null | \
             jsonfilter -e "@.interface[@.${sel}=\"$dev\"].route[@.target=\"0.0.0.0\"].nexthop" \
             2>/dev/null | grep -m1 '^[0-9]')
        [ -n "$gw" ] && echo "$gw" && return 0
    done
    return 1
}

# 取某个出口的网关。先问内核和 netifd 的权威信息, 再退到静态配置,
# 到最后宁可诚实失败, 也不编一个地址出来。
#
# 2026-10-08 真机测出来的两个毛病, 都出在原先那条"取 IP 前三段 + .1"的兜底上:
#
# (1) 编出来的网关会被当真。switch_to() 切换时先 `ip route del default`,
#     于是"从内核默认路由读"这条规则在**切换之后**必然落空 —— 而
#     check_primary_via_temp_route() 想把主口探回来, 正好是在这个时刻取网关。
#     剩下的规则也都落空(DHCP 口的 network.<iface>.gateway 实测是空的),
#     最后就落到兜底: 对 10.74.42.142/8 算出 10.74.42.1, 真网关是 10.0.0.1。
#     这台机器上它侥幸能用 —— 蜂窝模组对整个 /8 做 proxy ARP, 假地址真有人
#     应答(10.74.42.1 显示 REACHABLE, 而真网关 10.0.0.1 根本不回 ping)。
#     换一个不代理 ARP 的上行, 切回主口就是直接断网。
#
# (2) 备用口没有地址时, 兜底会返回一个光秃秃的 ".1"。
#     空字符串经 `cut -d. -f1-3` 还是空, 拼上 ".1" 就是 ".1" —— 非空,
#     于是 switch_to 的 `[ -n "$gw" ]` 闸门放它过去, 先 `ip route del default`
#     删掉**本来好用的**默认路由, 再 `ip route replace default via .1` 失败,
#     最后还记一行"默认路由已切换到 ... (.1)"。
#     结果: 本来只是主口坏了, 切完变成整台设备一条默认路由都没有, 日志还说成功。
#
# 所以这条兜底整个删掉。诚实失败的下游行为都是安全的:
#   switch_to -> 记一条"无网关"并且**不动**路由;
#   check_primary_via_temp_route -> 返回失败, 老老实实留在备用口。
#
# 顺带删掉 /tmp/dhcp.leases 那条: 那是本机 dnsmasq **发给 LAN 客户端**的租约,
# 第三列是客户端地址, 跟上行网关毫无关系 —— 真被 grep 命中(比如某个客户端主机名
# 里带 "eth2"), 反而会拿一个 LAN 客户端 IP 当网关用。
get_gateway() {
    local ifname="$1"
    local gw

    # 1) 内核里现成的默认路由: 没切换过的时候最快最准
    gw=$(ip route show dev "$ifname" | awk '/^default / {print $3; exit}')
    [ -n "$gw" ] && echo "$gw" && return 0

    # 2) netifd 的权威记录: 默认路由已被 switch_to 删掉时靠这条
    gw=$(ubus_gateway "$ifname")
    [ -n "$gw" ] && echo "$gw" && return 0

    # 3) 静态配置里写死的网关
    local netname
    netname=$(get_iface_name_by_dev "$ifname")
    if [ -n "$netname" ]; then
        gw=$(uci get network."$netname".gateway 2>/dev/null)
        [ -n "$gw" ] && echo "$gw" && return 0
    fi

    # 4) 任何提到这个口的默认路由
    gw=$(ip route | grep "$ifname" | awk '/default/ {print $3; exit}')
    [ -n "$gw" ] && echo "$gw" && return 0

    # 真的不知道了。这里不记日志: 跑在备用口上时 check_primary_via_temp_route
    # 每个检测周期都会问一次主口的网关, 主口没插线就每次都走到这里, 而那只是
    # "主口还没恢复", 不是新情况(原先每 5 分钟记一行, 状态页满屏都是它)。
    # 真正要用这个网关去切换却拿不到时, 由调用方记一次。
    return 1
}

check_primary_via_temp_route() {
    local ifname="$1"
    local target="$2"

    local gw
    gw=$(get_gateway "$ifname") || return 1

    if ! ip addr show dev "$ifname" | grep -q "inet "; then
        return 1
    fi

    ip route add "$target" via "$gw" dev "$ifname" 2>/dev/null
    local result=1
    if ping -I "$ifname" -c 2 -W 2 "$target" >/dev/null 2>&1; then
        result=0
    fi
    ip route del "$target" via "$gw" dev "$ifname" 2>/dev/null

    return $result
}

# 当前默认路由实际走哪个口。
# 点灯看的是实况, 而不是脚本自己记的 CURRENT_IF —— 后者只在本脚本切换时更新,
# 别处(ifup/DHCP/手动改路由)动过它并不知道。取不到就是没默认路由, 等于没网。
#
# 找 "dev" 后面那个词, 不按固定列取: 没有网关的默认路由(点对点口)长这样
# "default dev X proto static ...", 第 5 列是 "static", 不是网卡名。
# 多条时取第一条, 内核按 metric 从小到大排, 第一条就是实际在用的。
active_if() {
    ip -4 route show default 2>/dev/null | \
        awk '{for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit }}'
}

# 一条 IPv4 默认路由都没有时, 按 netifd 记的把各接口的默认路由补回来。
#
# 2026-10-15 真机: 模组页把网口从 WAN 改回 LAN 之后首页没有 WAN 流量。经过是
#   网关存活切到主口 eth1 时, 旧的 switch_to 把别的默认路由全删了, 连 netifd
#   给蜂窝(2_1/eth2, metric 11)装的那条也删了;
#   改回 LAN 时 eth1 回到网桥, 它上面的默认路由跟着没了, 网关存活也被关掉;
#   network reload 只重启配置变了的接口, 2_1 没变, 它那条路由 netifd 不会重装。
# 结果一条默认路由都不剩。switch_to 已经改成不删备用路由, 这里再兜一层:
# 别的程序删的、旧版本删的, 都能补回来。
#
# 补的就是 netifd 自己记着的那条(同网关、同 metric、同 src、proto static),
# 和它自己装的一模一样, 之后它增删都认得。
# 只在"一条都没有"时动手, 不在"有路由但缺某条"时补: 网关存活跑在备口上时,
# 主口那条是故意拿掉的, 补回来等于把坏掉的主口又抢回去。
#
# 但"一条都没有"也会出现在备口上: 跑在蜂窝上时主口那条已被顶掉, 蜂窝一重拨或
# 模组复位, eth2 上的路由被内核一起清掉, 表就空了。这时 netifd 还记着主口的网关,
# 照补就把坏主口装回 metric 0, 蜂窝回来只有 metric 11, 反被它压住, 要再等
# FAIL_THRESHOLD 轮才切回去。所以开着、自己决定跑在备口上时跳过主口:
# 主口好没好由 check_primary_via_temp_route 去探, 蜂窝回来 netifd 自己会装。
# force_primary=0 时守护进程不会自己探回主口, 那种情况照补, 免得谁都不补。
# primary_if 填的可能是 l3_device(pppoe-wan、br-lan)也可能是 device(eth1), 两个都比。
_rt_err=""
restore_defroutes() {
    if ip -4 route show default 2>/dev/null | grep -q .; then
        _rt_err=""
        return 0
    fi
    command -v ubus >/dev/null 2>&1 || return 0
    command -v jsonfilter >/dev/null 2>&1 || return 0

    local skip=""
    [ "$ENABLED" = "1" ] && [ "$FORCE_PRIMARY" = "1" ] && [ -n "$CURRENT_IF" ] && \
        [ "$CURRENT_IF" != "$PRIMARY_IF" ] && skip="$PRIMARY_IF"

    local i L D M G S src err got=""
    for i in $(ubus call network.interface dump 2>/dev/null | \
               jsonfilter -e '@.interface[@.up=true].interface' 2>/dev/null); do
        # 配置里写了不要默认路由、或者路由放在别的表里的接口, netifd 本来就不往主表装
        [ "$(uci -q get network."$i".defaultroute)" = "0" ] && continue
        [ -n "$(uci -q get network."$i".ip4table)" ] && continue

        L=""; D=""; M=""; G=""; S=""
        eval "$(ubus call network.interface."$i" status 2>/dev/null | jsonfilter \
            -e 'L=@.l3_device' -e 'D=@.device' -e 'M=@.metric' \
            -e 'G=@.route[@.target="0.0.0.0" && @.mask=0].nexthop' \
            -e 'S=@.route[@.target="0.0.0.0" && @.mask=0].source' 2>/dev/null)"
        # 同一个接口记了多条时取第一条; source 形如 "a.b.c.d/32", 只要地址
        G=${G%% *}; S=${S%% *}; S=${S%/*}
        case "$L" in ""|*[!A-Za-z0-9_.@-]*) continue ;; esac
        case "$G" in ""|*[!0-9.]*) continue ;; esac
        case "$M" in ""|*[!0-9]*) M=0 ;; esac
        [ -n "$skip" ] && { [ "$L" = "$skip" ] || [ "$D" = "$skip" ]; } && continue
        # 从查表到这里要 fork 好几次, 这期间 netifd 可能刚把它装上: 那是它自己装的,
        # 不算我们补的, 不记日志
        ip -4 route show default dev "$L" 2>/dev/null | grep -q . && continue
        src=""
        case "$S" in ""|0.0.0.0|*[!0-9.]*) ;; *) src="src $S" ;; esac

        # 网关是 0.0.0.0 的是点对点口, 没有下一跳, 直接挂在口上
        if [ "$G" = "0.0.0.0" ]; then
            err=$(ip route replace default dev "$L" proto static metric "$M" $src 2>&1)
        else
            err=$(ip route replace default via "$G" dev "$L" proto static metric "$M" $src 2>&1)
        fi
        if [ -n "$err" ]; then
            # 装不上的(比如手填的网关不在网段里)每轮都会再失败一次, 同样的报错只记一次
            if [ "$_rt_err" != "$L $err" ]; then
                logger -t mwrt_failover "restore default via $G dev $L metric $M: $err"
                _rt_err="$L $err"
            fi
            continue
        fi
        got="$got${got:+、}$L"
    done

    [ -n "$got" ] || return 0
    _rt_err=""
    CURRENT_IF=$(active_if)
    log_msg "WARN" "没有默认路由，已按网络配置补回 $got 的默认路由"
}

# 只 ping, 不做 ifup —— 专门给点灯用。
# check_online() 在没有 inet 地址时会顺手 ifup 再探, 那个副作用是故障切换需要
# 的; 点灯只是反映现状, 不该为了点灯去动接口。
probe_online() {
    local ifname="$1"
    [ -n "$ifname" ] || return 1
    ping -I "$ifname" -c 1 -W 2 "$PING_TARGET" >/dev/null 2>&1
}

check_online() {
    local ifname="$1"; local ping_target="$PING_TARGET"

    if ! ip addr show dev "$ifname" | grep -q "inet "; then
        ifup "$ifname"
        sleep 2
    fi

    if ping -I "$ifname" -c 2 -W 2 "$ping_target" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# 切默认路由。先装新的, 成功了再清掉旧的 —— 顺序很重要。
#
# 原先是先 `ip route del default` 再 `ip route replace`。只要 replace 失败
# (网关在链路上不可达、接口刚好掉下去), 设备就一条默认路由都没有了,
# 日志却照样记"已切换到 ..."。先装后清则最坏情况是留着旧的那条, 也就是
# 维持现状 —— 本来就坏的上行, 不会因为切换失败而变得更坏。
#
# 新路由不写 metric, 即 metric 0, 比 netifd 自己那条(本机实测 metric 11)优先,
# 所以装上就立刻生效, 不依赖旧的那条有没有删掉。
#
# 删旧路由只删"不是本次目标"的那些: 用 while 逐条删, 因为 `ip route del default`
# 一次只删一条, 多条并存时删不干净(上一轮测试就留下过两条)。
#
# 而且只删 metric 0 的。metric 更大的(netifd 给蜂窝装的 metric 11 那种)本来就
# 排在新路由后面, 抢不走流量, 留着正好是备用: 原先连它一起删, 网口改回 LAN、
# 主口那条随之消失后, 设备一条默认路由都没有了(见 restore_defroutes)。
# metric 0 在 `ip route` 输出里不显示, 所以排除的是带 "metric 1-9..." 的行。
#
# 第三个参数是切换原因, 和结果并成一行记(原先"准备切换"、"已切换"各记一行)。
# 失败用 log_once: 问题不解决, 每隔 FAIL_THRESHOLD 个周期就会再失败一次。
switch_to() {
    local ifname="$1"; local gw="$2"; local why="$3"
    [ -z "$gw" ] && log_once sw ERROR "切换到 $ifname 失败：取不到它的网关" && return

    local err
    err=$(ip route replace default via "$gw" dev "$ifname" 2>&1)
    if [ -n "$err" ]; then
        # ip 的原始报错是英文, 页面上不给用户看, 留在系统日志里排查用
        logger -t mwrt_failover "ip route replace default via $gw dev $ifname: $err"
        log_once sw ERROR "切换到 $ifname（网关 $gw）失败，路由没装上，保留原来的默认路由"
        return
    fi

    # 确认真的装上了, 再去动旧的
    if ! ip route show default | grep -q "via $gw dev $ifname"; then
        log_once sw ERROR "切换到 $ifname（网关 $gw）失败，新路由没出现在路由表里"
        return
    fi

    local n=0
    while [ $n -lt 8 ]; do
        local other
        other=$(ip route show default | grep -v "via $gw dev $ifname" | \
                grep -v ' metric [1-9]' | head -1)
        [ -z "$other" ] && break
        ip route del $other >/dev/null 2>&1 || break
        n=$((n+1))
    done

    CURRENT_IF="$ifname"
    clear_once sw
    log_msg "INFO" "${why}默认路由已切到 $ifname（网关 $gw）"
}

########################################
CURRENT_IF=$(active_if)
fail_count=0
success_count=0

ENABLED=$(get_config_value "enabled" "1")
PRIMARY_IF=$(get_config_value "primary_if" "eth0")
SECONDARY_IF=$(resolve_secondary "$(get_config_value "secondary_if" "eth2")")
PING_TARGET=$(get_config_value "ping_target" "8.8.8.8")
CHECK_INTERVAL=$(get_config_value "check_interval" "5")
FAIL_THRESHOLD=$(get_config_value "fail_threshold" "2")
SUCCESS_THRESHOLD=$(get_config_value "success_threshold" "3")
FORCE_PRIMARY=$(get_config_value "force_primary" "1")

if [ "$ENABLED" = "1" ]; then
    log_msg "INFO" "启动：网关存活已开启，主口 $PRIMARY_IF、备口 $SECONDARY_IF，每 $CHECK_INTERVAL 秒检测 $PING_TARGET；当前出口 ${CURRENT_IF:-无}"
else
    log_msg "INFO" "启动：网关存活未开启，只监测互联网通断（指示灯），不切换线路"
fi
last_enabled="$ENABLED"

# 先把这两个灯的内核触发器摘掉, 否则 hc:red:error 的 default-on 会跟我们抢
led_init

while true; do
    # 本轮的联网判断。留空 = 还不知道, 由轮末补一次探测。
    ONLINE=""
    # 开机时本脚本常常比拨号/DHCP 先起来, 那时一条默认路由都没有。不重读的话
    # CURRENT_IF 一直是空, 会走下面"不在主口上"的分支, 等主口 DHCP 一好就当成
    # "主口恢复"再切一遍(日志里每次开机都多出一条假的恢复记录)。
    [ -n "$CURRENT_IF" ] || CURRENT_IF=$(active_if)
    ENABLED=$(uci get ${CONFIG_FILE}.${CONFIG_SECTION}.enabled 2>/dev/null || echo "1")
    PRIMARY_IF=$(uci get ${CONFIG_FILE}.${CONFIG_SECTION}.primary_if 2>/dev/null || echo "eth0")
    SECONDARY_IF=$(resolve_secondary "$(uci get ${CONFIG_FILE}.${CONFIG_SECTION}.secondary_if 2>/dev/null || echo "eth2")")
    PING_TARGET=$(uci get ${CONFIG_FILE}.${CONFIG_SECTION}.ping_target 2>/dev/null || echo "8.8.8.8")
    CHECK_INTERVAL=$(uci get ${CONFIG_FILE}.${CONFIG_SECTION}.check_interval 2>/dev/null || echo "5")
    FAIL_THRESHOLD=$(uci get ${CONFIG_FILE}.${CONFIG_SECTION}.fail_threshold 2>/dev/null || echo "2")
    SUCCESS_THRESHOLD=$(uci get ${CONFIG_FILE}.${CONFIG_SECTION}.success_threshold 2>/dev/null || echo "3")
    FORCE_PRIMARY=$(uci get ${CONFIG_FILE}.${CONFIG_SECTION}.force_primary 2>/dev/null || echo "1")

    if [ "$ENABLED" != "$last_enabled" ]; then
        if [ "$ENABLED" = "1" ]; then
            log_msg "INFO" "网关存活已开启：主口 $PRIMARY_IF、备口 $SECONDARY_IF"
        else
            log_msg "INFO" "网关存活已关闭，不再自动切换线路"
        fi
        last_enabled="$ENABLED"
        # 关掉之前攒的计数作废, 重新打开时从零数, 不能一开就按旧账切换
        fail_count=0
        success_count=0
        clear_once fo
        clear_once sw
    fi

    # 开着关着都兜: 关着的时候更需要, 没人会再去装默认路由
    restore_defroutes

    # 故障切换停用时不动路由, 但灯照样要反映真实联网状态 ——
    # "有没有互联网"和"要不要自动切换"是两件事。
    #
    # 关着的时候路由归 netifd 和别人管, CURRENT_IF 跟着实况走。不跟的话它停在
    # 关闭之前的口上: 比如网口改回 LAN 时它还记着 eth1, 之后再改成 WAN 打开,
    # 守护进程以为自己已经在主口上, 不会把默认路由从蜂窝切过来。
    if [ "$ENABLED" != "1" ]; then
        CURRENT_IF=$(active_if)
        if probe_online "$CURRENT_IF"; then ONLINE=1; else ONLINE=0; fi
        set_leds "$ONLINE"
        note_net "$ONLINE"
        sleep "$CHECK_INTERVAL"
        continue
    fi

    # 开着的时候 CURRENT_IF 由本脚本自己维护, 但内核实况已经回到主口时要认下来:
    #   网口从 LAN 改回 WAN, 关着时 CURRENT_IF 跟到了蜂窝, 打开后 wan 一上来
    #   netifd 就装了 metric 0, 出口本来就在主口 —— 不认的话会走下面的"主口已恢复"
    #   再切一遍, 多记一条假记录, 还把 netifd 自己那条换成不归它管的;
    #   跑在备口上时 netifd 重装主口路由(重拨、换租)会顶掉我们的 metric 0, 出口又
    #   回到坏主口, 不认的话只会去探主口, 永远不会再切回备口。
    # 只在实况等于主口时纠正, 不无条件跟: 备口重拨的空窗里 active_if 是空的。
    [ "$CURRENT_IF" != "$PRIMARY_IF" ] && [ "$(active_if)" = "$PRIMARY_IF" ] && CURRENT_IF="$PRIMARY_IF"

    if [ "$CURRENT_IF" = "$PRIMARY_IF" ]; then
        if check_online "$PRIMARY_IF"; then
            fail_count=0
            success_count=$((success_count + 1))
            set_state "PRIMARY_OK"
            clear_once fo
            ONLINE=1
        else
            success_count=0
            fail_count=$((fail_count + 1))
            # 主口这一轮探测失败, 而默认路由还在主口上 —— 先按没网算。
            # 下面真切到备用口了再改回未知, 交给轮末重新探。
            ONLINE=0
            if [ "$fail_count" -ge "$FAIL_THRESHOLD" ]; then
                if ! check_online "$SECONDARY_IF"; then
                    ifup "$SECONDARY_IF"
                    sleep 3
                fi

                gw_secondary=$(get_gateway "$SECONDARY_IF")
                if [ -n "$gw_secondary" ]; then
                    switch_to "$SECONDARY_IF" "$gw_secondary" "主口 $PRIMARY_IF 连续 $FAIL_THRESHOLD 次不通，"
                    set_state "SECONDARY_ACTIVE"
                    clear_once fo
                    # 刚切过来, 备用口通不通这一轮还没探过, 置回未知
                    ONLINE=""
                else
                    log_once fo WARN "主口 $PRIMARY_IF 连续 $FAIL_THRESHOLD 次不通，但备口 $SECONDARY_IF 没有网关，暂时无法切换"
                fi
                fail_count=0
            fi
        fi
    else
        if [ "$FORCE_PRIMARY" = "1" ]; then
            if check_primary_via_temp_route "$PRIMARY_IF" "$PING_TARGET"; then
                gw_primary=$(get_gateway "$PRIMARY_IF")
                if [ -n "$gw_primary" ]; then
                    if [ -n "$CURRENT_IF" ]; then
                        switch_to "$PRIMARY_IF" "$gw_primary" "主口 $PRIMARY_IF 已恢复，"
                    else
                        switch_to "$PRIMARY_IF" "$gw_primary" "没有默认路由而主口 $PRIMARY_IF 可用，"
                    fi
                    set_state "PRIMARY_OK"
                    # 刚才 check_primary_via_temp_route 已经证明主口能出网
                    ONLINE=1
                fi
            fi
        fi
    fi

    # 点灯。本轮已经探出结果的直接用; 没探过的才补一次 —— 比如正跑在备用口
    # 上、这一轮只探了主口的情况。这样不会为了点灯把 ping 量翻倍。
    if [ -z "$ONLINE" ]; then
        if probe_online "$(active_if)"; then ONLINE=1; else ONLINE=0; fi
    fi
    set_leds "$ONLINE"
    note_net "$ONLINE"

    sleep "$CHECK_INTERVAL"
done
