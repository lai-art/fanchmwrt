#!/bin/sh
# ============================================================================
# FM350 / RM520 SIM 卡槽选择 —— C2000MAX / C2000Ultra 专用
# ----------------------------------------------------------------------------
# 这两款板子的卡槽切换是纯硬件 mux:只写 GPIO cpe-sel0 即可,不需要华为 ^SCICHG
# (^SCICHG 是 MT5700 授权模组专用)。写完 GPIO 后用通用 3GPP 命令 AT+CFUN=0/1
# 让 FM350 软重启、重新读取新卡槽里的 SIM。
#
# ===================== 安全红线(封卡!)=====================
# 内置卡(机身卡槽)是授权模组(鲲鹏/MT5700)专属,非授权模组(FM350/RM520)
# 切到内置卡读取会导致【封卡】。s157 起 350/520 也可选内置卡,但必须是用户已确认
# "本机模组是原装鲲鹏内置模组、不是自己更换的第三方模组":页面/首页切卡时弹确认,
# 同意后才写 uci mwrt.@ndis[0].inner_ok=1;本脚本只认这个标记,没有标记的 simsel=1
# 一律当外置卡槽1处理,不写内置卡路由。
#   外置卡槽1(正面)-> cpe-sel0=0  (移远:QUIMSLOT=1,官方口径)
#   外置卡槽2(背面)-> cpe-sel0=1         (移远:QUIMSLOT=1)
#   内置卡(需确认) -> cpe-sel0=1 + 模组另一路 SIM 接口   (移远:QUIMSLOT=2)
#   任何未知/缺省值 -> 一律回落到 cpe-sel0=0(外置1),最安全。
# 移远 QUIMSLOT 映射以官方开发口径为准(s175):外置1 gpio0+1;外置2 gpio1+1;内置 gpio1+2。
# FM350 没有 QUIMSLOT,仍只写 GPIO。两板 DTS 都只有 cpe-sel0 一根引脚,无 cpe-sel1。
# ============================================================
#
# 用法:
#     fm350sim.sh [simsel值]      # 不传则读 uci mwrt.@ndis[0].simsel
#     FM350SIM_NOAT=1 fm350sim.sh # 只切 GPIO,不发 AT(开机/测试免断流用)
#     FM350SIM_INNER_OK=1 fm350sim.sh 1   # 已确认原装鲲鹏模组,才允许内置卡

SEL=/sys/class/gpio/cpe-sel0/value

# s195: 多卡槽/切卡只属于 C2000 系列。其余机型(H5000M、AP3000M 等)都是单卡槽，
# 一律不发 QUIMSLOT / CFUN，也不写 GPIO；判据与 simstat.sh 一致(型号或板名含 c2000)。
case "$(cat /tmp/sysinfo/model /tmp/sysinfo/board_name 2>/dev/null | tr 'A-Z' 'a-z')" in
    *c2000*) ;;
    *) logger -t fm350sim "非 C2000 机型，单卡槽，不切卡" 2>/dev/null; exit 0 ;;
esac

# 只对 FM350/RM520 生效;若在场的是 MT5700 授权模组,交给 mt5700m.sh(它才有权切内置卡)
if grep -q '5700' /tmp/modconf.conf 2>/dev/null; then
    logger -t fm350sim "MT5700 present, mt5700m.sh owns simsel; skip"
    exit 0
fi

[ -w "$SEL" ] || { logger -t fm350sim "no writable $SEL, abort"; exit 0; }

# N5000 的 DTS 照抄 Ultra 也有 cpe-sel0,但没有卡槽 mux(蜂窝走 USB 转接板),不写
case "$(cat /tmp/sysinfo/model 2>/dev/null)" in
    *N5000*|*n5000*) logger -t fm350sim "N5000 has no slot mux, skip"; exit 0 ;;
esac

Sim_Sel="$1"
[ -n "$Sim_Sel" ] || Sim_Sel=$(uci -q get mwrt.@ndis[0].simsel)

# 调用方(页面/首页切卡)在 uci 还没提交时通过环境变量 FM350SIM_INNER_OK=1 传入确认结果;开机走 uci 标记
INNER_OK="$FM350SIM_INNER_OK"
[ "$INNER_OK" = "1" ] || INNER_OK=$(uci -q get mwrt.@ndis[0].inner_ok)
qslot=""
case "$Sim_Sel" in
    2|6) val=1; name="外置卡槽2"; qslot=1 ;;   # s156 统一「卡槽/UI」页后外置SIM2 的取值是 6(旧页是 2),两个都认
    1)
        if [ "$INNER_OK" = "1" ]; then
            val=1; name="内置卡(用户已确认原装模组)"; qslot=2
        else
            logger -t fm350sim "simsel=1 but inner_ok!=1, refuse internal card -> ext1"
            val=0; name="外置卡槽1"; qslot=1
        fi ;;
    *) val=0; name="外置卡槽1"; qslot=1 ;;
esac

echo "$val" > "$SEL"
echo "$Sim_Sel" > /tmp/sim_sel
logger -t fm350sim "simsel=${Sim_Sel:-<empty>} ($name) -> cpe-sel0=$val"

# 让 FM350 重读 SIM:通用软重启(FM350 无 ^SCICHG)
if [ "$FM350SIM_NOAT" != "1" ]; then
    sleep 1
    # 移远模组:按上面的映射切 SIM 接口(应答里没有 +QUIMSLOT 就不是移远,跳过)
    if [ -n "$qslot" ] && sendat 1 'AT+QUIMSLOT?' 4 2>/dev/null | grep -q 'QUIMSLOT: '; then
        sendat 1 "AT+QUIMSLOT=$qslot" 4 >/dev/null 2>&1
        logger -t fm350sim "QUIMSLOT=$qslot"
    fi
    sendat 1 'AT+CFUN=0' >/dev/null 2>&1
    sleep 3
    sendat 1 'AT+CFUN=1' >/dev/null 2>&1
    logger -t fm350sim "AT+CFUN cycle done"
fi
exit 0
