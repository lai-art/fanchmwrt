#!/bin/sh
# 供 LuCI 轮询的 SIM 状态接口,输出 JSON。
#
# 切卡脚本 mt5700m.sh 跑一趟要 30 秒左右(含 sleep 11 + CFUN 循环 + chkSimExt),
# 它运行期间锁文件 /tmp/rm520n.lock 存在。这段时间本脚本不发任何 AT ——
# 一是别跟切卡脚本抢 AT 口,二是切换过程中的状态码没有参考价值,
# 直接回报"切换中"让界面显示进度即可。
#
# s64 提速 + 抗抖:AT 口被 websocket_server / qmodem / info 轮询抢着时,sendat 会等锁、
# 甚至超时返回空 —— 表现就是"卡槽读取很慢、动不动报模组未响应"。两招治它:
#   1) 结果缓存:每次读到有效状态就写 /tmp/simstat.cache(带 SEL 指纹)。CACHE_TTL 秒内
#      再被轮询直接回缓存、一条 AT 都不发 —— 页面 30 秒一问,绝大多数直接命中,秒回。
#   2) 粘滞兜底:真去读却读空(抢不到口/超时)时,不立刻翻脸报"模组无响应",而是回最近
#      STICKY 秒内的good缓存(同一卡槽),把偶发的空读糊过去;超过粘滞窗口才报未读到。
#   sendat 显式给 4 秒超时,读不到就快速失败,不再干等把页面拖住。
#   切卡(SEL 变了)会让缓存指纹对不上,自动作废,不会显示切换前的旧卡。
#
# s100:多回一个 phone 字段(AT+CNUM 读到的本机号码,首页「SIM卡信息」卡片用)。
#   读到号码 -> 只含数字和 +;卡里没存号码(+CME ERROR: 22 / 只回 OK) -> "-";
#   没读到(抢不到口/超时/无卡) -> "",下一轮再试,不把空读当成"没存"缓存下来。
#
# s156 分模组读:MT5700(华为)走 AT^SIMSQ?/AT^ICCID?;RM520/FM350 等其余模组走 3GPP + 移远 AT
#   (AT+CPIN? / AT+QCCID),归一成同一套状态码,页面与首页卡片不用分家:
#   READY→12  SIM PIN/PUK→2  CME ERROR 10(未插入)→0  CME ERROR 13 等(SIM 故障)→100。
#   开机后若移远模组还没读到卡(boot 时先上电后切 GPIO,模组没重读),每次开机自动软重启一次
#   (AT+CFUN=0/1,标记 /tmp/simstat.healed,不改任何模组配置),之后不再动。
#
# 输出的字段都是受控值(数字/中文/十六进制),不含引号和反斜杠,
# 故不做 JSON 转义(BusyBox sed 对转义表达式支持也不全)。

LOCK=/tmp/rm520n.lock
CACHE=/tmp/simstat.cache
CACHE_TTL=20      # 这么多秒内的缓存直接回,不碰 AT 口
STICKY=180        # 读空时,这么多秒内的good缓存拿来兜底
ATTMO=4           # 单条 AT 的超时(秒),抢不到口就快速失败

SEL=$(uci -q get mwrt.@ndis[0].simsel)
# 机型判定:三卡槽(外置SIM1/外置SIM2/内置卡)是 C2000 系列专属的硬件布局。
# 其余机型(H5000M 等)物理上只有一个卡槽,不论 simsel 取值一律显示"机身卡槽",
# 与"卡槽选择"下拉框保持一致,不暴露本机不存在的卡槽。判据与 CBI/页脚一致:含 c2000。
IDSTR=$(cat /tmp/sysinfo/model /tmp/sysinfo/board_name 2>/dev/null | tr 'A-Z' 'a-z')
case "$IDSTR" in
    *c2000*) IS_C2000=1 ;;
    *)       IS_C2000=0 ;;
esac
case "$(cat /tmp/modconf.conf 2>/dev/null)" in
    *5700*) IS_HW=1 ;;
    *)      IS_HW=0 ;;
esac
# s197 C5800: 4 外置 + 2 内置 六卡槽(simsel 0/3/4/5=外置1-4, 1/2=内置1-2), 只对 C5800 生效
case "$IDSTR" in *c5800*) IS_C5800=1 ;; *) IS_C5800=0 ;; esac
if [ "$IS_C5800" = "1" ]; then
    case "$SEL" in
        0)   SLOT="外置SIM卡槽1" ;;
        3)   SLOT="外置SIM卡槽2" ;;
        4)   SLOT="外置SIM卡槽3" ;;
        5)   SLOT="外置SIM卡槽4" ;;
        1)   SLOT="内置SIM卡槽1" ;;
        2)   SLOT="内置SIM卡槽2" ;;
        *)   SLOT="未知($SEL)" ;;
    esac
