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
        sleep 2  # 等待一段时间确保进程终止
    fi
    fi

    # 创建新的锁文件，记录当前进程 ID
    echo "$$" > "$lock_file"
    sleep 2 && /sbin/uci commit
    Modem_Enable=`uci -q get modem.@ndis[0].enable` || Modem_Enable=1
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
    sleep 11

    Sim_Sel=`uci -q get modem.@ndis[0].simsel`|| Sim_Sel=0
    echo "simsel: $Sim_Sel" >> /tmp/moduleInit
    #SIM选择

    Enable_IMEI=`uci -q get modem.@ndis[0].enable_imei` || Enable_IMEI=0
    #IMEI修改开关

    RF_Mode=`uci -q get modem.@ndis[0].smode` || RF_Mode=0
    #网络制式 0: Auto, 1: 4G, 2: 5G
    NR_Mode=`uci -q get modem.@ndis[0].nrmode` || NR_Mode=0
    #0: Auto, 1: SA, 2: NSA
    Band_LTE=`uci -q get modem.@ndis[0].bandlist_lte` || Band_LTE=0
    Band_SA=`uci -q get modem.@ndis[0].bandlist_sa` || Band_SA=0
    Band_NSA=`uci -q get modem.@ndis[0].bandlist_nsa` || Band_NSA=0
    #Enable_PING=`uci -q get modem.@ndis[0].pingen` || Enable_PING=0
    #PING_Addr=`uci -q get modem.@ndis[0].pingaddr` || PING_Addr="119.29.29.29"
    #PING_Count=`uci -q get modem.@ndis[0].count` || PING_Count=10
    #FCN CI LOCK
    Earfcn=`uci -q get modem.@ndis[0].earfcn` || Earfcn=0
    Cellid=` uci -q get modem.@ndis[0].cellid` || Cellid=0
    Freqlock=` uci -q get modem.@ndis[0].freqlock` || Freqlock=0
    #
    switchNetwork=` uci -q get modem.@ndis[0].switchNetwork` || switchNetwork=0
    RF_Mode2=`uci -q get modem.@ndis[0].smode2` || RF_Mode2=0
    Autoswitchtime=` uci -q get modem.@ndis[0].Autoswitchtime` || Autoswitchtime="00-07"

     #-----------------SIM Card switch
     #attention！ims enable and autosel enable will make some card work under 4G network
    Sim_Sel=`uci -q get modem.@ndis[0].simsel`|| Sim_Sel=0
    echo $Sim_Sel >> /tmp/sim_sel
    echo "simsel: $Sim_Sel" >> /tmp/moduleInit
    echo "simsel: $Sim_Sel"
    echo 0 > /sys/class/gpio/cpe-sel1/value
    echo 0 > /sys/class/gpio/cpe-sel0/value
    sleep 2
    case "$Sim_Sel" in
        6)
            printMsg "外置反面SIM卡"
            echo 1 > /sys/class/gpio/cpe-sel1/value
            echo 1 > /sys/class/gpio/cpe-sel0/value
            sendat 1 'AT^SCICHG=0,1'
            sendat 1 'AT^HVSST=1,0'
            sleep 3
            sendat 1 'AT^HVSST=1,1'
            sendat 1 ' AT+CFUN=0'
            sleep 3
            sendat 1 ' AT+CFUN=1'
            echo "外置反面SIM卡" >> /tmp/moduleInit
            echo "外置反面SIM卡切换完成"
            echo "SIN卡UCI标识：$Sim_Sel"
            echo 6 > /tmp/sim_sel
        ;;
        0)
            printMsg "外置正面SIM卡"
            echo 1 > /sys/class/gpio/cpe-sel1/value
            echo 0 > /sys/class/gpio/cpe-sel0/value
            sendat 1 'AT^SCICHG=0,1'
            sendat 1 'AT^HVSST=1,0'
            sleep 3
            sendat 1 'AT^HVSST=1,1'
            sendat 1 ' AT+CFUN=0'
            sleep 3
            sendat 1 ' AT+CFUN=1'
            echo "外置正面SIM卡" >> /tmp/moduleInit
            echo "外置正面SIM卡切换完成"
            echo "SIN卡UCI标识：$Sim_Sel"
            echo 0 > /tmp/sim_sel
        ;;
        1)
            printMsg "内置SIM卡1"
            echo 1 > /sys/class/gpio/cpe-sel1/value
            echo 1 > /sys/class/gpio/cpe-sel0/value
            sendat 1 'AT^SCICHG=1,0'
            sendat 1 'AT^HVSST=1,0'
            sleep 3
            sendat 1 'AT^HVSST=1,1'
            sendat 1 ' AT+CFUN=0'
            sleep 3
            sendat 1 ' AT+CFUN=1'
            echo "内置SIM卡1" >> /tmp/moduleInit
            echo "内置SIM卡1切换完成"
            echo "SIN卡UCI标识：$Sim_Sel"
            echo 1 > /tmp/sim_sel
        ;;
        2)
            printMsg "内置SIM卡2"
            echo 0 > /sys/class/gpio/cpe-sel1/value
            echo 1 > /sys/class/gpio/cpe-sel0/value
            sendat 1 'AT^SCICHG=1,0'
            sendat 1 'AT^HVSST=1,0'
            sleep 3
            sendat 1 'AT^HVSST=1,1'
            sendat 1 ' AT+CFUN=0'
            sleep 3
            sendat 1 ' AT+CFUN=1'
            echo "内置SIM卡2" >> /tmp/moduleInit
            echo "内置SIM卡2切换完成"
            echo "SIN卡UCI标识：$Sim_Sel"
            echo 2 > /tmp/sim_sel
        ;;
        *)
            printMsg "未识别SIM卡槽"
            echo 1 > /sys/class/gpio/cpe-sel1/value
            echo 1 > /sys/class/gpio/cpe-sel0/value
            sendat 1 'AT^SCICHG=0,0'
            sendat 1 'AT^HVSST=1,0'
            sleep 3
            sendat 1 'AT^HVSST=1,1'
            sendat 1 ' AT+CFUN=0'
            sleep 3
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
        IMEI=`uci -q get modem.@ndis[0].modify_imei`
        if [ "$IMEI" != "$last_IMEI" ]; then
            sendat 1 "AT+CFUN=0"
            sleep 2
            sendat 1 "AT^PHYNUM=IMEI,$IMEI" >> /tmp/moduleInit
            sleep 3
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
        sleep 5
        simStat=$(sendat 1 'AT^SIMSQ?' | awk '/^\^SIMSQ:/ {split($0, a, ","); print a[2]}'| tr -d '\r\n')
        echo "状态码：$simStat"
        sleep 5
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




