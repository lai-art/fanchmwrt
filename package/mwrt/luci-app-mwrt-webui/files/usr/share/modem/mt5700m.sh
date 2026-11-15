    #!/bin/sh
    #By Manper MT5700
    echo "SIM INIT..." >/tmp/simcardstat
    export MWRT_SENDAT_LOCAL=1   # s200 切卡/初始化只对内置模组, 接了 AK68 也不能走 ATSD
    PROGRAM="MT5700M_MODEM"
    printMsg() {
        local msg="$1"
        logger -t "${PROGRAM}" "${msg}"
    } #日志输出调用API

    # 检查是否存在锁文件 @Icey
    lock_file="/tmp/rm520n.lock"

    if [ -e "$lock_file" ]; then
    # 锁文件存在，获取锁定的进程 ID，并终止它
    locked_pid=$(cat "$lock_file")
    if [ -n "$locked_pid" ]; then
        echo "Terminating existing rm520n.sh process (PID: $locked_pid)"
        kill "$locked_pid"
        sleep 0.5  # s64 提速: 杀旧进程后略等即可(原 2s 偏保守)
    fi
    fi

    # 创建新的锁文件，记录当前进程 ID
    echo "$$" > "$lock_file"
    /sbin/uci commit   # s64 提速: commit 不必等 2s
    Modem_Enable=`uci -q get mwrt.@ndis[0].enable` || Modem_Enable=1
    #模块启动
    #模块开关
    if [ "$Modem_Enable" == 0 ]; then
        echo 0 >/sys/class/gpio/cpe-pwr/value
        printMsg "禁用模块，退出"
        rm $lock_file
        exit 0
    else
        printMsg "模块启用"
        echo 1 >/sys/class/gpio/cpe-pwr/value
        #预先开内置卡
        #echo 1 > /sys/class/gpio/cpe-sel0/value
    fi
    #先关闭数据！
    sleep 4   # s64 提速: 原 11s 是保守裕量, 实测 4s 足够模组上电稳定

    Sim_Sel=`uci -q get mwrt.@ndis[0].simsel`|| Sim_Sel=0
    echo "simsel: $Sim_Sel" >> /tmp/moduleInit
    #SIM选择

    Enable_IMEI=`uci -q get mwrt.@ndis[0].enable_imei` || Enable_IMEI=0
    #IMEI修改开关

    RF_Mode=`uci -q get mwrt.@ndis[0].smode` || RF_Mode=0
    #网络制式 0: Auto, 1: 4G, 2: 5G
    NR_Mode=`uci -q get mwrt.@ndis[0].nrmode` || NR_Mode=0
    #0: Auto, 1: SA, 2: NSA
    Band_LTE=`uci -q get mwrt.@ndis[0].bandlist_lte` || Band_LTE=0
    Band_SA=`uci -q get mwrt.@ndis[0].bandlist_sa` || Band_SA=0
    Band_NSA=`uci -q get mwrt.@ndis[0].bandlist_nsa` || Band_NSA=0
    #Enable_PING=`uci -q get mwrt.@ndis[0].pingen` || Enable_PING=0
    #PING_Addr=`uci -q get mwrt.@ndis[0].pingaddr` || PING_Addr="119.29.29.29"
    #PING_Count=`uci -q get mwrt.@ndis[0].count` || PING_Count=10
    #FCN CI LOCK
    Earfcn=`uci -q get mwrt.@ndis[0].earfcn` || Earfcn=0
    Cellid=` uci -q get mwrt.@ndis[0].cellid` || Cellid=0
    Freqlock=` uci -q get mwrt.@ndis[0].freqlock` || Freqlock=0
    #
    switchNetwork=` uci -q get mwrt.@ndis[0].switchNetwork` || switchNetwork=0
    RF_Mode2=`uci -q get mwrt.@ndis[0].smode2` || RF_Mode2=0
    Autoswitchtime=` uci -q get mwrt.@ndis[0].Autoswitchtime` || Autoswitchtime="00-07"

     #-----------------SIM Card switch
     #attention！ims enable and autosel enable will make some card work under 4G network
    Sim_Sel=`uci -q get mwrt.@ndis[0].simsel`|| Sim_Sel=0

    # ================= 卡槽值必须按机型夹一次,别盲信 uci =================
    # 三卡槽布局(外置SIM1=0 / 外置SIM2=6 / 内置卡=1|2)是 C2000 MAX/Ultra 专属;
    # 其余机型(H5000M / 87N 等)物理上只有一个机身卡槽,走的是 6 这条路由
    # (AT^SCICHG=0,1)。而 /etc/config/mwrt 出厂默认 simsel='0'(给 C2000 准备的),
    # 于是首次刷机开机就照 0 去切 -> AT^SCICHG=1,0 指向本机不存在的那条卡路由,
    # 模组报 ^SIMSQ: 1,0(SIM卡未插入)、AT+CPIN? 回 +CME ERROR: 10、拨不上号;
    # 非得去"卡槽选择"点一次保存并应用(该下拉框对非 C2000 只有 6 这一项)才有网。
    # 判据与 CBI(modem5700.lua)/simstat.sh/页脚一致: 机型串含 c2000。
    IS_C2000=0
    case "$(cat /tmp/sysinfo/model 2>/dev/null) $(cat /tmp/sysinfo/board_name 2>/dev/null)" in
        *c2000*|*C2000*) IS_C2000=1 ;;
    esac
    # s197 C5800(本体 4 个外置卡槽 + 2 个内置卡槽 = 6 卡槽, 4 根选择脚 cpe-sel3..0, 编码照出厂固件):
    # 只对 C5800 生效, simsel 取 0-5 (0/3/4/5=外置1-4, 1/2=内置1-2); 其余机型的逻辑原样不动
    IS_C5800=0
    case "$(cat /tmp/sysinfo/model 2>/dev/null) $(cat /tmp/sysinfo/board_name 2>/dev/null)" in
        *c5800*|*C5800*) IS_C5800=1 ;;
    esac
    if [ "$IS_C5800" = "1" ]; then
        case "$Sim_Sel" in 0|1|2|3|4|5) ;; *) printMsg "C5800 simsel '${Sim_Sel:-<空>}' 不认识, 回落到 0"; Sim_Sel=0 ;; esac
    fi
    if [ "$IS_C2000" != "1" ] && [ "$IS_C5800" != "1" ] && [ "$Sim_Sel" != "6" ]; then
        printMsg "非C2000机型只有机身卡槽: simsel=${Sim_Sel:-<空>} 夹到 6"
        echo "simsel 夹取: ${Sim_Sel:-<空>} -> 6 (机身卡槽)" >> /tmp/moduleInit
        Sim_Sel=6
    fi
    # 未识别的值(空/脏数据)也落到本机真实存在的卡槽,而不是掉进 *) 分支去写内置卡
    case "$Sim_Sel" in
        0|1|2|6) ;;
        3|4|5) [ "$IS_C5800" = "1" ] || { printMsg "simsel $Sim_Sel 只有 C5800 才有, 回落"; [ "$IS_C2000" = 1 ] && Sim_Sel=0 || Sim_Sel=6; } ;;
        *) printMsg "simsel 值 '${Sim_Sel:-<空>}' 不认识,回落到 $([ "$IS_C2000" = 1 ] && echo 0 || echo 6)"
           [ "$IS_C2000" = "1" ] && Sim_Sel=0 || Sim_Sel=6 ;;
    esac

    echo $Sim_Sel > /tmp/sim_sel
    echo "simsel: $Sim_Sel" >> /tmp/moduleInit
    echo "simsel: $Sim_Sel"
    # cpe-sel0 是 C2000 独有的硬件 mux 引脚;别的机型没这个节点,写它只会刷错误日志
    # 还白等 2 秒,所以先探节点存在性(与 modem.lua 的 has_slot_mux 判据同源)。
    # N5000 的 DTS 照抄 Ultra 也导出了 cpe-sel0,但板上没有卡槽 mux(蜂窝走 USB 转接板),不碰它
    case "$(cat /tmp/sysinfo/model 2>/dev/null)" in *N5000*|*n5000*) NO_SEL0=1 ;; *) NO_SEL0=0 ;; esac
    # C5800 用自己的四脚编码(下面 c5800_slot), 不走 cpe-sel0 单脚
    [ "$IS_C5800" = "1" ] && NO_SEL0=1
    set_sel0() {
        [ "$NO_SEL0" = "1" ] && return 0
        [ -w /sys/class/gpio/cpe-sel0/value ] || return 0
        echo "$1" > /sys/class/gpio/cpe-sel0/value
    }
    #echo 0 > /sys/class/gpio/cpe-sel1/value  # 本板无此引脚,SIM_SEL1=cpe-sel0
    if [ "$NO_SEL0" != "1" ] && [ -w /sys/class/gpio/cpe-sel0/value ]; then
        set_sel0 0
        sleep 2
    fi
    # s197 C5800 六卡槽: 先把四根脚清零, 再按槽位写编码 + AT^SCICHG, 最后 HVSST 断开重连 SIM
    # (与出厂固件逐位一致: 0=外置1 1=内置1 2=内置2 3=外置2 4=外置3 5=外置4)
    c5800_slot() {
        local p3 p2 p1 p0 sc nm i
        case "$Sim_Sel" in
            0) p3=1; p2=0; p1=1; p0=0; sc='0,1'; nm="外置SIM卡槽1" ;;
            3) p3=1; p2=1; p1=1; p0=0; sc='0,1'; nm="外置SIM卡槽2" ;;
            4) p3=1; p2=1; p1=1; p0=1; sc='0,1'; nm="外置SIM卡槽3" ;;
            5) p3=1; p2=1; p1=0; p0=1; sc='0,1'; nm="外置SIM卡槽4" ;;
            1) p3=1; p2=1; p1=1; p0=1; sc='1,0'; nm="内置SIM卡槽1" ;;
            2) p3=0; p2=1; p1=1; p0=1; sc='1,0'; nm="内置SIM卡槽2" ;;
        esac
        printMsg "$nm"
        for i in 3 2 1 0; do [ -w /sys/class/gpio/cpe-sel$i/value ] && echo 0 > /sys/class/gpio/cpe-sel$i/value; done
        sleep 2
        [ -w /sys/class/gpio/cpe-sel3/value ] && echo $p3 > /sys/class/gpio/cpe-sel3/value
        [ -w /sys/class/gpio/cpe-sel2/value ] && echo $p2 > /sys/class/gpio/cpe-sel2/value
        [ -w /sys/class/gpio/cpe-sel1/value ] && echo $p1 > /sys/class/gpio/cpe-sel1/value
        [ -w /sys/class/gpio/cpe-sel0/value ] && echo $p0 > /sys/class/gpio/cpe-sel0/value
        sendat 1 "AT^SCICHG=$sc"
        sendat 1 'AT^HVSST=1,0'
        sleep 3
        sendat 1 'AT^HVSST=1,1'
        echo "$nm" >> /tmp/moduleInit
        echo "${nm}切换完成"
        echo "SIN卡UCI标识：$Sim_Sel"
        echo "$Sim_Sel" > /tmp/sim_sel
    }
    [ "$IS_C5800" = "1" ] && { c5800_slot; SLOT_DONE=1; } || SLOT_DONE=0
    [ "$SLOT_DONE" = "1" ] || case "$Sim_Sel" in
        6)
            # 同一条卡路由在 C2000 上是"外置SIM2(背面)",在 H5000M/87N 上就是唯一的机身卡槽,
            # 日志按机型说人话,免得以后查问题被"外置卡槽2"带偏
            [ "$IS_C2000" = "1" ] && printMsg "外置卡槽2" || printMsg "机身卡槽"
            #echo 1 > /sys/class/gpio/cpe-sel1/value  # 本板无此引脚,SIM_SEL1=cpe-sel0
            set_sel0 1
            sendat 1 'AT^SCICHG=0,1'
            sendat 1 'AT^HVSST=1,0'
            sleep 2
            sendat 1 'AT^HVSST=1,1'
            sendat 1 ' AT+CFUN=0'
            sleep 2
            sendat 1 ' AT+CFUN=1'
            echo "外置反面SIM卡" >> /tmp/moduleInit
            echo "外置反面SIM卡切换完成"
            echo "SIN卡UCI标识：$Sim_Sel"
            echo 6 > /tmp/sim_sel
        ;;
        0)
            printMsg "外置卡槽1"
            #echo 1 > /sys/class/gpio/cpe-sel1/value  # 本板无此引脚,SIM_SEL1=cpe-sel0
            set_sel0 0
            sendat 1 'AT^SCICHG=1,0'
            sendat 1 'AT^HVSST=1,0'
            sleep 2
            sendat 1 'AT^HVSST=1,1'
            sendat 1 ' AT+CFUN=0'
            sleep 2
            sendat 1 ' AT+CFUN=1'
            echo "外置正面SIM卡" >> /tmp/moduleInit
            echo "外置正面SIM卡切换完成"
            echo "SIN卡UCI标识：$Sim_Sel"
            echo 0 > /tmp/sim_sel
        ;;
        1)
            printMsg "内置卡"
            #echo 1 > /sys/class/gpio/cpe-sel1/value  # 本板无此引脚,SIM_SEL1=cpe-sel0
            set_sel0 1
            sendat 1 'AT^SCICHG=1,0'
            sendat 1 'AT^HVSST=1,0'
            sleep 2
            sendat 1 'AT^HVSST=1,1'
            sendat 1 ' AT+CFUN=0'
            sleep 2
            sendat 1 ' AT+CFUN=1'
            echo "内置SIM卡1" >> /tmp/moduleInit
            echo "内置SIM卡1切换完成"
            echo "SIN卡UCI标识：$Sim_Sel"
            echo 1 > /tmp/sim_sel
        ;;
        2)
            printMsg "内置卡"
            #echo 0 > /sys/class/gpio/cpe-sel1/value  # 本板无此引脚,SIM_SEL1=cpe-sel0
            set_sel0 1
            sendat 1 'AT^SCICHG=1,0'
            sendat 1 'AT^HVSST=1,0'
            sleep 2
            sendat 1 'AT^HVSST=1,1'
            sendat 1 ' AT+CFUN=0'
            sleep 2
            sendat 1 ' AT+CFUN=1'
            echo "内置SIM卡2" >> /tmp/moduleInit
            echo "内置SIM卡2切换完成"
            echo "SIN卡UCI标识：$Sim_Sel"
            echo 2 > /tmp/sim_sel
        ;;
        *)
            printMsg "未识别SIM卡槽"
            #echo 1 > /sys/class/gpio/cpe-sel1/value  # 本板无此引脚,SIM_SEL1=cpe-sel0
            set_sel0 1
            sendat 1 'AT^SCICHG=0,0'
            sendat 1 'AT^HVSST=1,0'
            sleep 2
            sendat 1 'AT^HVSST=1,1'
            sendat 1 ' AT+CFUN=0'
            sleep 2
            sendat 1 ' AT+CFUN=1'
            echo "外置正面SIM卡" >> /tmp/moduleInit
            echo "未识别卡槽"
            echo "SIN卡UCI标识：$Sim_Sel"
            #echo 0 > /tmp/sim_sel
        ;;
        esac

    #MT5700-IMEI
    if [ ${Enable_IMEI} == 1 ];then
        IMEI_file="/tmp/IMEI"
        if [ -e "$IMEI_file" ]; then
            last_IMEI=$(cat "$IMEI_file")
        else
            last_IMEI=-1
        fi
        IMEI=`uci -q get mwrt.@ndis[0].modify_imei`
        if [ "$IMEI" != "$last_IMEI" ]; then
            sendat 1 "AT+CFUN=0"
            sleep 2
            sendat 1 "AT^PHYNUM=IMEI,$IMEI" >> /tmp/moduleInit
            sleep 2
            sendat 1 "AT+CFUN=1"
            printMsg "IMEI: ${IMEI}"
            echo "修改IMEI $IMEI" >> /tmp/moduleInit
            echo "修改IMEI $IMEI"
            echo "$IMEI" > "$IMEI_file"
        else
            echo "IMEI未变动, 不执行操作" >> /tmp/moduleInit
            echo "IMEI未变动, 不执行操作"
        fi
    fi


    #Check if SIM or esim exist
    chkSimExt() {
        sleep 2   # s64 提速: 原 5s, 问 SIM 状态前的等待缩短
        simStat=$(sendat 1 'AT^SIMSQ?' | awk '/^\^SIMSQ:/ {split($0, a, ","); print a[2]}'| tr -d '\r\n')
        echo "状态码：$simStat"
        sleep 2   # s64 提速: 原 5s
        case $simStat in
            0)
                printMsg "SIM卡未插入."
                echo "SIM卡未插入" > /tmp/simcardstat
                echo "SIM卡未插入"
                printMsg "SIM卡未插入"
                ;;
            1)
                printMsg "SIM卡插入."
                echo "SIM卡已插入" > /tmp/simcardstat
                echo "SIM卡已插入"
                printMsg "SIM卡已插入"
                ;;
            2)
                echo "SIM卡被锁" > /tmp/simcardstat
                echo "SIM卡被锁"
                ;;
            3)
                echo "SIMLOCK 锁定(暂不支持上报)" > /tmp/simcardstat
                echo "SIMLOCK 锁定(暂不支持上报)"
                ;;
            10)
                echo "卡文件正在初始化 SIM Initializing" > /tmp/simcardstat
                ;;
            11)
                echo "卡初始化完成 （可接入网络）" > /tmp/simcardstat
                echo "卡初始化完成 （可接入网络）"
                printMsg "状态码11,卡初始化完成 （可接入网络）"
                ;;
            12)
                printMsg "SIM卡正常工作."
                echo "SIM卡正常工作" > /tmp/simcardstat
                echo "SIM卡正常工作"
                printMsg "状态码12,SIM卡正常工作"
                ;;
            98)
                echo "卡物理失效 （PUK锁死或者卡物理失效）" > /tmp/simcardstat
                ;;
            99)
                echo "卡移除 SIM removed" > /tmp/simcardstat
                ;;
            Note2)
                echo "不支持虚拟SIM卡" > /tmp/simcardstat
                ;;
            100)
                echo "卡错误（初始化过程中，卡失败）" > /tmp/simcardstat
                ;;
            *)
                echo "未知SIM卡状态" > /tmp/simcardstat
                echo "未知SIM卡状态 状态码：$simStat"
                printMsg "未知SIM卡状态 状态码：$simStat"
                ;;
        esac
    }

    chkSimExt
    moduleStartCheckLine
    rm $lock_file
    exit