elif [ "$IS_C2000" = "1" ]; then
    if [ "$IS_HW" = "1" ]; then
        case "$SEL" in
            6)   SLOT="外置SIM2卡槽" ;;
            0)   SLOT="外置SIM1卡槽" ;;
            1|2) SLOT="内置卡" ;;
            *)   SLOT="未知($SEL)" ;;
        esac
    else
        # RM520/FM350 只暴露外置卡槽(内置卡是授权模组专属,切了会封卡),fm350sim.sh 也只认 2/6 为卡槽 2
        case "$SEL" in
            6|2) SLOT="外置SIM2卡槽" ;;
     # s163 用户已确认原装鲲鹏模组(uci inner_ok=1)时 simsel=1 才是内置卡; 没确认时 fm350sim.sh 也是当外置卡槽1
     1)   if [ "$(uci -q get mwrt.@ndis[0].inner_ok)" = "1" ]; then SLOT="内置卡"; else SLOT="外置SIM1卡槽"; fi ;;
            *)   SLOT="外置SIM1卡槽" ;;
        esac
    fi
else
    SLOT="机身卡槽"
fi

# s200 C5800 接了 AK68 且 ATSD 已通: sendat 已改走 AK68, 读到的是 AK68 里那张卡, 不是本机六卡槽中的任何一个。
# 卡槽名改标"AK68卡槽"; 缓存指纹换成 ak68(切入/切出时旧缓存自动作废); 模组种类按 AK68 里的实际型号判。
if [ "$IS_C5800" = "1" ] && [ -e /tmp/mwrt-ak68.atsd ]; then
    SLOT="AK68卡槽"; SEL="ak68"
    case "$(jsonfilter -i /tmp/mwrt-ak68.json -e '@.kind' 2>/dev/null)" in rm520n) IS_HW=0 ;; *) IS_HW=1 ;; esac
fi

# 切卡中:只回"切换中",不发 AT,也不碰缓存(切完下一轮自然刷新)。
if [ -e "$LOCK" ]; then
    PID=$(cat "$LOCK" 2>/dev/null)
    if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then
        printf '{"busy":1,"code":"","text":"正在切换卡槽,请稍候…","slot":"%s","iccid":"","phone":""}\n' "$SLOT"
        exit 0
    fi
fi

# 缓存文件格式(单行):<epoch>|<sel>|<code>|<iccid>|<phone>   (旧版四段缓存读出来 phone 为空,下一轮补读)
now=$(date +%s)
c_ts=""; c_sel=""; c_code=""; c_iccid=""; c_phone=""
if [ -f "$CACHE" ]; then
    IFS='|' read -r c_ts c_sel c_code c_iccid c_phone < "$CACHE" 2>/dev/null
fi

# 读本机号码:stdout 输出 号码 / "-" / 空。+CNUM 回包形如 +CNUM: "","+86138...",145
read_phone() {
    _r=$(sendat 1 'AT+CNUM' "$ATTMO" 2>/dev/null | tr -d '\r')
    _n=$(echo "$_r" | sed -n 's/^+CNUM: *[^,]*, *"\([^"]*\)".*/\1/p' | head -1 | tr -cd '0-9+')
    if [ -n "$_n" ]; then
        echo "$_n"
    elif echo "$_r" | grep -qE 'CME ERROR: *22|^OK'; then
        echo "-"
    fi
}
cache_age=999999
case "$c_ts" in ''|*[!0-9]*) ;; *) cache_age=$((now - c_ts)) ;; esac

# 把一个 code(+iccid)渲染成文案并输出 JSON;同时刷新 /tmp/simcardstat。
emit() {
    _code="$1"; _iccid="$2"; _phone="$3"
    case "$_code" in
        0)   _t="SIM卡未插入" ;;
        1)   _t="SIM卡已插入" ;;
        2)   _t="SIM卡被锁" ;;
        3)   _t="SIMLOCK 锁定" ;;
        10)  _t="卡文件正在初始化" ;;
        11)  _t="卡初始化完成(可接入网络)" ;;
        12)  _t="SIM卡正常工作" ;;
        98)  _t="卡物理失效(PUK锁死或卡损坏)" ;;
        99)  _t="卡已移除" ;;
        100) _t="卡错误(初始化失败)" ;;
        "")  _t="未读到状态(模组无响应)" ;;
        *)   _t="未知状态码 $_code,请参考 AT 手册" ;;
    esac
    echo "$_t" > /tmp/simcardstat
    printf '{"busy":0,"code":"%s","text":"%s","slot":"%s","iccid":"%s","phone":"%s"}\n' \
        "$_code" "$_t" "$SLOT" "$_iccid" "$_phone"
}

# 1) 新鲜缓存直接回(同一卡槽、CACHE_TTL 秒内),一条 AT 都不发 —— 这是提速的关键。
if [ "$c_sel" = "$SEL" ] && [ "$cache_age" -le "$CACHE_TTL" ] && [ -n "$c_code" ]; then
    # 有卡但号码还没读到过(旧缓存/上次抢口失败):只补读这一条,读到了回写缓存
    if [ -z "$c_phone" ]; then
        case "$c_code" in
            1|11|12)
                c_phone=$(read_phone)
                [ -n "$c_phone" ] && printf '%s|%s|%s|%s|%s\n' "$c_ts" "$c_sel" "$c_code" "$c_iccid" "$c_phone" > "$CACHE" 2>/dev/null
                ;;
        esac
    fi
    emit "$c_code" "$c_iccid" "$c_phone"
    exit 0
fi

# 2) 真读:给 sendat 显式超时,抢不到口就快速失败(返回空)。
CODE=""; ICCID=""; PHONE=""
if [ "$IS_HW" = "1" ]; then
    SQ=$(sendat 1 'AT^SIMSQ?' "$ATTMO" 2>/dev/null | tr -d '' | sed -n 's/^\^SIMSQ: *//p' | head -1)
    CODE=$(echo "$SQ" | cut -d, -f2)
else
    PIN=$(sendat 1 'AT+CPIN?' "$ATTMO" 2>/dev/null | tr -d '')
    case "$PIN" in
        *"+CPIN: READY"*)                CODE=12 ;;
        *"+CPIN: SIM PIN"*|*"+CPIN: SIM PUK"*|*"+CPIN: PH-"*) CODE=2 ;;
        *"CME ERROR: 10"*|*"not inserted"*) CODE=0 ;;
        *"CME ERROR: 1"[3-9]*|*"CME ERROR: 12"*|*"CME ERROR: 14"*) CODE=100 ;;
    esac
    # 开机后一直没读到卡:自动软重启模组一次(读卡发生在模组上电时,之后换了卡槽/GPIO 就不会重读)
    case "$CODE" in
        0|100)
            if [ ! -e /tmp/simstat.healed ] && [ "$(cut -d. -f1 /proc/uptime)" -gt 90 ]; then
                : > /tmp/simstat.healed
                ( sendat 1 'AT+CFUN=0' 6 >/dev/null 2>&1; sleep 3; sendat 1 'AT+CFUN=1' 6 >/dev/null 2>&1 ) &
            fi
            ;;
    esac
fi

if [ -n "$CODE" ]; then
    # 读到了:有卡才多发一条取 ICCID(空槽不白占 AT 口)
    case "$CODE" in
        1|11|12)
            if [ "$IS_HW" = "1" ]; then
                ICCID=$(sendat 1 'AT^ICCID?' "$ATTMO" 2>/dev/null | tr -d '' | sed -n 's/.*ICCID: *//p' | head -1)
            else
                ICCID=$(sendat 1 'AT+QCCID' "$ATTMO" 2>/dev/null | tr -d '' | sed -n 's/^+QCCID: *//p' | head -1 | tr -cd '0-9A-Za-z')
            fi
            PHONE=$(read_phone)
            ;;
    esac
    # 写缓存(指纹=当前 SEL)
    printf '%s|%s|%s|%s|%s
' "$now" "$SEL" "$CODE" "$ICCID" "$PHONE" > "$CACHE" 2>/dev/null
    emit "$CODE" "$ICCID" "$PHONE"
    exit 0
fi

# 3) 读空:粘滞兜底 —— 同一卡槽、STICKY 秒内有good缓存,就回缓存,别翻脸报"无响应"。
if [ "$c_sel" = "$SEL" ] && [ "$cache_age" -le "$STICKY" ] && [ -n "$c_code" ]; then
    emit "$c_code" "$c_iccid" "$c_phone"
    exit 0
fi

# 粘滞窗口也过了,确实读不到:如实报"未读到状态(模组无响应)"。
emit "" "" ""
