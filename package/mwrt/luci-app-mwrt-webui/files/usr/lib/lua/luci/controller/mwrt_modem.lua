module("luci.controller.modem", package.seeall)

function index()
    entry({"admin", "modem"}, firstchild(), _("蜂窝"), 25).dependent = false
	-- 「首页」一级菜单直接渲染设备概览页(zmode/modem_info),不再要二级「设备概览」子页。
	entry({"admin", "modeminfo"}, template("zmode/modem_info"), _("首页"), 2).dependent = false
    --entry({"admin", "modeminfo", "device_data"}, template("zmode/modem_info2"), _("数据监控"), 2)
	--entry({"admin", "modeminfo", "networkck"}, template("zmode/networkck"), _("网络体检"), 4)
	if nixio.fs.access("/etc/config/mwrtinfo.file") then
		--entry({"admin", "modeminfo", "routerdog"}, template("routerdog/index"), _("路由桌面"), 3)
	end
    local handle = io.popen("lsusb")
    local result = handle:read("*a") or ""
    handle:close()

    if result:find("5700") then
		os.execute("touch /usr/bin/modemflag.conf")
        entry({"admin", "modem", "webui"}, template("zmode/webui"), _("WEB界面"), 92)
        --entry({"admin", "modem", "nets"}, template("zmode/net_status_MT5700M"), _("模组状态"), 96)
		entry({"admin", "modem", "smsc"}, template("zmode/smsc"), _("短信管理"), 95)
		-- 短信设置端点只在识别到 5700 模组时注册(与上面的短信管理菜单同一判定),
		-- 其它机型/无模组时直接 404,不会去执行设备端脚本。只收 POST 并核对 CSRF token。
		entry({"admin", "modem", "smscfg"}, post("action_smscfg"))
    end

	-- s156 「卡槽/UI」页不再按模组分家:不论什么模组一律走 modem5700 这一份(页内各项已按
	-- /tmp/modconf.conf 自行门控),原来非 5700 的 cbi("modem")「其他设定」页不再挂菜单。
	entry({"admin", "modem", "modem"}, cbi("modem5700"), _("卡槽/UI"), 100)

	-- s160 通用 WEB界面:不是 5700 / FM350 / RM520 的其它模组(广和通、美格、鼎桥、中兴、Sierra...)也给一个 WEB界面,
	-- 用 5700 的前端(/gen/ 副本)、数据来自 QModem(genws 后端,8766)。判据:lsusb 里有这些厂商关键词,或 qmodem 已建出模组段。
	local generic = false
	if not (result:find("5700") or result:find("350") or result:find("0e8d:7127") or result:find("2c7c:")) then
		local low = result:lower()
		for _, key in ipairs({ "fibocom", "huawei", "zte", "sierra", "cinterion", "longsung", "meig", "me909", "simcom",
				"foxconn", "alcatel", "ublox", "telit", "td tech", "td-tech", "tdtech", "td500", "td510" }) do
			if low:find(key, 1, true) then generic = true; break end
		end
		if not generic and nixio.fs.access("/etc/config/qmodem") then
			local qh = io.popen("uci -q show qmodem 2>/dev/null | grep -c '=modem-device'")
			local qn = qh and tonumber(qh:read("*a") or "") or 0
			if qh then qh:close() end
			generic = qn > 0
		end
	end
	if generic then
		entry({"admin", "modem", "webui"}, template("zmode/webui-gen"), _("WEB界面"), 92)
	end

	-- FM350(0e8d:7127)与 RM520(移远 2c7c:0801)共用 :8889 的 fm350webserver 那套 WEB界面。
	-- 原来只认 "350" / "0e8d:7127",RM520 的 lsusb 行里两个都没有,菜单直接缺失。
	if result:find("350") or result:find("0e8d:7127") or result:find("2c7c:") then
        entry({"admin", "modem", "webui"}, template("zmode/webui-350"), _("WEB界面"), 92)
    end

    --entry({"admin", "status", "mwrtstyle"}, template("zmode/mwrtstyle2"), _("界面修改"), 93)
    -- s147 用户要求去掉「串口调试」菜单(页面不好看, 5700 WEB 界面里有 AT 调试终端)
    --entry({"admin", "modem", "at"}, template("zmode/at"), _("串口调试"), 97)
    entry({"admin", "modem", "simstat"}, call("action_simstat"))
    -- s197 NRadio C5800: POE 口(lan4)外接 AK68 状态(只读) / POE 开关与自动识别开关(必须 POST + CSRF token)。其它机型一律返回 supported=false。
    entry({"admin", "modem", "ak68_state"}, call("action_ak68_state"))
    entry({"admin", "modem", "ak68_set"}, call("action_ak68_set"))
    entry({"admin", "modem", "ak68_info"}, call("action_ak68_info"))
    -- 首页 SIM 卡槽那格的「快速切卡」浮窗用的两个端点(读写分开)。
    -- slots 只读, 按本机机型(是否 C2000)给出可切的卡槽清单, 与 cbi/modem5700 一致;
    -- simset 必须 POST 且带 CSRF token, 只接受 slots 清单里的值, 写 simsel 后后台跑切卡脚本。
    entry({"admin", "modem", "simslots"}, call("action_simslots"))
    entry({"admin", "modem", "simset"}, call("action_simset"))
    -- 首页「无线网桥」浮窗: 扫描上游 WiFi / 读桥接状态 / 加入(建 STA 客户端+挂 WAN+网关存活) / 断开还原。
    -- scan、status 只读; join、leave 必须 POST + CSRF token(会改无线/网络/防火墙, 风险高)。
    entry({"admin", "modem", "wlbridge_scan"}, call("action_wlbridge_scan"))
    entry({"admin", "modem", "wlbridge_status"}, call("action_wlbridge_status"))
    entry({"admin", "modem", "wlbridge_join"}, call("action_wlbridge_join"))
    entry({"admin", "modem", "wlbridge_leave"}, call("action_wlbridge_leave"))
    -- 首页设备图「USB 摄像头」悬停预览: camstart/camstop 必须 POST + CSRF token(会起停 ffmpeg 占用摄像头),
    -- camframe 只读 /tmp/mwrt-cam.jpg 并顺手刷新心跳, 不起任何进程。
    entry({"admin", "modem", "camstart"}, call("action_camstart"))
    entry({"admin", "modem", "camframe"}, call("action_camframe"))
    entry({"admin", "modem", "camstop"}, call("action_camstop"))
    -- 首页设备图「USB 声卡」: 音量 / 静音 / 输出与麦克风波形 / 音乐播放器(上传 + 外部存储 + 测试音)。
    -- audio_state、audio_wave 只读(顺手刷新心跳并确保守护 /usr/libexec/mwrt-audio 已起);
    -- 其余全部必须 POST + CSRF token。命令串里只拼接白名单后的整数 / 枚举 / 曲目 id, 不含任何用户字符串。
    entry({"admin", "modem", "audio_state"}, call("action_audio_state"))
    entry({"admin", "modem", "audio_wave"}, call("action_audio_wave"))
    entry({"admin", "modem", "audio_vol"}, call("action_audio_vol"))
    entry({"admin", "modem", "audio_mute"}, call("action_audio_mute"))
    entry({"admin", "modem", "audio_play"}, call("action_audio_play"))
    entry({"admin", "modem", "audio_ctl"}, call("action_audio_ctl"))
    entry({"admin", "modem", "audio_mic"}, call("action_audio_mic"))
    entry({"admin", "modem", "audio_upload"}, call("action_audio_upload"))
    entry({"admin", "modem", "audio_del"}, call("action_audio_del"))
    -- 首页「无线」磁贴右上角那个编辑键用的两个端点。
    -- get 只读(不回传密码),set 必须 POST 且带 CSRF token —— 见各自函数头的说明。
    entry({"admin", "modem", "wifi_get"}, call("action_wifi_get"))
    entry({"admin", "modem", "wifi_set"}, call("action_wifi_set"))
    -- 首页网口那格的「切换 WAN/LAN」(只有单网口的 C2000 MAX 有),读写分开,同上。
    entry({"admin", "modem", "port_get"}, call("action_port_get"))
    entry({"admin", "modem", "port_set"}, call("action_port_set"))
    -- 首页网口卡片上的 WAN / LAN 设置(所有机型通用,只改参数不动网口归属),get 只读,set 必须 POST 且带 CSRF token。
    entry({"admin", "modem", "wan_get"}, call("action_wan_get"))
    entry({"admin", "modem", "wan_set"}, call("action_wan_set"))
    entry({"admin", "modem", "lan_get"}, call("action_lan_get"))
    entry({"admin", "modem", "lan_set"}, call("action_lan_set"))
    -- s178 C8-668/688/5800 的四个交换机口各自设 WAN/LAN(+WAN 的上网方式), 只有 C8 系列有效。
    entry({"admin", "modem", "c8port_get"}, call("action_c8port_get"))
    entry({"admin", "modem", "c8port_set"}, call("action_c8port_set"))
    -- s181 出口信息浮窗的连通性检测(打开浮窗才调用)
    entry({"admin", "modem", "egress_probe"}, call("action_egress_probe"))
    -- 网口当 LAN 时识别插上来的是不是上级路由器/光猫,所有页面(mwrt-portsw.js)据此弹「要不要改成 WAN」。
    entry({"admin", "modem", "port_probe"}, call("action_port_probe"))
    entry({"admin", "modem", "port_probe_ignore"}, call("action_port_probe_ignore"))
    -- USB 网卡 / 手机共享的插拔处理(mwrt-usbnic):读状态;用户选 LAN/WAN;忽略(按 LAN)。
    -- state 只读,set / ignore 必须 POST 且带 CSRF token,同 port_set。
    entry({"admin", "modem", "usbnic_state"}, call("action_usbnic_state"))
    entry({"admin", "modem", "usbnic_set"}, call("action_usbnic_set"))
    entry({"admin", "modem", "usbnic_ignore"}, call("action_usbnic_ignore"))
    -- 首页/侧栏判断「有没有模组」: 与「其他设定/卡槽UI」页的「当前模组」同一套 lsusb 关键词,
    -- 只读 GET, 不碰串口, 不回传 lsusb 原文。
    entry({"admin", "modem", "modem_present"}, call("action_modem_present"))
    -- 5700 模组的结构化小区/载波聚合/邻区信息,给首页的"SIM卡信息 / 载波聚合 /
    -- 附近小区"三个板块用。只读 /tmp/mwrt_cellinfo.json,不碰串口 —— 采集由
    -- /usr/bin/mwrt-cellinfo 走 cron 独立完成。首页 4 秒一轮,AT 口经不起在
    -- 请求里同步跑十来条命令(admin/modem/nets 那条路就是这么把口子占满的)。
    entry({"admin", "modeminfo", "cellx"}, call("action_cellx"))
    entry({"admin", "modem", "get_csq"}, call("action_get_csq"))
    entry({"admin", "modem", "topo_data"}, call("action_topo_data"))
    entry({"admin", "modem", "unlock_state"}, call("action_unlock_state"))
	entry({"admin", "modem", "get_if"}, call("action_get_if"))
    entry({"admin", "modem", "send_atcmd"}, call("action_send_atcmd"))
    entry({"admin", "modem", "smscs"}, call("action_smscs"))
    entry({"admin", "modem", "smslist"}, call("action_smslist"))
    entry({"admin", "modem", "smsdel"}, call("action_smsdel"))
    entry({"admin", "modem", "smssend"}, call("action_smssend"))
    entry({"admin", "modem", "mwrtdf"}, call("action_mwrtdf"))
    entry({"admin", "modem", "mwrtco"}, call("action_mwrtco"))
    entry({"admin", "modem", "mwrtpk"}, call("action_mwrtpk"))
	entry({"admin", "modem", "mwrtgr"}, call("action_mwrtgr"))
	entry({"admin", "modem", "mwrtor"}, call("action_mwrtor"))
    entry({"admin", "modem", "mwrtinit"}, call("action_mwrtinit"), nil).leaf = true
    entry({"admin", "modem", "mwrtinit"}, call("action_mwrtinit"), nil).sysauth = false
	-- s101: 5700 通话/来电/短信通知接口。放在 lsusb 5700 分支之外,内部自己判在场与 phoneen。
	entry({"admin", "modem", "phone_state"}, call("action_phone_state")).leaf = true
	entry({"admin", "modem", "phone_dial"}, call("action_phone_dial")).leaf = true
	entry({"admin", "modem", "phone_answer"}, call("action_phone_answer")).leaf = true
	entry({"admin", "modem", "phone_hangup"}, call("action_phone_hangup")).leaf = true
	-- s105: 短信 / 未接来电通知的已读记录(设备端统一记录, 所有浏览器一致)。只收 POST 并核对 CSRF token(post(...) 注册),
	-- 放在 5700 分支之外: 内部不碰串口, 只写 /tmp/mwrt-phone/notice.ack。
	entry({"admin", "modem", "notice_ack"}, post("action_notice_ack")).leaf = true
end

-- 「当前模组」判定: 与 model/cbi/modem.lua、modem5700.lua 的 current_mod.cfgvalue 同一套关键词。
-- 逐行匹配 lowercased lsusb(根集线器行是 Linux Foundation, 不会误中);
-- 用 plain find, 关键词里的 "-" 不会被当成 Lua 模式字符。
local MODEM_KEYS = {
	"mediatek", "fm350", "quectel", "fibocom", "huawei", "zte", "sierra", "cinterion", "longsung",
	"meig", "me909", "simcom", "foxconn", "alcatel", "ublox", "telit",
	"td tech", "td-tech", "tdtech", "td500", "td510",
	-- 展锐 SRM821 等在 lsusb 里只显示 Spreadtrum / 5G Module,不带厂商名
	"spreadtrum", "unisoc", "5g module"
}

local function modem_detect()
	local h = io.popen("lsusb 2>/dev/null")
	local raw = h and (h:read("*a") or "") or ""
	if h then h:close() end
	for line in raw:lower():gmatch("[^\r\n]+") do
		for _, key in ipairs(MODEM_KEYS) do
			if line:find(key, 1, true) then
				return true, (line:match("([%w%-]+)%s*$") or "")
			end
		end
	end
	-- lsusb 里认不出厂商时,以 qmodem 已建出的模组段为准(段里 path 指向的 USB 设备确实在场)
	local found, nm = false, ""
	local ok = pcall(function()
		require("luci.model.uci").cursor():foreach("qmodem", "modem-device", function(sec)
			if not found and sec.path and nixio.fs.access(sec.path) then
				found = true
				nm = sec.name or ""
			end
		end)
	end)
	if ok and found then return true, nm end
	return false, ""
end

function action_modem_present()
	local ok, model = modem_detect()
	luci.http.header("Cache-Control", "no-store")
	luci.http.prepare_content("application/json")
	luci.http.write_json({ present = ok, model = model })
end

function action_mwrtinit()
	local rv ={}
	local p = luci.http.formvalue("p")
	local set = luci.http.formvalue("set")
	local fixed = "txt"
	port= string.gsub(p, "\"", "~")
	rv["at"] = fixed 
	rv["port"] = port
	local file_exist = nixio.fs.access("/usr/bin/modemflag.conf")
	local handle = io.popen("lsusb")
    local result = handle:read("*a") or ""
    handle:close()

    if result:find("5700") then
		if file_exist then
			rv["rv"] = "OK"
		else
			rv["rv"] = "NO"
		end
	else
		rv["rv"] = "OK"
    end
	luci.http.prepare_content("application/json")
	luci.http.write_json(rv)
end

function action_mwrtco()
	local source_file = "/usr/share/modem/cascade.cssdf"
	local target_file = "/www/luci-static/argon/css/cascade.css"
	local command4 = string.format("cp %s %s", source_file, target_file)
	--os.execute(command4)
	local p = luci.http.formvalue("p")
	port= string.gsub(p, "\"", "~")
	local S = port
	local command = string.format("sed -i 's/--primary:[^;]*/--primary:%s;/' /www/luci-static/argon/css/cascade.css", S)
	os.execute(command)
	local command2 = string.format("sed -i 's/--bar-bg:[^;]*/--bar-bg:%s;/' /www/luci-static/argon/css/cascade.css", S)
	os.execute(command2)
	os.execute("/etc/init.d/uhttpd restart")
end

function action_mwrtdf()
	local source_file = "/usr/share/modem/cascade.cssdf"
	local target_file = "/www/luci-static/argon/css/cascade.css"
	local command = string.format("cp %s %s", source_file, target_file)
	os.execute(command)
	os.execute("/etc/init.d/uhttpd restart")
end

function action_mwrtpk()
	local source_file = "/usr/share/modem/cascade.csspk"
	local target_file = "/www/luci-static/argon/css/cascade.css"
	local command = string.format("cp %s %s", source_file, target_file)
	os.execute(command)
	os.execute("/etc/init.d/uhttpd restart")
end

function action_mwrtgr()
	local source_file = "/usr/share/modem/cascade.cssgr"
	local target_file = "/www/luci-static/argon/css/cascade.css"
	local command = string.format("cp %s %s", source_file, target_file)
	os.execute(command)
	os.execute("/etc/init.d/uhttpd restart")
end

function action_mwrtor()
	local source_file = "/usr/share/modem/cascade.cssor"
	local target_file = "/www/luci-static/argon/css/cascade.css"
	local command = string.format("cp %s %s", source_file, target_file)
	os.execute(command)
	os.execute("/etc/init.d/uhttpd restart")
end

function action_smscs()
	local rv ={}
	local file
	local p = luci.http.formvalue("p")
	local set = luci.http.formvalue("set")
	fixed = set
	port= string.gsub(p, "\"", "~")
	rv["at"] = fixed 
	rv["port"] = port

	os.execute("/usr/share/modem/smsc.sh \'" .. port .. "\' \'" .. fixed .. "\'")
	smsc = "/tmp/smsc.at"
	file = io.open(smsc, "r")
	if file ~= nil then
		rv["smsc"] = file:read("*all")
		file:close()
	else
		rv["smsc"] = " "
	end
	os.execute("/usr/share/modem/rsmsc.sh")
	luci.http.prepare_content("application/json")
	luci.http.write_json(rv)
end

-- 读短信,返回结构化 JSON。
--
-- action_smscs 回的是给老页面拼字符串用的文本块,发件人/时间/内容全靠行号切,
-- 已读未读更是塞不进去。这里直接用 pdu_decoder --json,它带 +CMGL 的 stat 位
-- (0=未读 1=已读),顺带把长短信的各段合成一条。AT+CPMS? 给出占用格数。
function action_smslist()
	local jsonc = require "luci.jsonc"
	-- s105: 读短信开始前先记下通话守护的事件序号(/tmp/mwrt-phone/seq, 只读一个小文件)。
	-- 收件箱页读取成功后用它 ack「序号 <= evseq」的短信事件: 这些事件在读取开始前就已经到达模组, 一定在这次列表里;
	-- 读取期间新到的短信序号更大, 不会被误标为已读。本接口仍是只读(不写 ack), 避免被别的轮询误标。
	local evseq = tonumber(((require "nixio.fs").readfile("/tmp/mwrt-phone/seq", 32) or ""):match("^%s*(%d+)"))
	local pipe = io.popen(
		"/usr/bin/sendat 1 at+cmgl=4 20 2>/dev/null | /usr/bin/pdu_decoder --json 2>/dev/null")
	local decoded = pipe and jsonc.parse(pipe:read("*all") or "") or nil
	if pipe then pipe:close() end

	local rv = { ok = false, messages = {}, evseq = evseq }
	if type(decoded) == "table" and decoded.ok then
		rv.ok = true
		rv.messages = decoded.messages or {}
	end

	-- 读不到容量不算失败,列表照常显示,只是不画那个占用条。
	local storage = io.popen("/usr/bin/sendat 1 'AT+CPMS?' 5 2>/dev/null")
	if storage then
		local st, used, total = (storage:read("*all") or ""):match('%+CPMS:%s*"([^"]*)",(%d+),(%d+)')
		storage:close()
		rv.used = tonumber(used)
		rv.total = tonumber(total)
		-- 当前读取位置(SM=SIM 卡, ME=模组),页面据此显示「SIM 卡存储」还是「模组存储」。
		if st and st:match("^[A-Z_]+$") then rv.store = st end
	end

	luci.http.prepare_content("application/json")
	luci.http.write_json(rv)
end

-- 删短信。idx 是逗号分隔的存储槽位号(长短信有好几个),或者 all 删全部。
-- 一条命令一个槽位:模组不收槽位列表。从大到小删,免得剩下的槽位号在中途挪位。
function action_smsdel()
	local util = require "luci.util"
	local idx = luci.http.formvalue("idx") or ""
	local rv = { ok = false, error = "无效的短信编号" }

	if idx == "all" then
		os.execute("/usr/bin/sendat 1 'AT+CMGD=0,4' 30 >/dev/null 2>&1")
		rv = { ok = true }
	elseif idx:match("^%d+[%d,]*$") then
		local slots = {}
		for slot in idx:gmatch("%d+") do slots[#slots + 1] = tonumber(slot) end
		table.sort(slots, function(left, right) return left > right end)
		for _, slot in ipairs(slots) do
			os.execute("/usr/bin/sendat 1 " ..
				util.shellquote("AT+CMGD=" .. slot) .. " 10 >/dev/null 2>&1")
		end
		rv = { ok = #slots > 0, error = #slots > 0 and nil or "无效的短信编号" }
	end

	luci.http.prepare_content("application/json")
	luci.http.write_json(rv)
end

-- 发短信。POST 而不是 GET: 一条 2000 字的中文短信 urlencode 完就是几 KB,塞不进 URL。
-- 真正的编码和发送在 /usr/bin/smssend 里(pdul.lua 编 PDU + 单行 AT+CMGS),
-- 这个模组不认标准的 '>' 提示符握手,所以 sms_tool_q 那条路在这台机器上发不出去。
function action_smssend()
	local util = require "luci.util"
	local jsonc = require "luci.jsonc"
	local number = luci.http.formvalue("number") or ""
	local text = luci.http.formvalue("text") or ""
	local rv = { ok = false, error = "号码或内容不合法" }

	if number:match("^%+?[%d%s%-()]+$") and #number <= 32 and
	   text ~= "" and #text <= 2048 and not text:find("%z") then
		local pipe = io.popen("/usr/bin/smssend " .. util.shellquote(number) ..
			" " .. util.shellquote(text) .. " 2>/dev/null")
		local output = pipe and pipe:read("*all") or ""
		if pipe then pipe:close() end
		local decoded = jsonc.parse(output)
		if type(decoded) == "table" then
			rv = decoded
		else
			rv = { ok = false, error = "发送工具没有返回结果" }
		end
	end

	luci.http.prepare_content("application/json")
	luci.http.write_json(rv)
end

-- 短信设置(短信管理页的「设置」视图用)。读写都交给设备端脚本 /usr/bin/mwrt-smscfg,
-- 它内部全部经 sendat(带 /tmp/sendat.at.lock),这里不碰串口。
-- act 只认下面几个字面值;号码和存储位置先在这里校验一遍,脚本里还会再校验一遍,
-- 通过校验的值才会拼进命令(号码再过一次 shellquote)。入口用 post(...) 注册:只收 POST,
-- 并由 dispatcher 核对 CSRF token(smslist/smsdel 用的是 call(...),不核对 token,这里不照搬,
-- 因为 clear/toggle 这类写操作不能被别的网页借登录态触发)。
--   get      读状态(短信功能开关、短信中心号码、存储用量、CFUN),顺带带上短信转发是否启用
--   status   读开关任务进度(只读状态文件)
--   toggle   on=1|0,后台执行开/关短信功能,立即返回
--   csca     number=短信中心号码
--   cpms     r/w/n=SM|ME 读/写/收三个存储位置
--   clear    清空设备上所有短信
--   recover  模组停在飞行模式时恢复联网
function action_smscfg()
	local util = require "luci.util"
	local jsonc = require "luci.jsonc"
	local tool = "/usr/bin/mwrt-smscfg"
	local act = luci.http.formvalue("act") or "get"
	local cmd = nil

	if act == "get" or act == "status" or act == "clear" or act == "recover" then
		cmd = tool .. " " .. act
	elseif act == "toggle" then
		local on = luci.http.formvalue("on")
		if on == "1" or on == "0" then
			cmd = tool .. " toggle " .. on
		end
	elseif act == "csca" then
		local number = luci.http.formvalue("number") or ""
		if number:match("^%+?%d+$") and #number >= 3 and #number <= 21 then
			cmd = tool .. " csca " .. util.shellquote(number)
		end
	elseif act == "cpms" then
		local allowed = { SM = true, ME = true }
		local r = luci.http.formvalue("r")
		local w = luci.http.formvalue("w")
		local n = luci.http.formvalue("n")
		if allowed[r] and allowed[w] and allowed[n] then
			cmd = tool .. " cpms " .. r .. " " .. w .. " " .. n
		end
	end

	-- 输出先落到临时文件再读: 嵌入式 uhttpd 里 io.popen 的 read 会被后台子进程退出的信号打断
	-- (EINTR, 返回 nil 且丢掉已读内容), toggle 刚好会拉起后台 worker, 于是明明已经开始执行
	-- 却报「没有返回结果」。os.execute 内部的 waitpid 会自动重试 EINTR, 读文件也不受影响。
	local function run_capture(c)
		local tmp = os.tmpname()
		os.execute(c .. " >" .. util.shellquote(tmp) .. " 2>/dev/null")
		local f = io.open(tmp, "r")
		local out = f and f:read("*all") or ""
		if f then f:close() end
		os.remove(tmp)
		return out
	end

	local rv = { ok = false, error = "参数不合法" }
	if cmd then
		local output = run_capture(cmd)
		rv = jsonc.parse(output)
		if type(rv) ~= "table" then
			rv = { ok = false, error = "设备端工具没有返回结果" }
		end
	end

	-- 「短信转发」只放一个入口,这里只告诉前端它当前有没有启用。
	if act == "get" then
		local value = run_capture("uci -q get smsforward.settings.enable"):match("^[^%c]*")
		rv.forward = { enabled = (value == "1") }
	end

	luci.http.prepare_content("application/json")
	luci.http.write_json(rv)
end


function action_send_atcmd()
	local rv ={}
	local file
	local p = luci.http.formvalue("p")
	local set = luci.http.formvalue("set")
	--fixed = string.gsub(set, "\"", "~")
	fixed = set
	port= string.gsub(p, "\"", "~")
	rv["at"] = fixed 
	rv["port"] = port

	os.execute("/usr/share/modem/atcmd.sh \'" .. port .. "\' \'" .. fixed .. "\'")
	result = "/tmp/result.at"
	file = io.open(result, "r")
	if file ~= nil then
		rv["result"] = file:read("*all")
		file:close()
	else
		rv["result"] = " "
	end
	os.execute("/usr/share/modem/delatcmd.sh")
	luci.http.prepare_content("application/json")
	luci.http.write_json(rv)
end

function action_get_csq()
	local file = io.open("/tmp/modconf.conf", "r")
	if file then
		local content = file:read("*all")
		file:close()
		if content and string.find(content, "RM520") then
			rm520_rm500U()			
		elseif content and string.find(content, "RM500U") then
			rm520_rm500U()	
		elseif content and string.find(content, "MT5700") then	
			MT5700()
		end
	end
end

function action_get_if()
    local fs = require "nixio.fs"
    local uci = require "luci.model.uci".cursor()
    local http = require "luci.http"
    local rv = {}

    -- 获取无线 SSID
    local ssid_24g, ssid_5g

    uci:foreach("wireless", "wifi-iface", function(s)
        if s.device == "MT7981_1_1" and not ssid_24g then
            ssid_24g = s.ssid
        elseif s.device == "MT7981_1_2" and not ssid_5g then
            ssid_5g = s.ssid
        end
    end)

    rv["2.4G"] = ssid_24g or "未知"
    rv["5G"] = ssid_5g or "未知"

    -- CPU温度
    local cpu_temp_path = "/sys/class/thermal/thermal_zone0/temp"
    local temp = fs.readfile(cpu_temp_path)
    if temp then
        temp = tonumber(temp) / 1000
        rv["tmp"] = string.format("%.1f", temp)
    else
        rv["tmp"] = "未知"
    end

    -- 风扇转速
    local fanspeed = fs.readfile("/usr/bin/fanspeed.conf")
    rv["fansp"] = fanspeed and fanspeed:gsub("\n", "") or "未知"

    -- 运行时间
    local uptime = fs.readfile("/proc/uptime")
    if uptime then
        local sec = tonumber(uptime:match("^(%d+%.?%d*)"))
        if sec then
            local h = math.floor(sec / 3600)
            local m = math.floor((sec % 3600) / 60)
            local s = math.floor(sec % 60)
            rv["uptime"] = string.format("%02d:%02d:%02d", h, m, s)
        else
            rv["uptime"] = "未知"
        end
    else
        rv["uptime"] = "未知"
    end

    http.prepare_content("application/json")
    http.write_json(rv)
end


function MT5700()
	os.execute("/usr/share/modem/zinfo_mt5700.sh")
    local file, file2
    local stat = "/tmp/cpe_cell.file"
    local stat2 = "/tmp/stsss_u.file"
    file = io.open(stat, "r")
    file2 = io.open(stat2, "r")
	local rv ={}
	rv["stsss"] = file:read("*line")
	rv["modem"] = file:read("*line")
	rv["conntype"] = file:read("*line")
	rv["firmware"] = file:read("*line")
	rv["temper"] = file:read("*line")
	rv["date"] = file:read("*line")
	--------------------------------
	rv["simsel"] = file:read("*line")
	rv["cops"] = file:read("*line")
	rv["imei"] = file:read("*line")
	rv["imsi"] = file:read("*line")
	rv["iccid"] = file:read("*line")
	rv["phone"] = file:read("*line")
	--------------------------------
	rv["mode"] = file:read("*line")
	rv["per"] = file:read("*line")
	rv["rssi"] = file:read("*line")
	rv["rsrq"] = file:read("*line")
	rv["rscp"] = file:read("*line")
	rv["sinr"] = file:read("*line")
	-------------------------------
	rv["mcc"] = file:read("*line")
	rv["lac"] = file:read("*line")
	rv["cid"] = file:read("*line")
	rv["band"] = file:read("*line")
	rv["rfcn"] = file:read("*line")
	rv["pci"] = file:read("*line")
	rv["apn"] = file:read("*line")
	rv["down"] = file:read("*line")
	rv["up"] = file:read("*line")
	rv["qci"] = file:read("*line")
	rv["zbjh"] = file:read("*line")
	rv["r2cc"] = file:read("*line")
	rv["r3cc"] = file:read("*line")
	--------------------------------
	rv["cell1"] = file:read("*line")
	rv["cell2"] = file:read("*line")
	rv["cell3"] = file:read("*line")
	rv["cell4"] = file:read("*line")
	rv["cell5"] = file:read("*line")
-------------------------------
	luci.http.prepare_content("application/json")
	luci.http.write_json(rv)
end



-- 结构化小区信息。纯读缓存:采集器 /usr/bin/mwrt-cellinfo 由 cron 每分钟跑一次,
-- 这里只把它的 JSON 原样转出去,外加一个 age 字段让前端能标"数据已过期"。
--
-- 缓存不存在时(刚开机、非 5700 模组、采集器还没跑过第一轮)返回
-- {"supported":false},前端据此整段隐藏,而不是显示一堆空卡片。
function action_cellx()
	local CACHE = "/tmp/mwrt_cellinfo.json"
	local fs = require "nixio.fs"

	luci.http.prepare_content("application/json")

	-- 非 5700 模组直接短路:其他模组没有 ^HFREQINFO / ^MONNC 这些厂商命令,
	-- 这几个板块在它们身上没有意义(用户的要求就是"其他模组不需要")。
	local mod = fs.readfile("/tmp/modconf.conf") or ""
	if not mod:find("5700") then
		luci.http.write_json({ supported = false, reason = "not5700" })
		return
	end

	local raw = fs.readfile(CACHE)
	if not raw or #raw < 2 then
		-- 第一次访问时缓存可能还没生成。踢一脚采集器(后台,不等它),
		-- 这一轮先如实说"还没有数据",下一轮前端自然就拿到了。
		os.execute("(/usr/bin/mwrt-cellinfo >/dev/null 2>&1 &) &")
		luci.http.write_json({ supported = false, reason = "nocache" })
		return
	end

	local jsonc = require "luci.jsonc"
	local data = jsonc.parse(raw)
	if type(data) ~= "table" then
		luci.http.write_json({ supported = false, reason = "badcache" })
		return
	end

	data.supported = true
	local st = fs.stat(CACHE)
	if st and st.mtime then
		data.age = os.time() - st.mtime
	end
	-- 采集器只在 cron 的一分钟节拍上跑。如果缓存已经明显过期(设备刚休眠醒来、
	-- cron 被停过),顺手触发一次异步刷新,但仍然把手上这份旧数据先给出去 ——
	-- 前端有 age 可以自己决定显不显示"数据滞后"。
	if (data.age or 0) > 180 then
		os.execute("(/usr/bin/mwrt-cellinfo >/dev/null 2>&1 &) &")
	end

	luci.http.write_json(data)
end

-- 首页无线磁贴的读/写端点。
--
-- 按 band 字段('2g'/'5g')反查 wifi-device,再找挂在它底下的那个 ap 接口。
-- **不写死 MT7992_1_1 这种名字** —— 设备名由芯片型号拼出来,换一块板子就变。
-- 本文件里原有的 action_get_if 写死了 MT7981_1_1,这块 7992 的板子上它一直
-- 返回"未知",就是这个原因。
--
-- 一个 band 可能有多个 ap 接口(主 SSID + 访客网络)。取 section 名排序最小的
-- 那个,也就是 default_* 那个主接口 —— 排序让每次拿到的都是同一个,
-- 不受 uci:foreach 的遍历顺序影响。
local function wifi_find(band)
	local uci = require "luci.model.uci".cursor()
	local dev
	uci:foreach("wireless", "wifi-device", function(s)
		if not dev and s.band == band then dev = s[".name"] end
	end)
	if not dev then return nil, nil, "找不到 " .. band .. " 频段的无线设备" end

	local names = {}
	uci:foreach("wireless", "wifi-iface", function(s)
		if s.device == dev and (s.mode or "ap") == "ap" then
			names[#names + 1] = s[".name"]
		end
	end)
	if #names == 0 then return nil, nil, "该频段没有可配置的无线接口" end
	table.sort(names)
	return dev, names[1], nil
end

-- s112: 单个频段的高级参数(信道/带宽/功率/隐藏/隔离)及驱动支持的取值范围。
-- 用全局函数: 本文件 local 已经很多, 再加会逼近 Lua 5.1 的 200 个上限。
function wifi_ubus(path, phy)
	if not tostring(phy or ""):match("^[%w_%-]+$") then return nil end
	local p = io.popen("ubus call iwinfo " .. path .. " '{\"device\":\"" .. phy .. "\"}' 2>/dev/null")
	if not p then return nil end
	local raw = p:read("*a") or ""
	p:close()
	return require("luci.jsonc").parse(raw)
end

function wifi_detail(uci, dev, iface)
	local phy = uci:get("wireless", dev, "phy") or ""
	local d = {
		htmode = uci:get("wireless", dev, "htmode") or "",
		channel = uci:get("wireless", dev, "channel") or "auto",
		txpower = tonumber(uci:get("wireless", dev, "txpower")) or 100,
		hidden = uci:get("wireless", iface, "hidden") == "1",
		isolate = uci:get("wireless", iface, "isolate") == "1",
		country = uci:get("wireless", dev, "country") or "",
		htmodes = {}, channels = {}
	}
	local info = wifi_ubus("info", phy)
	if info and type(info.htmodes) == "table" then d.htmodes = info.htmodes end
	local fl = wifi_ubus("freqlist", phy)
	if fl and type(fl.results) == "table" then
		for _, f in ipairs(fl.results) do
			if f.channel and not f.restricted then d.channels[#d.channels + 1] = f.channel end
		end
	end
	return d
end

-- band=both 时返回两个频段的概况,并给出 merged:2.4G 与 5G 的 SSID、密码、加密方式是否完全相同
-- (「双频合一」状态)。密码只在服务端比较,**不回传**。
local function wifi_get_both(uci)
	local out, keys = {}, {}
	for _, b in ipairs({ "2g", "5g" }) do
		local dev, iface, err = wifi_find(b)
		if not iface then
			luci.http.write_json({ ok = false, error = err })
			return
		end
		out[b] = {
			device = dev,
			ssid = uci:get("wireless", iface, "ssid") or "",
			encryption = uci:get("wireless", iface, "encryption") or "none",
			disabled = (uci:get("wireless", dev, "disabled") == "1"
				or uci:get("wireless", iface, "disabled") == "1"),
			adv = wifi_detail(uci, dev, iface)
		}
		keys[b] = uci:get("wireless", iface, "key") or ""
	end
	local merged = out["2g"].ssid == out["5g"].ssid
		and out["2g"].encryption == out["5g"].encryption
		and keys["2g"] == keys["5g"]
	luci.http.write_json({ ok = true, both = true, merged = merged, bands = out })
end

-- 读当前无线配置。GET,只读。
-- **不回传 key。** 现有无线密码不出现在页面上;前端那个密码框留空即表示不修改。
function action_wifi_get()
	local uci = require "luci.model.uci".cursor()
	local band = luci.http.formvalue("band")

	luci.http.prepare_content("application/json")
	if band == "both" then return wifi_get_both(uci) end
	if band ~= "2g" and band ~= "5g" then
		luci.http.write_json({ ok = false, error = "频段参数不合法" })
		return
	end

	local dev, iface, err = wifi_find(band)
	if not iface then
		luci.http.write_json({ ok = false, error = err })
		return
	end

	luci.http.write_json({
		ok = true,
		band = band,
		device = dev,
		ssid = uci:get("wireless", iface, "ssid") or "",
		encryption = uci:get("wireless", iface, "encryption") or "none",
		-- 设备整体关闭 或 这个接口单独关闭,都算关闭
		disabled = (uci:get("wireless", dev, "disabled") == "1"
			or uci:get("wireless", iface, "disabled") == "1"),
		adv = wifi_detail(uci, dev, iface)
	})
end

-- s112: 高级参数的校验。取值范围一律以驱动当前报出的为准(信道表/带宽表),不信前端。
-- 返回 plan 表(要写的 uci 项)或 nil, 错误文案。缺省的项不动。
function wifi_adv_plan(uci, t)
	local fv = luci.http.formvalue
	local ch, ht, tx = fv("ch_" .. t.band), fv("ht_" .. t.band), fv("tx_" .. t.band)
	if ch == nil and ht == nil and tx == nil then return {} end
	local d = wifi_detail(uci, t.dev, t.iface)
	local nm = (t.band == "2g") and "2.4G" or "5G"
	local plan = {}
	if ht ~= nil then
		local hit = (ht == d.htmode)
		for _, m in ipairs(d.htmodes) do if m == ht then hit = true end end
		if not hit then return nil, nm .. " 的模式与带宽不受当前无线芯片支持" end
		plan.htmode = ht
	end
	if ch ~= nil then
		local hit = (ch == "auto" or ch == d.channel)
		for _, c in ipairs(d.channels) do if tostring(c) == ch then hit = true end end
		if not hit then return nil, nm .. " 的信道不在当前国家码允许的范围内" end
		plan.channel = ch
	end
	local w = tonumber(((plan.htmode or d.htmode):match("(%d+)$")))
	if t.band == "5g" and (plan.channel or d.channel) == "165" and w and w > 20 then
		return nil, nm .. " 的 165 信道只能使用 20 MHz 带宽"
	end
	if tx ~= nil then
		local n = tonumber(tx)
		if not n or n < 1 or n > 100 or n ~= math.floor(n) then
			return nil, nm .. " 的发射功率需要 1 - 100 的整数百分比"
		end
		plan.txpower = tostring(n)
	end
	return plan
end

-- 写无线配置。**必须 POST 且带 CSRF token** —— test_post_security() 两件都查,
-- 不通过它自己回 405/403 并且返回 false。
-- 改 SSID/密码是能把用户锁在网络外面的操作,不能让别的站点拿着会话 cookie
-- 用一个 <img src> 式的 GET 就触发。
function action_wifi_set()
	-- dispatcher 此刻必然已加载(它正在调度这个请求), require 走的是缓存,
	-- 但显式写出来才不依赖 package.seeall 碰巧能看到那个全局。
	-- test_post_security 内部用的 http/context 是它自己的闭包 upvalue,
	-- 跨模块调用照样拿得到。
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end

	local uci = require "luci.model.uci".cursor()
	local band = luci.http.formvalue("band")
	local ssid = luci.http.formvalue("ssid") or ""
	local enc = luci.http.formvalue("encryption") or ""
	local key = luci.http.formvalue("key") or ""

	luci.http.prepare_content("application/json")

	-- 前端也校验了一遍,但那只是为了少跑一个来回;真正的闸门在这里。
	-- both = 「双频合一」:2.4G 与 5G 写成同一组 SSID / 加密 / 密码,一次提交、一次重载
	if band ~= "2g" and band ~= "5g" and band ~= "both" then
		luci.http.write_json({ ok = false, error = "频段参数不合法" })
		return
	end
	-- SSID 按**字节**算长度:这是 802.11 的硬限制(SSID 字段 32 字节),
	-- 不是字符数 —— 中文一个字 3 字节,11 个汉字就到顶了。
	if ssid == "" or #ssid > 32 then
		luci.http.write_json({ ok = false, error = "网络名称需要 1 - 32 个字节(中文每字约 3 字节)" })
		return
	end
	-- 控制字符会把 uci 配置写坏,也不可能是用户真想要的名字
	if ssid:find("[%c]") then
		luci.http.write_json({ ok = false, error = "网络名称不能包含控制字符" })
		return
	end
	-- 白名单,不是黑名单:加密方式会被原样写进 uci 并交给 hostapd,
	-- 只放行确实支持的那几种写法。
	local ENC_OK = {
		["none"] = true, ["psk"] = true, ["psk2"] = true,
		["psk-mixed"] = true, ["sae"] = true, ["sae-mixed"] = true
	}
	if not ENC_OK[enc] then
		luci.http.write_json({ ok = false, error = "不支持的加密方式" })
		return
	end
	if enc ~= "none" and key ~= "" and (#key < 8 or #key > 63) then
		luci.http.write_json({ ok = false, error = "无线密码需要 8 - 63 个字符" })
		return
	end

	-- 先把要写的频段全部找到并校验完,再统一写:合一时不能出现"写了一半"的状态
	local targets = {}
	for _, b in ipairs(band == "both" and { "2g", "5g" } or { band }) do
		local dev, iface, err = wifi_find(b)
		if not iface then
			luci.http.write_json({ ok = false, error = err })
			return
		end
		targets[#targets + 1] = { dev = dev, iface = iface, band = b }
	end

	-- 改成加密但没给密码,而原来也没有密码 —— 这会落到一个"加密却无密码"的
	-- 配置上,hostapd 起不来,无线直接消失。挡在写之前。
	-- 合一时"留空保留原密码"只在两个频段原密码相同且非空时成立:
	-- 否则保留谁的都不对,必须让用户给一个新的。
	if enc ~= "none" and key == "" then
		local first
		for _, t in ipairs(targets) do
			local ok = uci:get("wireless", t.iface, "key") or ""
			if ok == "" or (first and ok ~= first) then
				local msg = (#targets > 1)
					and "两个频段当前的密码不同或为空, 合并为双频合一时必须设置一个新密码"
					or "该频段当前没有密码, 改为加密时必须设置一个"
				luci.http.write_json({ ok = false, error = msg })
				return
			end
			first = ok
		end
	end

	-- s112: 高级参数。先全部校验再写, 不会出现写一半。hidden/isolate 是两个频段共用的开关。
	local hid, iso = luci.http.formvalue("hidden"), luci.http.formvalue("isolate")
	for _, v in ipairs({ hid or "0", iso or "0" }) do
		if v ~= "0" and v ~= "1" then
			luci.http.write_json({ ok = false, error = "隐藏网络/客户端隔离参数不合法" })
			return
		end
	end
	for _, t in ipairs(targets) do
		local plan, perr = wifi_adv_plan(uci, t)
		if not plan then
			luci.http.write_json({ ok = false, error = perr })
			return
		end
		t.plan = plan
	end

	for _, t in ipairs(targets) do
		uci:set("wireless", t.iface, "ssid", ssid)
		uci:set("wireless", t.iface, "encryption", enc)
		if hid then uci:set("wireless", t.iface, "hidden", hid) end
		if iso then uci:set("wireless", t.iface, "isolate", iso) end
		for k, v in pairs(t.plan) do uci:set("wireless", t.dev, k, v) end
		if enc == "none" then
			-- 开放网络留着一个 key 没有意义,而且下次切回加密时会悄悄复用旧密码
			uci:delete("wireless", t.iface, "key")
		elseif key ~= "" then
			uci:set("wireless", t.iface, "key", key)
		end
		-- key == "" 且 enc ~= "none": 保留原密码不动,这就是前端"留空表示不修改"
	end

	uci:commit("wireless")
	local dev = targets[1].dev

	-- **异步重启无线。** 同步跑 `wifi reload` 的话:用户大概率正通过这个频段的
	-- WiFi 访问本页面,无线一断 HTTP 响应就发不出去,浏览器只会看到请求失败,
	-- 分不清是没保存成功还是只是断线。延后一秒再 reload,先把这个 JSON 回出去。
	os.execute("(sleep 1; /sbin/wifi reload) >/dev/null 2>&1 &")

	luci.http.write_json({ ok = true, band = band, device = dev, ssid = ssid })
end

-- ===================== 首页网口 WAN/LAN 快捷切换 =====================
--
-- 只给 C2000 MAX:它只有一个物理网口(eth1),出厂在 br-lan 里当 LAN 口;
-- wan/wan6 指着 eth0 —— 只有 MAC 没有 PHY 的空壳,永远没有载波。
-- router3d-data 按 network.wan.device 判网口角色,所以:
--   改成 WAN = 从网桥的 ports 里拿掉 + wan/wan6 的 device 改成它;
--   改回 LAN = 放回网桥 + wan/wan6 指回 eth0,wan 回到出厂的 DHCP。网桥里的 hnat 不动。
--   为什么要回 DHCP:静态方式 netifd 默认 force_link,eth0 没有载波也会被拉起来,
--   挂上一条 metric 0 的默认路由,把蜂窝的默认路由顶掉;DHCP 在 eth0 上永远拿不到地址,无害。
--   宽带账号/密码留着(DHCP 不读它们),再切回拨号不用重填。
-- 三种上网方式的写法照向导(mwrt/wizard.js 的 stageUci)。
--
-- 网关存活(Mwrt-Assurance)跟着开/关。它的守护进程拿**默认路由的出口网卡**
-- 和 primary_if 比,相同才探测主口、不通才切到备口:
--   DHCP/静态  默认路由走 eth1,主口填 eth1;
--   PPPoE      netifd 另起 pppoe-wan,默认路由走它,eth1 自己没有 IPv4 ——
--              主口填 eth1 的话守护进程永远认为"不在主口上",一次都不会切。
--              所以填拨号接口名(ppp.sh: pppname 选项,缺省 "pppoe-<接口名>")。
-- 改回 LAN 时关掉网关存活,主口复原成这个网口(出厂值)。

local PORT_WAN_IDLE = "eth0"   -- 改回 LAN 后 wan/wan6 指回的空壳口(出厂值)
local PORT_TXT_MAX = 128       -- 宽带账号/密码长度上限(字节)

-- 本机支持就返回那个唯一的物理网口名,否则 nil。
-- 机型判定和 modem_info.htm 顶部同一套:先拦 H5000M/E87N,其余 ≥4 核是 Ultra。
-- 再要求恰好一个物理口(有 phydev 的) —— 机型之外再兜一层,哪天 MAX 换了
-- 硬件版本多出一个口,这里不会还按单口去拆网桥。
local function port_pick()
	local fs = require "nixio.fs"
	local id = ((fs.readfile("/tmp/sysinfo/model") or "") .. " " ..
		(fs.readfile("/tmp/sysinfo/board_name") or "")):lower()
	if id:find("h5000m", 1, true) or id:find("e87n", 1, true) or id:find("edgepi", 1, true) then
		return nil
	end
	-- s178 C8 系列是 SoC+交换机, 口有四个(lan1-4), 另有 eth1 带 PHY; 不能按"唯一物理口"去拆网桥
	if id:match("c8%-%d") or id:find("c5800", 1, true) then return nil end
	local ncpu = 0
	local cf = io.open("/proc/cpuinfo", "r")
	if cf then
		for line in cf:lines() do
			if line:match("^processor") then ncpu = ncpu + 1 end
		end
		cf:close()
	end
	if ncpu >= 4 then return nil end
	local port
	for ifn in (fs.dir("/sys/class/net") or function() end) do
		if fs.access("/sys/class/net/" .. ifn .. "/phydev") then
			if port then return nil end
			port = ifn
		end
	end
	if port and port:match("^[%w%._-]+$") then return port end
	return nil
end

-- 网桥和 wan 的现状。ports 统一成数组(list 读出来是 table,单值写法是字符串)。
local function port_state(uci, port)
	local st = { lan_dev = uci:get("network", "lan", "device") or "br-lan", ports = {} }
	uci:foreach("network", "device", function(s)
		if not st.br and s.name == st.lan_dev and s.type == "bridge" then
			st.br = s[".name"]
			if type(s.ports) == "table" then
				for _, v in ipairs(s.ports) do st.ports[#st.ports + 1] = v end
			elseif type(s.ports) == "string" then
				for v in s.ports:gmatch("%S+") do st.ports[#st.ports + 1] = v end
			end
		end
	end)
	for _, v in ipairs(st.ports) do
		if v == port then st.in_br = true end
	end
	if st.in_br then
		st.mode = "lan"
	elseif uci:get("network", "wan", "device") == port then
		st.mode = "wan"
	else
		st.mode = "none"
	end
	return st
end

-- 浏览器是不是经这个网口接进来的:REMOTE_ADDR → ARP 表里的 MAC → 网桥转发表
-- 里学到它的那个端口。是的话一切成 WAN 本页就断,前端得提前说清楚。
-- brforward 的格式见 fancontrol.lua 的 devpop_clients(每条 16 字节)。
local function port_client_via(port, lan_dev)
	local fs = require "nixio.fs"
	local ra = (luci.http.getenv("REMOTE_ADDR") or ""):gsub("^::ffff:", "")
	local mac
	local f = io.open("/proc/net/arp", "r")
	if f then
		for line in f:lines() do
			local ip, hw, dev = line:match("^(%S+)%s+%S+%s+%S+%s+(%S+)%s+%S+%s+(%S+)")
			if ip == ra and dev == lan_dev then mac = hw:lower() break end
		end
		f:close()
	end
	if not mac then return false end
	local no = tonumber(((fs.readfile("/sys/class/net/" .. lan_dev .. "/brif/" .. port .. "/port_no") or ""):match("0x(%x+)")) or "", 16)
	if not no then return false end
	local bf = io.open("/sys/class/net/" .. lan_dev .. "/brforward", "rb")
	local data = bf and bf:read("*a") or ""
	if bf then bf:close() end
	for i = 1, #data - 15, 16 do
		local b1, b2, b3, b4, b5, b6, pno, is_local = data:byte(i, i + 7)
		if is_local == 0 and string.format("%02x:%02x:%02x:%02x:%02x:%02x", b1, b2, b3, b4, b5, b6) == mac then
			return data:byte(i + 12) * 256 + pno == no
		end
	end
	return false
end

-- IPv4 点分 → 整数,不合法返回 nil。Lua 5.1 没有位运算,网段比较用除法取整。
local function ip4n(s)
	local a, b, c, d = tostring(s or ""):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if not a then return nil end
	a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
	if a > 255 or b > 255 or c > 255 or d > 255 then return nil end
	return ((a * 256 + b) * 256 + c) * 256 + d
end
-- 子网掩码 → 前缀长度;不是连续的 1 返回 nil
local function mask_bits(s)
	local n = ip4n(s)
	if not n then return nil end
	for b = 0, 32 do
		if n == 2 ^ 32 - 2 ^ (32 - b) then return b end
	end
	return nil
end
local function same_net(x, y, bits)
	local k = 2 ^ (32 - bits)
	return math.floor(x / k) == math.floor(y / k)
end
-- LAN 的地址和前缀。ipaddr 可能是 "a.b.c.d/24" 写法,也可能配 netmask。
local function lan_net(uci)
	local ip = uci:get("network", "lan", "ipaddr")
	if type(ip) == "table" then ip = ip[1] end
	ip = tostring(ip or "")
	local a, bits = ip:match("^([%d%.]+)/(%d+)$")
	if a then return a, ip4n(a), tonumber(bits) end
	return ip, ip4n(ip), mask_bits(uci:get("network", "lan", "netmask") or "255.255.255.0")
end
local function port_list(v)
	if type(v) == "table" then return table.concat(v, " ") end
	return v or ""
end

-- 上网方式(DHCP / PPPoE / 静态)的参数校验。port_set(单网口 MAX)和 usbnic_set(USB 网卡当 WAN)共用,
-- 两边的字段名、规则、中文提示必须一致。
--   fv(k)      取去掉首尾空白的表单值
--   keep_pass  已经存过宽带密码(此时密码留空 = 不修改)
-- 成功返回 { proto, username, password, ipaddr, netmask, gateway, dns = {...} },失败返回 nil, 中文原因。
local function port_wan_args(uci, fv, keep_pass)
	local a = {
		proto = fv("proto"), username = fv("username"), password = luci.http.formvalue("password") or "",
		ipaddr = fv("ipaddr"), netmask = fv("netmask"), gateway = fv("gateway"), dns = {},
	}
	if a.proto ~= "dhcp" and a.proto ~= "pppoe" and a.proto ~= "static" then
		return nil, "上网方式参数不正确"
	end
	if a.proto == "pppoe" then
		if a.username == "" then return nil, "请填写宽带账号。" end
		if #a.username > PORT_TXT_MAX or a.username:find("%c") then
			return nil, "宽带账号太长或含有不可见字符。"
		end
		if a.password ~= "" and (#a.password > PORT_TXT_MAX or a.password:find("%c")) then
			return nil, "宽带密码太长或含有不可见字符。"
		end
		if a.password == "" and not keep_pass then
			return nil, "请填写宽带密码。"
		end
	elseif a.proto == "static" then
		local ipn = ip4n(a.ipaddr)
		local o1 = ipn and math.floor(ipn / 16777216)
		if not ipn or o1 == 0 or o1 == 127 or o1 >= 224 then return nil, "请填写正确的 IP 地址。" end
		local bits = mask_bits(a.netmask)
		if not bits or bits < 1 then return nil, "请填写正确的子网掩码。" end
		if bits <= 30 then
			local k = 2 ^ (32 - bits)
			if ipn % k == 0 or ipn % k == k - 1 then
				return nil, "这个 IP 是网段的网络地址或广播地址，不能给本机用。"
			end
		end
		if a.gateway ~= "" then
			local gwn = ip4n(a.gateway)
			if not gwn then return nil, "请填写正确的网关地址。" end
			if gwn == ipn then return nil, "网关不能和本机 IP 相同。" end
			if bits <= 30 and not same_net(ipn, gwn, bits) then
				return nil, "网关不在这个 IP 的网段里，请核对 IP 地址、子网掩码和网关。"
			end
		end
		local lan_ip, ln, lb = lan_net(uci)
		if ln and lb and same_net(ipn, ln, math.min(bits, lb)) then
			return nil, "这个 IP 和局域网（" .. lan_ip .. "）在同一网段，会冲突，请换一个网段。"
		end
		for v in fv("dns"):gmatch("[^%s,，]+") do
			if not ip4n(v) then return nil, "DNS 服务器地址不正确：" .. v end
			a.dns[#a.dns + 1] = v
		end
	end
	return a
end

-- 网口对端识别:网口当 LAN 用时,插上来的是上级路由器/光猫(多半该改成 WAN),
-- 还是电脑这类终端。真正去测的是 /usr/bin/mwrt-portprobe(python3,在这个口上
-- 直接发 DHCP/PPPoE 发现包,约 2 秒),这里只按需在后台拉起它、读它写的结果。
-- 结果跟着网口的 carrier_up_count 走:拔插一次换一个号,重新识别。同一次插着的期间,
-- 没认出来的隔 PROBE_GAP 秒补测、最多 PROBE_TRIES 次(对端可能刚上电还没起 DHCP),
-- 认出来的不再测。
-- 「忽略」只管这一次插着:/tmp 里记"网口名 carrier_up_count",拔插一次号就变,
-- 下次插上照常检测、是路由器照样弹。从 WAN 改回 LAN 也算忽略这一次 —— 用户是看着
-- 它插着才选的 LAN;可网络重载会让网口掉一下线、号跟着变,所以先记成"网口名 set 时间",
-- 等重载完由 port_set 的后台尾巴钉到那时的号上(没钉上的 PROBE_SETTLE 秒后作废)。
local PROBE_BIN = "/usr/bin/mwrt-portprobe"
local PROBE_OUT = "/tmp/mwrt-portprobe.json"
local PROBE_IGN = "/tmp/mwrt-portprobe.ign"
local PROBE_TRIES, PROBE_GAP, PROBE_STALE = 4, 20, 15   -- 次数;补测间隔、"测了一半没了"判定(秒)
local PROBE_SETTLE = 60

local function probe_read()
	local s = (require "nixio.fs").readfile(PROBE_OUT)
	local r = s and require("luci.jsonc").parse(s)
	return type(r) == "table" and r or nil
end
local function probe_ignored(port, cnt)
	local p, v, t = ((require "nixio.fs").readfile(PROBE_IGN) or ""):match("^(%S+) (%S+) ?(%d*)")
	if p ~= port then return false end
	if v == "set" then return os.time() - (tonumber(t) or 0) < PROBE_SETTLE end
	return cnt ~= nil and tonumber(v) == cnt
end

-- 读现状。GET,只读。**不回传宽带密码**,只告诉前端有没有存过(留空 = 不修改)。
function action_port_get()
	luci.http.prepare_content("application/json")
	local port = port_pick()
	if not port then
		luci.http.write_json({ ok = false, error = "本机型不支持网口切换" })
		return
	end
	local uci = require "luci.model.uci".cursor()
	local st = port_state(uci, port)
	local function w(k) return uci:get("network", "wan", k) end
	local ipaddr, netmask = w("ipaddr"), w("netmask") or ""
	if type(ipaddr) == "table" then ipaddr = ipaddr[1] end
	ipaddr = tostring(ipaddr or "")
	local a, bits = ipaddr:match("^([%d%.]+)/(%d+)$")
	if a then
		ipaddr = a
		local n = 2 ^ 32 - 2 ^ (32 - tonumber(bits))
		netmask = string.format("%d.%d.%d.%d", math.floor(n / 16777216) % 256,
			math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
	end
	local lan_ip = lan_net(uci)
	local fs = require "nixio.fs"
	luci.http.write_json({
		ok = true,
		port = port,
		mode = st.mode,
		carrier = eth_carrier(port),
		via = st.in_br and port_client_via(port, st.lan_dev) or false,
		proto = w("proto") or "dhcp",
		username = w("username") or "",
		has_pass = (w("password") or "") ~= "",
		ipaddr = ipaddr,
		netmask = netmask,
		gateway = w("gateway") or "",
		dns = port_list(w("dns")),
		lan_ip = lan_ip,
		failover = uci:get("Mwrt-Assurance", "wan_failover", "enabled") == "1",
		fo_ok = uci:get("Mwrt-Assurance", "wan_failover") ~= nil,
	})
end

-- 全局 mwrt-portsw.js 轮询的对端识别。GET,不改配置;该测的时候在后台拉起探测脚本,这一次先回 probing。
-- 只回前端要显示的:不回对端 MAC(忽略接口自己从结果文件里取)。
function action_port_probe()
	luci.http.prepare_content("application/json")
	local port = port_pick()
	if not port then
		luci.http.write_json({ ok = false, error = "本机型不支持网口切换" })
		return
	end
	local fs = require "nixio.fs"
	local uci = require "luci.model.uci".cursor()
	local st = port_state(uci, port)
	local sys = "/sys/class/net/" .. port .. "/"
	local res = { ok = true, port = port, mode = st.mode, state = "off",
		carrier = eth_carrier(port) }
	if st.mode ~= "lan" or not res.carrier or not fs.access(PROBE_BIN, "x") then
		luci.http.write_json(res)
		return
	end
	local cnt = tonumber((fs.readfile(sys .. "carrier_up_count") or ""):match("%d+"))
	local r = probe_read()
	if r and not (r["if"] == port and r.cnt == cnt) then r = nil end
	local age = r and os.time() - (tonumber(r.t) or 0) or 0
	local run
	if not r then
		run = true
	elseif r.state == "probing" then
		run = age >= PROBE_STALE
	elseif r.state ~= "router" then
		run = (tonumber(r.tries) or 1) < PROBE_TRIES and age >= PROBE_GAP
	end
	if run then os.execute(PROBE_BIN .. " " .. port .. " >/dev/null 2>&1 &") end
	res.state = r and r.state or "probing"
	if res.state == "router" then
		local ipn, bits = ip4n(r.ip), mask_bits(r.mask or "")
		local lan_ip, ln, lb = lan_net(uci)
		res.kind = r.kind
		res.gw = r.gw or ""
		res.ac = r.ac or ""
		res.lan_ip = lan_ip
		res.conflict = (ipn and bits and ln and lb and same_net(ipn, ln, math.min(bits, lb))) and true or false
		res.ignored = probe_ignored(port, cnt)
	end
	luci.http.write_json(res)
end

-- 接入检测提示框的「忽略」。POST + token。钉的是提示框依据的那份结果的号:
-- 用户点之前已经拔插过的话,号对不上、等于没忽略,新插的这次照样弹。
function action_port_probe_ignore()
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end
	luci.http.prepare_content("application/json")
	local port = port_pick()
	if not port then
		luci.http.write_json({ ok = false, error = "本机型不支持网口切换" })
		return
	end
	local r = probe_read()
	local cnt = r and r["if"] == port and r.state == "router" and tonumber(r.cnt)
	if cnt then (require "nixio.fs").writefile(PROBE_IGN, port .. " " .. cnt .. "\n") end
	luci.http.write_json({ ok = true })
end

-- 写。**必须 POST 且带 CSRF token**(同 wifi_set)。
-- 前端已经校验过一遍,那只是为了少跑一个来回;真正的闸门在这里。
function action_port_set()
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end
	luci.http.prepare_content("application/json")
	local function fail(msg) luci.http.write_json({ ok = false, error = msg }) end

	local port = port_pick()
	if not port then return fail("本机型不支持网口切换") end
	local uci = require "luci.model.uci".cursor()
	local st = port_state(uci, port)
	if not st.br then return fail("没有找到局域网网桥的配置，无法切换") end

	local function fv(k) return ((luci.http.formvalue(k) or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
	local mode, proto = fv("mode"), fv("proto")
	if mode ~= "lan" and mode ~= "wan" then return fail("网口模式参数不正确") end
	-- 已经是 LAN 再选 LAN:什么都不用动,也不去重载网络
	if mode == "lan" and st.mode == "lan" then
		luci.http.write_json({ ok = true, changed = false, mode = "lan" })
		return
	end

	local is_wan = mode == "wan"
	local username, password, ipaddr, netmask, gateway, dns = "", "", "", "", "", {}
	if is_wan then
		local a, err = port_wan_args(uci, fv, (uci:get("network", "wan", "password") or "") ~= "")
		if not a then return fail(err) end
		proto, username, password = a.proto, a.username, a.password
		ipaddr, netmask, gateway, dns = a.ipaddr, a.netmask, a.gateway, a.dns
	end

	local via = st.in_br and port_client_via(port, st.lan_dev) or false

	-- 网桥成员:拿掉/放回这个口,其余(hnat)原样;放回时排在最前,和出厂顺序一致。
	-- 万一拿完一个不剩,标 bridge_empty,免得 br-lan 起不来把无线也带掉。
	local np = {}
	for _, v in ipairs(st.ports) do
		if v ~= port then np[#np + 1] = v end
	end
	if not is_wan then table.insert(np, 1, port) end
	if #np > 0 then
		uci:set("network", st.br, "ports", np)
	else
		uci:delete("network", st.br, "ports")
		uci:set("network", st.br, "bridge_empty", "1")
	end

	local fo_ok = uci:get("Mwrt-Assurance", "wan_failover") ~= nil
	local pif = port
	if is_wan then
		uci:set("network", "wan", "device", port)
		if uci:get("network", "wan6") then uci:set("network", "wan6", "device", port) end
		uci:delete("network", "wan", "disabled")
		if proto == "dhcp" then
			uci:set("network", "wan", "proto", "dhcp")
			for _, k in ipairs({ "username", "password", "ipaddr", "netmask", "gateway", "dns" }) do
				uci:delete("network", "wan", k)
			end
		elseif proto == "pppoe" then
			uci:set("network", "wan", "proto", "pppoe")
			uci:set("network", "wan", "username", username)
			if password ~= "" then uci:set("network", "wan", "password", password) end
			for _, k in ipairs({ "ipaddr", "netmask", "gateway" }) do
				uci:delete("network", "wan", k)
			end
			pif = uci:get("network", "wan", "pppname") or "pppoe-wan"
		else
			uci:set("network", "wan", "proto", "static")
			uci:set("network", "wan", "ipaddr", ipaddr)
			uci:set("network", "wan", "netmask", netmask)
			if gateway ~= "" then
				uci:set("network", "wan", "gateway", gateway)
			else
				uci:delete("network", "wan", "gateway")
			end
			if #dns > 0 then
				uci:set("network", "wan", "dns", dns)
			else
				uci:delete("network", "wan", "dns")
			end
			for _, k in ipairs({ "username", "password" }) do
				uci:delete("network", "wan", k)
			end
		end
	else
		for _, s in ipairs({ "wan", "wan6" }) do
			if uci:get("network", s, "device") == port then
				uci:set("network", s, "device", PORT_WAN_IDLE)
			end
		end
		uci:set("network", "wan", "proto", "dhcp")
		for _, k in ipairs({ "ipaddr", "netmask", "gateway", "dns" }) do
			uci:delete("network", "wan", k)
		end
	end
	if fo_ok then
		uci:set("Mwrt-Assurance", "wan_failover", "enabled", is_wan and "1" or "0")
		uci:set("Mwrt-Assurance", "wan_failover", "primary_if", pif)
	end

	local ok, err = uci:commit("network")
	if not ok then
		uci:revert("network")
		if fo_ok then uci:revert("Mwrt-Assurance") end
		return fail("保存网络配置失败：" .. tostring(err or "未知错误"))
	end
	if fo_ok then uci:commit("Mwrt-Assurance") end
	if not is_wan then (require "nixio.fs").writefile(PROBE_IGN, port .. " set " .. os.time() .. "\n") end

	-- **异步重载。** 理由同 wifi_set:浏览器要是正经这个口连着,网络一动响应就发不出去。
	-- 提交本身已经会让 procd 约 1 秒后重载 network(reload_trigger),这里再显式来一次兜底,
	-- 配置没变时是空操作。防火墙随后补一次,让 eth1 进出 wan 区域立即生效。
	-- 改回 LAN 时顺手清掉还挂在这个口上的默认路由(网关存活切换时装的那种不归 netifd 管),
	-- 再等网口重新起来,把上面的"忽略这一次"钉到那时的拔插计数上。
	local tail = is_wan and "" or
		("; for i in 1 2 3 4; do ip route del default dev " .. port .. " 2>/dev/null || break; done" ..
		"; sleep 8; c=$(cat /sys/class/net/" .. port .. "/carrier_up_count 2>/dev/null)" ..
		"; grep -q '^" .. port .. " set ' " .. PROBE_IGN .. " && [ -n \"$c\" ] && echo \"" .. port .. " $c\" > " .. PROBE_IGN)
	os.execute("(sleep 2; /etc/init.d/network reload; sleep 6; /etc/init.d/firewall reload" ..
		tail .. ") >/dev/null 2>&1 &")

	luci.http.write_json({
		ok = true, changed = true, mode = mode,
		proto = is_wan and proto or nil,
		failover = fo_ok and is_wan or false,
		primary = fo_ok and pif or nil,
		via = via,
		lan_ip = (lan_net(uci)),
	})
end

-- ===================== 首页网口卡片的 WAN / LAN 设置 =====================
--
-- 与 port_get/port_set 的区别: 那一对只给单网口的 MAX 用,而且连带切 WAN/LAN、改网桥;
-- 这里的 wan_*/lan_* 只改参数,不动网桥和接口归属,所有带 WAN 口 / LAN 口的机型都能用。
-- 校验规则复用 port_wan_args,和 port_set、usbnic_set 的提示完全一致。
-- 用全局函数而不是 local:文件顶层 local 已经很多,Lua 5.1 每个函数最多 200 个。

-- 掩码 "255.255.255.0" / 前缀写法统一成 (ip, 点分掩码)
function ip_and_mask(ip, mask)
	if type(ip) == "table" then ip = ip[1] end
	ip = tostring(ip or "")
	local a, bits = ip:match("^([%d%.]+)/(%d+)$")
	if a then
		local n = 2 ^ 32 - 2 ^ (32 - tonumber(bits))
		return a, string.format("%d.%d.%d.%d", math.floor(n / 16777216) % 256,
			math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
	end
	return ip, tostring(mask or "")
end

-- 读 WAN 的参数。GET,只读;**不回传宽带密码**,只告诉有没有存过(留空 = 不修改)。
function action_wan_get()
	luci.http.prepare_content("application/json")
	local uci = require "luci.model.uci".cursor()
	if uci:get("network", "wan") == nil then
		luci.http.write_json({ ok = false, error = "本机没有 WAN 口的配置" })
		return
	end
	local function w(k) return uci:get("network", "wan", k) end
	local ip, mask = ip_and_mask(w("ipaddr"), w("netmask"))
	luci.http.write_json({
		ok = true,
		device = w("device") or "",
		proto = w("proto") or "dhcp",
		username = w("username") or "",
		has_pass = (w("password") or "") ~= "",
		ipaddr = ip, netmask = mask,
		gateway = w("gateway") or "",
		dns = port_list(w("dns")),
		lan_ip = (lan_net(uci)),
		failover = uci:get("Mwrt-Assurance", "wan_failover", "enabled") == "1",
	})
end

-- 写 WAN 的上网方式(DHCP / 宽带拨号 / 静态 IP)。POST + CSRF。
-- 只改 network.wan 的协议参数,不动网口归属;宽带密码留空 = 不修改。
-- 提交后异步重载网络(设置页的连接可能因此中断,所以响应先发出去)。
function action_wan_set()
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end
	luci.http.prepare_content("application/json")
	local function fail(msg) luci.http.write_json({ ok = false, error = msg }) end
	local uci = require "luci.model.uci".cursor()
	if uci:get("network", "wan") == nil then return fail("本机没有 WAN 口的配置") end
	local function fv(k) return ((luci.http.formvalue(k) or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
	local a, err = port_wan_args(uci, fv, (uci:get("network", "wan", "password") or "") ~= "")
	if not a then return fail(err) end

	uci:delete("network", "wan", "disabled")
	uci:set("network", "wan", "proto", a.proto)
	local drop = { dhcp = { "username", "password", "ipaddr", "netmask", "gateway", "dns" },
		pppoe = { "ipaddr", "netmask", "gateway", "dns" }, static = { "username", "password" } }
	for _, k in ipairs(drop[a.proto]) do uci:delete("network", "wan", k) end
	if a.proto == "pppoe" then
		uci:set("network", "wan", "username", a.username)
		if a.password ~= "" then uci:set("network", "wan", "password", a.password) end
	elseif a.proto == "static" then
		uci:set("network", "wan", "ipaddr", a.ipaddr)
		uci:set("network", "wan", "netmask", a.netmask)
		if a.gateway ~= "" then uci:set("network", "wan", "gateway", a.gateway) else uci:delete("network", "wan", "gateway") end
		if #a.dns > 0 then uci:set("network", "wan", "dns", a.dns) else uci:delete("network", "wan", "dns") end
	end
	-- 网关存活已开启时,主出口名要跟着上网方式走(拨号用 pppoe-wan,其余用物理口)
	local fo = uci:get("Mwrt-Assurance", "wan_failover", "enabled") == "1"
	if fo then
		local dev = uci:get("network", "wan", "device") or ""
		local pif = a.proto == "pppoe" and (uci:get("network", "wan", "pppname") or "pppoe-wan") or dev
		if pif ~= "" then uci:set("Mwrt-Assurance", "wan_failover", "primary_if", pif) end
	end
	local ok, e2 = uci:commit("network")
	if not ok then
		uci:revert("network")
		return fail("保存网络配置失败：" .. tostring(e2 or "未知错误"))
	end
	if fo then uci:commit("Mwrt-Assurance") end
	os.execute("(sleep 2; /etc/init.d/network reload; sleep 6; /etc/init.d/firewall reload) >/dev/null 2>&1 &")
	luci.http.write_json({ ok = true, proto = a.proto, failover = fo })
end

-- ===================== s178/s179 多网口各自设 WAN / LAN(C8 四口 + 双网口机型) =====================
--
-- 668/688/5800: SoC 的 gmac0 经 2.5G 内连接 MT7531 交换机, 四个用户口是 DSA 口 lan1..lan4,
-- 第四个(lan4)是 2.5G 口, 出厂当宽带 WAN。系统只有一个 wan 接口, 所以同一时刻最多一个口是 WAN,
-- 其余都在 br-lan 里。用户可以把任意一个口设成 WAN(原来的 WAN 口自动回 LAN), 也可以四口全 LAN(不接宽带)。
-- wan.device = 那个口; 全 LAN 时 wan/wan6 整段删除, 设回 WAN 时重建(dhcp/dhcpv6)。
-- 网关存活(Mwrt-Assurance)跟着: 有 WAN 口就开, 主口 = 该口(PPPoE 则 pppoe-wan); 全 LAN 就关。
-- 备口(蜂窝等)仍由用户在网关存活页自己定, 这里不碰。
C8_PORTS = { "lan1", "lan2", "lan3", "lan4" }

-- s191 网口"真实有线": MT7981 内置千兆 PHY 的驱动(patches-6.6/9999-01-hnat.patch)在没检测到对端时强制 link=1,
-- 没插线内核 carrier 也恒为 1。与 router3d-data 同判据: 这类口再看 ethtool 的对端通告模式
-- (Link partner advertised link modes 只有真有对端才有值)。其它 PHY / DSA 口直接信内核。
function eth_carrier(name)
	local fs = require "nixio.fs"
	local base = "/sys/class/net/" .. name
	if (fs.readfile(base .. "/carrier") or ""):match("^1") == nil then return false end
	local drv = fs.readlink(base .. "/phydev/driver") or ""
	if drv:find("MT7981 PHY", 1, true) and name:match("^[%w_%-]+$") and fs.access("/usr/sbin/ethtool", "x") then
		local p = io.popen("/usr/sbin/ethtool " .. name .. " 2>/dev/null")
		local out = p and p:read("*a") or ""
		if p then p:close() end
		return out:match("Link partner advertised link modes:%s*%d") ~= nil
	end
	return true
end

-- 本机能设的口: C8 = 交换机 DSA 口 lan1..lan4; 其余机型(TR3000 等) = 设备树 GMAC 且绑了 PHY 的 ethN
-- (与 router3d-data 同判据), 至少两个才算。没有返回 nil。
function c8_scan()
	local fs = require "nixio.fs"
	local id = ((fs.readfile("/tmp/sysinfo/model") or "") .. " " ..
		(fs.readfile("/tmp/sysinfo/board_name") or "")):lower()
	if id:match("c8%-%d") or id:find("c5800", 1, true) then return { "lan1", "lan2", "lan3", "lan4" } end
	local names = {}
	for n in (fs.dir("/sys/class/net") or function() end) do
		if n:match("^eth%d+$") then
			local base = "/sys/class/net/" .. n
			if (fs.readfile(base .. "/uevent") or ""):find("OF_NAME=mac", 1, true) and fs.access(base .. "/phydev") then
				names[#names + 1] = n
			end
		end
	end
	table.sort(names)
	if #names >= 2 then return names end
	return nil
end

-- 每个请求先调一次: 刷新 C8_PORTS, 返回本机是否支持
function c8_ok()
	C8_PORTS = c8_scan()
	return C8_PORTS ~= nil
end

function c8_wan_port(uci)
	if uci:get("network", "wan", "disabled") == "1" then return nil end
	local d = uci:get("network", "wan", "device")
	for _, n in ipairs(C8_PORTS) do
		if d == n then return n end
	end
	return nil
end

-- 读现状。GET,只读;不回传宽带密码。
function action_c8port_get()
	luci.http.prepare_content("application/json")
	if not c8_ok() then
		luci.http.write_json({ ok = false, error = "本机型不支持网口设置" })
		return
	end
	local fs = require "nixio.fs"
	local uci = require "luci.model.uci".cursor()
	local st = port_state(uci, C8_PORTS[1])
	local wp = c8_wan_port(uci)
	local ports = {}
	for _, n in ipairs(C8_PORTS) do
		local sys = "/sys/class/net/" .. n .. "/"
		local role = (wp == n) and "wan" or "lan"
		ports[#ports + 1] = {
			id = n, role = role,
			carrier = eth_carrier(n),
			speed = tonumber((fs.readfile(sys .. "speed") or ""):match("%-?%d+")) or -1,
			via = role == "lan" and port_client_via(n, st.lan_dev) or false,
		}
	end
	local function w(k) return uci:get("network", "wan", k) end
	local ip, mask = ip_and_mask(w("ipaddr"), w("netmask"))
	luci.http.write_json({
		ok = true, ports = ports, wan = wp or "none",
		proto = w("proto") or "dhcp",
		username = w("username") or "",
		has_pass = (w("password") or "") ~= "",
		ipaddr = ip, netmask = mask,
		gateway = w("gateway") or "",
		dns = port_list(w("dns")),
		lan_ip = (lan_net(uci)),
		failover = uci:get("Mwrt-Assurance", "wan_failover", "enabled") == "1",
	})
end

-- 写。POST + CSRF。参数 wan = lan1..lan4 | none; wan 不是 none 时同时带上网方式(同 wan_set)。
function action_c8port_set()
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end
	luci.http.prepare_content("application/json")
	local function fail(msg) luci.http.write_json({ ok = false, error = msg }) end
	if not c8_ok() then return fail("本机型不支持网口设置") end
	local uci = require "luci.model.uci".cursor()
	local st = port_state(uci, C8_PORTS[1])
	if not st.br then return fail("没有找到局域网网桥的配置，无法切换") end
	local function fv(k) return ((luci.http.formvalue(k) or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

	local want = fv("wan")
	local valid = want == "none"
	for _, n in ipairs(C8_PORTS) do
		if n == want then valid = true end
	end
	if not valid then return fail("网口参数不正确") end
	local is_wan = want ~= "none"
	local old = c8_wan_port(uci)

	local a
	if is_wan then
		local err
		a, err = port_wan_args(uci, fv, (uci:get("network", "wan", "password") or "") ~= "")
		if not a then return fail(err) end
	end
	-- 浏览器经哪个口接进来: 它要被切成 WAN, 一切换本页就断
	local via = false
	if is_wan and want ~= old and port_client_via(want, st.lan_dev) then via = true end

	-- 网桥成员: 四个口里除了 WAN 的都放回, 排在最前(出厂顺序); 其余成员(非 lanN)原样
	local np = {}
	for _, n in ipairs(C8_PORTS) do
		if n ~= want then np[#np + 1] = n end
	end
	for _, v in ipairs(st.ports) do
		local isc8 = false
		for _, n in ipairs(C8_PORTS) do
			if n == v then isc8 = true end
		end
		if not isc8 then np[#np + 1] = v end
	end
	uci:set("network", st.br, "ports", np)

	local fo_ok = uci:get("Mwrt-Assurance", "wan_failover") ~= nil
	local pif = want
	if is_wan then
		-- 全 LAN 时 wan/wan6 是整段删掉的, 这里按需重建; 旧版留下的 disabled 一并清掉
		if not uci:get("network", "wan") then uci:section("network", "interface", "wan", { proto = a.proto }) end
		if not uci:get("network", "wan6") then uci:section("network", "interface", "wan6", { proto = "dhcpv6" }) end
		for _, s in ipairs({ "wan", "wan6" }) do
			uci:set("network", s, "device", want)
			uci:delete("network", s, "disabled")
		end
		uci:set("network", "wan", "proto", a.proto)
		local drop = { dhcp = { "username", "password", "ipaddr", "netmask", "gateway", "dns" },
			pppoe = { "ipaddr", "netmask", "gateway", "dns" }, static = { "username", "password" } }
		for _, k in ipairs(drop[a.proto]) do uci:delete("network", "wan", k) end
		if a.proto == "pppoe" then
			uci:set("network", "wan", "username", a.username)
			if a.password ~= "" then uci:set("network", "wan", "password", a.password) end
			pif = uci:get("network", "wan", "pppname") or "pppoe-wan"
		elseif a.proto == "static" then
			uci:set("network", "wan", "ipaddr", a.ipaddr)
			uci:set("network", "wan", "netmask", a.netmask)
			if a.gateway ~= "" then uci:set("network", "wan", "gateway", a.gateway) else uci:delete("network", "wan", "gateway") end
			if #a.dns > 0 then uci:set("network", "wan", "dns", a.dns) else uci:delete("network", "wan", "dns") end
		end
	else
		-- 四口全 LAN: 直接删掉 wan / wan6 接口(网络页不再出现), 设回 WAN 时重建
		for _, s in ipairs({ "wan", "wan6" }) do
			if uci:get("network", s) then uci:delete("network", s) end
		end
	end
	if fo_ok then
		uci:set("Mwrt-Assurance", "wan_failover", "enabled", is_wan and "1" or "0")
		if is_wan then uci:set("Mwrt-Assurance", "wan_failover", "primary_if", pif) end
	end

	local ok, err = uci:commit("network")
	if not ok then
		uci:revert("network")
		if fo_ok then uci:revert("Mwrt-Assurance") end
		return fail("保存网络配置失败：" .. tostring(err or "未知错误"))
	end
	if fo_ok then uci:commit("Mwrt-Assurance") end
	-- C5800: 用户自己改了网口, mwrt-ak68 自动识别切 WAN 前存的原设置作废, 不再自动还原
	os.execute("rm -rf /etc/mwrt-ak68.prev")

	-- 异步重载(理由同 port_set)。原来的 WAN 口回 LAN 后, 清掉还挂在它上面的默认路由(网关存活装的那种不归 netifd 管)
	local tail = ""
	if old and old ~= want then
		tail = "; for i in 1 2 3 4; do ip route del default dev " .. old .. " 2>/dev/null || break; done"
	end
	os.execute("(sleep 2; /etc/init.d/network reload; sleep 6; /etc/init.d/firewall reload" ..
		tail .. ") >/dev/null 2>&1 &")

	luci.http.write_json({
		ok = true, wan = want, proto = is_wan and a.proto or nil,
		failover = fo_ok and is_wan or false, primary = fo_ok and is_wan and pif or nil,
		via = via, lan_ip = (lan_net(uci)),
	})
end

-- ===================== s181 出口信息浮窗: 点开才检测, 不在后台跑流量 =====================
-- 目标写死在表里(不接收前端传来的网址, 免得被当跳板); 每次请求只测一个目标, 前端并发发起。
EGP_T = {
	ali = "https://www.aliyun.com",
	bd  = "https://www.baidu.com",
	qq  = "https://www.qq.com",
	yt  = "https://www.youtube.com",
	gg  = "https://www.google.com",
	cf  = "https://1.1.1.1",
}
EGP_ISP = { "电信", "联通", "移动", "广电", "教育网", "铁通" }

function egp_ms(s)
	return math.floor((tonumber(s) or 0) * 1000 + 0.5)
end

function action_egress_probe()
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end
	luci.http.prepare_content("application/json")
	local t = luci.http.formvalue("t") or ""
	if t == "ip" then
		-- 公网地址 + 归属 + 运营商(国内站点, 一次很小的请求)
		local s = luci.sys.exec("curl -s --connect-timeout 3 -m 5 https://myip.ipip.net 2>/dev/null") or ""
		local ip = s:match("IP：%s*([%x%.:]+)")
		if not ip then
			luci.http.write_json({ ok = false })
			return
		end
		local loc = (s:match("来自于：%s*(.-)%s*$") or ""):gsub("%s+", " ")
		local isp = ""
		for _, k in ipairs(EGP_ISP) do
			if loc:find(k, 1, true) then isp = k end
		end
		luci.http.write_json({ ok = true, ip = ip, place = (loc:gsub("^中国 ", "")), isp = isp })
		return
	end
	local url = EGP_T[t]
	if not url then
		luci.http.write_json({ ok = false, error = "未知检测目标" })
		return
	end
	local out = luci.sys.exec('curl -sS -I -o /dev/null --connect-timeout 3 -m 6 -w "%{http_code} %{time_namelookup} %{time_connect} %{time_appconnect} %{time_starttransfer} %{time_total}" ' ..
		url .. ' 2>/dev/null; echo " $?"') or ""
	local code, dns, tcp, tls, ttfb, tot, rc = out:match("^(%d+) ([%d%.]+) ([%d%.]+) ([%d%.]+) ([%d%.]+) ([%d%.]+) (%d+)")
	if not code then
		luci.http.write_json({ ok = false, rc = -1 })
		return
	end
	rc = tonumber(rc) or 0
	luci.http.write_json({
		ok = (rc == 0 and code ~= "000"), rc = rc, code = tonumber(code),
		dns = egp_ms(dns), tcp = math.max(0, egp_ms(tcp) - egp_ms(dns)),
		tls = (tonumber(tls) or 0) > 0 and math.max(0, egp_ms(tls) - egp_ms(tcp)) or 0,
		ttfb = egp_ms(ttfb), total = egp_ms(tot)
	})
end

-- LAN 现在的上游地址(WAN 当前实际拿到的 IPv4,拨号 / DHCP / 静态都算),用来挡「LAN 和 WAN 同网段」。
-- 取不到(没联网)返回 nil, nil。
function wanlan_up_net()
	local j = require("luci.jsonc").parse(luci.sys.exec("ubus call network.interface.wan status 2>/dev/null") or "")
	local a = type(j) == "table" and type(j["ipv4-address"]) == "table" and j["ipv4-address"][1]
	if type(a) ~= "table" or not a.address then return nil, nil end
	return a.address, tonumber(a.mask)
end

-- LAN 参数校验。成功返回 { ipaddr, netmask, bits, dhcp, start, limit, leasetime },失败返回 nil, 中文原因。
LAN_LEASES = { ["30m"] = 1, ["1h"] = 1, ["2h"] = 1, ["6h"] = 1, ["12h"] = 1, ["24h"] = 1, ["3d"] = 1, ["7d"] = 1 }
function wanlan_lan_args(uci, fv)
	local a = { ipaddr = fv("ipaddr"), netmask = fv("netmask"), dhcp = fv("dhcp") == "1" }
	local ipn = ip4n(a.ipaddr)
	if not ipn then return nil, "请填写正确的 LAN IP 地址。" end
	local o1, o2 = math.floor(ipn / 16777216), math.floor(ipn / 65536) % 256
	if not (o1 == 10 or (o1 == 172 and o2 >= 16 and o2 <= 31) or (o1 == 192 and o2 == 168)) then
		return nil, "局域网地址请用私有网段：10.x.x.x、172.16~31.x.x 或 192.168.x.x。"
	end
	local bits = mask_bits(a.netmask)
	if not bits or bits < 16 or bits > 30 then return nil, "子网掩码不正确，请用 255.255.0.0 到 255.255.255.252 之间的掩码。" end
	local k = 2 ^ (32 - bits)
	if ipn % k == 0 or ipn % k == k - 1 then return nil, "这个 IP 是网段的网络地址或广播地址，不能给路由器用。" end
	a.bits = bits
	local up_ip, up_bits = wanlan_up_net()
	local upn = up_ip and ip4n(up_ip)
	if upn and up_bits and same_net(ipn, upn, math.min(bits, up_bits)) then
		return nil, "这个网段和上级网络（" .. up_ip .. "）重叠，会让上网出问题，请换一个网段。"
	end
	if uci:get("network", "wan", "proto") == "static" then
		local wi, wm = ip_and_mask(uci:get("network", "wan", "ipaddr"), uci:get("network", "wan", "netmask"))
		local wn, wb = ip4n(wi), mask_bits(wm)
		if wn and wb and same_net(ipn, wn, math.min(bits, wb)) then
			return nil, "这个网段和 WAN 口的静态地址（" .. wi .. "）重叠，请换一个网段。"
		end
	end
	if a.dhcp then
		a.start, a.limit, a.leasetime = tonumber(fv("start")), tonumber(fv("limit")), fv("leasetime")
		if not a.start or a.start < 1 or a.start ~= math.floor(a.start) then return nil, "地址池起始位置不正确。" end
		if not a.limit or a.limit < 1 or a.limit ~= math.floor(a.limit) then return nil, "地址池数量不正确。" end
		if a.start + a.limit - 1 > k - 2 then
			return nil, "地址池超出了这个网段的范围（最多 " .. (k - 2) .. " 个地址），请减小起始位置或数量。"
		end
		if not LAN_LEASES[a.leasetime] then return nil, "租期参数不正确。" end
	end
	return a
end

-- 读 LAN 的地址和 DHCP 服务。GET,只读。
function action_lan_get()
	luci.http.prepare_content("application/json")
	local uci = require "luci.model.uci".cursor()
	if uci:get("network", "lan") == nil then
		luci.http.write_json({ ok = false, error = "本机没有 LAN 口的配置" })
		return
	end
	local ip, mask = ip_and_mask(uci:get("network", "lan", "ipaddr"), uci:get("network", "lan", "netmask") or "255.255.255.0")
	local function d(k) return uci:get("dhcp", "lan", k) end
	local up_ip, up_bits = wanlan_up_net()
	luci.http.write_json({
		ok = true,
		ipaddr = ip, netmask = mask,
		dhcp = uci:get("dhcp", "lan") ~= nil and d("ignore") ~= "1",
		start = tonumber(d("start")) or 100,
		limit = tonumber(d("limit")) or 150,
		leasetime = d("leasetime") or "12h",
		up_ip = up_ip, up_bits = up_bits,
		client = luci.http.getenv("REMOTE_ADDR") or "",
	})
end

-- 写 LAN 的地址和 DHCP 服务。POST + CSRF。
-- 改 LAN IP 会让当前这条连接失效,所以响应先发出去,2 秒后才重载网络和 dnsmasq;
-- 响应里带上新地址和「当前访问者是否会断开」,前端据此倒计时后跳到新地址。
function action_lan_set()
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end
	luci.http.prepare_content("application/json")
	local function fail(msg) luci.http.write_json({ ok = false, error = msg }) end
	local uci = require "luci.model.uci".cursor()
	if uci:get("network", "lan") == nil then return fail("本机没有 LAN 口的配置") end
	local function fv(k) return ((luci.http.formvalue(k) or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
	local a, err = wanlan_lan_args(uci, fv)
	if not a then return fail(err) end

	local old_ip = ip_and_mask(uci:get("network", "lan", "ipaddr"), "")
	uci:set("network", "lan", "ipaddr", a.ipaddr)
	uci:set("network", "lan", "netmask", a.netmask)
	if uci:get("dhcp", "lan") == nil then
		uci:set("dhcp", "lan", "dhcp")
		uci:set("dhcp", "lan", "interface", "lan")
	end
	if a.dhcp then
		uci:delete("dhcp", "lan", "ignore")
		uci:set("dhcp", "lan", "start", tostring(a.start))
		uci:set("dhcp", "lan", "limit", tostring(a.limit))
		uci:set("dhcp", "lan", "leasetime", a.leasetime)
	else
		uci:set("dhcp", "lan", "ignore", "1")
	end
	local ok, e2 = uci:commit("network")
	if ok then ok, e2 = uci:commit("dhcp") end
	if not ok then
		uci:revert("network"); uci:revert("dhcp")
		return fail("保存配置失败：" .. tostring(e2 or "未知错误"))
	end
	os.execute("(sleep 2; /etc/init.d/network reload; sleep 4; /etc/init.d/dnsmasq restart) >/dev/null 2>&1 &")
	luci.http.write_json({
		ok = true, ipaddr = a.ipaddr, changed_ip = old_ip ~= a.ipaddr, dhcp = a.dhcp,
	})
end

-- ===================== USB 网卡 / 手机共享 =====================
--
-- 插拔识别、接口/防火墙/网关存活的建立与还原全部在 /usr/bin/mwrt-usbnic(hotplug 触发, 没有常驻进程),
-- 这里只做参数校验、读状态、把用户的选择交给它。状态在 /tmp/mwrt-usbnic.json。
-- 前端(mwrt-portsw.js)轮询 usbnic_state,nic 接入后弹「要不要当 WAN」,默认 LAN。

local USBNIC_BIN = "/usr/bin/mwrt-usbnic"
local USBNIC_JSON = "/tmp/mwrt-usbnic.json"

local function usbnic_dev_ok(d)
	return type(d) == "string" and #d >= 1 and #d <= 15 and d:match("^[%w][%w%._-]*$") ~= nil
end

-- 调脚本。返回 退出码, 输出(去掉末尾空白)。参数都已校验成只含 [%w._/-] 的串。
local function usbnic_run(args)
	local p = io.popen(USBNIC_BIN .. " " .. args .. " 2>&1; echo \"RC=$?\"")
	if not p then return 1, "" end
	local out = p:read("*a") or ""
	p:close()
	local rc = tonumber(out:match("RC=(%d+)%s*$")) or 1
	out = out:gsub("RC=%d+%s*$", ""):gsub("%s+$", "")
	return rc, out
end

local function usbnic_enabled(uci)
	return uci:get_first("mwrt", "ndis", "USBEN") == "1"
end

-- 读状态。GET,只读。**不回传任何密码**(文件里本来就没有)。
-- 平时直接读 /tmp 里的 JSON,不起进程;只有这几种情况才叫脚本对一次账:
--   没有 JSON、开关状态和文件对不上、某个 pending 的已经过了期限、某个口的 sysfs 已经没了
-- (正常情况下定时器和 hotplug 早就处理了,这里是兜底)。
function action_usbnic_state()
	local fs = require "nixio.fs"
	luci.http.prepare_content("application/json")
	local uci = require "luci.model.uci".cursor()
	local en = usbnic_enabled(uci)
	local now = os.time()
	-- 本机没有 RTC, NTP 会把挂钟一步跳走; pending 的剩余时间以脚本写的 dmono(开机秒数口径的截止点)为准,
	-- 在这里按"此刻开机秒数"重新折成挂钟 deadline, 前端用 deadline - now 算倒计时才不会被时间跳变带偏
	local function uptime_s()
		local u = fs.readfile("/proc/uptime")
		return u and tonumber(u:match("^(%d+)"))
	end
	local up = uptime_s()
	local function left_of(d)
		local dm = tonumber(d.dmono) or 0
		if up and dm > 0 then return dm - up end
		return (tonumber(d.deadline) or 0) - now
	end
	local function load()
		local txt = fs.readfile(USBNIC_JSON)
		local r = txt and require("luci.jsonc").parse(txt)
		if type(r) == "table" then return txt, r end
	end
	local txt, r = load()
	local mode
	if not r then
		mode = "state"
	elseif (r.enabled == true) ~= en then
		mode = "sync"
	else
		for _, d in ipairs(r.devs or {}) do
			if (d.role == "pending" and left_of(d) <= -2)
				or not fs.access("/sys/class/net/" .. tostring(d.dev) .. "/device") then
				mode = "state"
				break
			end
		end
	end
	if mode and fs.access(USBNIC_BIN, "x") then
		usbnic_run(mode)
		txt, r = load()
	end
	if not txt then
		txt = '{"v":1,"enabled":' .. (en and "true" or "false") .. ',"devs":[]}'
	end
	-- pending 的 deadline 按当前开机秒数重新折算(见上)
	if up then
		txt = txt:gsub('"deadline":%d+,"dmono":(%d+)', function(dm)
			dm = tonumber(dm)
			if dm and dm > 0 then
				return '"deadline":' .. (now + dm - up) .. ',"dmono":' .. dm
			end
		end)
	end
	-- 在最外层对象末尾补 now(服务器 epoch),让前端按服务器时间算倒计时
	luci.http.write((txt:gsub("%s*}%s*$", ',"now":' .. now .. "}", 1)))
end

-- 用户选 LAN / WAN。POST + token。只有脚本里记着的 nic 才能设置(手机共享口自动作出口, 不能设)。
-- 参数经临时文件交给脚本(不上命令行、不进 ps), 脚本读完即删。
function action_usbnic_set()
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end
	luci.http.prepare_content("application/json")
	local function fail(msg) luci.http.write_json({ ok = false, err = msg, error = msg }) end

	local fs = require "nixio.fs"
	if not fs.access(USBNIC_BIN, "x") then return fail("本机不支持 USB 网卡检测") end
	local function fv(k) return ((luci.http.formvalue(k) or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
	local dev, role = fv("dev"), fv("role")
	if not usbnic_dev_ok(dev) then return fail("设备名不正确") end
	if role ~= "lan" and role ~= "wan" then return fail("接入方式参数不正确") end

	local argf = ""
	local a
	if role == "wan" then
		local uci = require "luci.model.uci".cursor()
		local err
		-- 没有"已存的密码"可留: 已经设成 WAN 又改参数时, 脚本自己会用接口里存的那份
		a, err = port_wan_args(uci, fv, true)
		if not a then return fail(err) end
		argf = os.tmpname()
		local lines = {
			"proto=" .. a.proto, "username=" .. a.username, "password=" .. a.password,
			"ipaddr=" .. a.ipaddr, "netmask=" .. a.netmask, "gateway=" .. a.gateway,
			"dns=" .. table.concat(a.dns, " "),
		}
		if not fs.writefile(argf, table.concat(lines, "\n") .. "\n") then
			os.remove(argf)
			return fail("写入临时参数失败")
		end
	end

	local rc, out = usbnic_run(("set %s %s %s"):format(dev, role, argf))
	if argf ~= "" then os.remove(argf) end
	if rc ~= 0 or not out:find("OK", 1, true) then
		return fail(out:match("ERR:(.+)$") or "设置失败，请重试")
	end
	luci.http.write_json({ ok = true, dev = dev, role = role, proto = a and a.proto or nil })
end

-- 弹窗里点「忽略」/ 关掉 = 按 LAN 处理(等同 role=lan)。已经设成 WAN 的口不受影响。POST + token。
function action_usbnic_ignore()
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end
	luci.http.prepare_content("application/json")
	local function fail(msg) luci.http.write_json({ ok = false, err = msg, error = msg }) end
	local dev = ((luci.http.formvalue("dev") or ""):gsub("^%s+", ""):gsub("%s+$", ""))
	if not usbnic_dev_ok(dev) then return fail("设备名不正确") end
	if not require("nixio.fs").access(USBNIC_BIN, "x") then return fail("本机不支持 USB 网卡检测") end
	local rc, out = usbnic_run("ignore " .. dev)
	if rc ~= 0 or not out:find("OK", 1, true) then
		return fail(out:match("ERR:(.+)$") or "设置失败，请重试")
	end
	luci.http.write_json({ ok = true, dev = dev, role = "lan" })
end

local function _is_c5800()
	local f = io.open("/tmp/sysinfo/model", "r")
	local m = f and f:read("*l") or ""
	if f then f:close() end
	f = io.open("/tmp/sysinfo/board_name", "r")
	local b = f and f:read("*l") or ""
	if f then f:close() end
	return ((b .. "|" .. m):lower():find("c5800", 1, true)) ~= nil
end

function action_ak68_state()
	luci.http.prepare_content("application/json")
	if not _is_c5800() then
		luci.http.write_json({ supported = false })
		return
	end
	local out = luci.sys.exec("/usr/bin/mwrt-ak68 status 2>/dev/null") or ""
	local ok, st = pcall(function() return require("luci.jsonc").parse(out) end)
	if not ok or type(st) ~= "table" then st = { present = 0 } end
	st.supported = true
	luci.http.write_json(st)
end

-- s202: AK68 里模组的型号/固件/IMEI(设置页"当前模组"显示 AK68 自己的, 不是内置 5700)。只 C5800 且 AK68 在位才问, 结果缓存 10 分钟。
function action_ak68_info()
	luci.http.prepare_content("application/json")
	local jc = require("luci.jsonc")
	if not _is_c5800() then
		luci.http.write_json({ supported = false })
		return
	end
	local st = jc.parse(luci.sys.exec("/usr/bin/mwrt-ak68 status 2>/dev/null") or "")
	if type(st) ~= "table" or tonumber(st.present) ~= 1 then
		luci.http.write_json({ supported = true, present = 0 })
		return
	end
	local CF = "/tmp/mwrt-ak68.modinfo"
	local f = io.open(CF, "r")
	if f then
		local c = jc.parse(f:read("*a") or "")
		f:close()
		if type(c) == "table" and c.model and c.kind == st.kind and (os.time() - (tonumber(c.ts) or 0)) < 600 then
			c.present = 1
			luci.http.write_json(c)
			return
		end
	end
	local function ask(at)
		local out = luci.sys.exec("/usr/bin/mwrt-akat '" .. at .. "' 3 2>/dev/null") or ""
		for l in out:gmatch("[^\r\n]+") do
			l = l:gsub("^%s+", ""):gsub("%s+$", "")
			if l ~= "" and l ~= "OK" and l ~= "ERROR" and not l:find("^AT") and not l:find("^%+CM[ES] ERROR") then
				return (l:gsub("^%+%u+:%s*", ""))
			end
		end
		return ""
	end
	local r = {
		supported = true, present = 1, kind = st.kind,
		vendor = ask("AT+CGMI"), model = ask("AT+CGMM"), fw = ask("AT+CGMR"), imei = ask("AT+CGSN"),
		ts = os.time(),
	}
	if r.model ~= "" then
		local w = io.open(CF, "w")
		if w then w:write(jc.stringify(r)); w:close() end
	end
	luci.http.write_json(r)
end

function action_ak68_set()
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end
	luci.http.prepare_content("application/json")
	if not _is_c5800() then
		luci.http.write_json({ ok = false, error = "本机型不支持" })
		return
	end
	local poe = luci.http.formvalue("poe")
	local auto = luci.http.formvalue("auto")
	local uci = require "luci.model.uci".cursor()
	if poe ~= nil and poe ~= "" then
		if poe ~= "0" and poe ~= "1" then
			luci.http.write_json({ ok = false, error = "POE 参数不正确" })
			return
		end
		uci:set("mwrt_ak68", "main", "poe", poe)
	end
	if auto ~= nil and auto ~= "" then
		if auto ~= "0" and auto ~= "1" then
			luci.http.write_json({ ok = false, error = "自动识别参数不正确" })
			return
		end
		uci:set("mwrt_ak68", "main", "auto", auto)
	end
	uci:commit("mwrt_ak68")
	-- 守护每 3 秒读一次配置并应用; 这里立刻补一次 POE, 让界面马上看到变化
	if poe == "0" or poe == "1" then
		luci.sys.exec("/usr/bin/mwrt-ak68 poe " .. (poe == "1" and "on" or "off") .. " >/dev/null 2>&1")
	end
	luci.http.write_json({ ok = true })
end

function action_simstat()
	local out = luci.sys.exec("/usr/share/modem/simstat.sh 2>/dev/null") or ""
	luci.http.prepare_content("application/json")
	if out:match("^%s*{") then
		luci.http.write(out)
	else
		-- 脚本缺失或异常时给个结构一致的兜底,前端不用做特判
		luci.http.write_json({
			busy = 0, code = "", slot = "",
			iccid = "", text = "状态接口无响应"
		})
	end
end

-- 首页 SIM 卡槽磁贴「快速切卡」浮窗 —— 后端两件事。
-- 判据和 cbi/modem5700.lua 完全一致:机型串(model + board_name)含 C2000 才是三卡槽硬件,
-- 其余机型物理上只有一个卡槽(= C2000 的"外置SIM2卡槽" simsel=6),只给"机身卡槽"一个选项,
-- 绝不把 C2000 的多卡槽暴露给本机不存在的卡槽, 免得误切后"重启跳内置卡拔不掉"。
local function _sim_rd(p)
	local f = io.open(p, "r"); if not f then return "" end
	local s = f:read("*a") or ""; f:close(); return s
end

-- 本机当前是不是 MT5700 模组 —— 只有它才走 mt5700m.sh 切卡脚本,和 cbi 的 apply 分支一致。
local function _sim_is5700()
	local fs = require "nixio.fs"
	local c = fs.readfile("/tmp/modconf.conf") or ""
	return c:find("MT5700", 1, true) ~= nil
end

local function _sim_slots()
	local idstr = (_sim_rd("/tmp/sysinfo/model") .. " " .. _sim_rd("/tmp/sysinfo/board_name")):lower()
	-- s197 C5800: 本体 4 个外置卡槽 + 2 个内置卡槽 = 六卡槽(simsel 0/3/4/5=外置1-4, 1/2=内置1-2),
	-- 4 根选择脚 + AT^SCICHG 由 mt5700m.sh 的 C5800 分支执行; 只有机型串含 c5800 才给, 其余机型原样不变。
	-- 第三个返回值 = 是否 C5800(前端据此分组画"外置/内置"两排并显示六卡槽文案)
	if idstr:find("c5800", 1, true) then
		return {
			{ v = "0", label = "外置SIM卡槽1", grp = "外置" },
			{ v = "3", label = "外置SIM卡槽2", grp = "外置" },
			{ v = "4", label = "外置SIM卡槽3", grp = "外置" },
			{ v = "5", label = "外置SIM卡槽4", grp = "外置" },
			{ v = "1", label = "内置SIM卡槽1", grp = "内置" },
			{ v = "2", label = "内置SIM卡槽2", grp = "内置" },
		}, true, true
	end
	local isc2000 = idstr:find("c2000", 1, true) ~= nil
	if isc2000 then
		local slots = {
			{ v = "0", label = "外置SIM1卡槽" },
			{ v = "6", label = "外置SIM2卡槽" },
			{ v = "1", label = "内置卡" },
		}
		-- s157 350/520 等非 5700 模组也能切内置卡,但必须用户确认本机是原装鲲鹏内置模组
		-- (自己换的第三方模组切内置卡有锁卡风险);前端据 confirm 字段弹窗,服务端 simset 再核 confirm=1。
		if not _sim_is5700() then
			slots[3].confirm = "内置卡只适用于机器出厂自带的原装鲲鹏模组。\n如果你自己更换过第三方模组(移远、广和通等),切到内置卡可能导致内置卡被锁卡、封卡,且无法恢复。\n\n请确认:本机模组是出厂原装的鲲鹏模组,不是自行更换的第三方模组。\n\n确定要切换到内置卡吗?"
		end
		return slots, true
	end
	return { { v = "6", label = "机身卡槽" } }, false
end

-- s200 C5800 接了 AK68 且 ATSD 已通: 上网的是 AK68 里的模组和它自带的卡, 本机六卡槽切换对上网没有意义
local function _ak68_on()
	return _is_c5800() and nixio.fs.access("/tmp/mwrt-ak68.atsd") ~= nil
end

function action_simslots()
	local slots, isc2000, isc5800 = _sim_slots()
	local cur = ""
	do
		local uci = require "luci.model.uci".cursor()
		cur = uci:get_first("mwrt", "ndis", "simsel") or ""
	end
	luci.http.prepare_content("application/json")
	luci.http.write_json({
		-- s157 非 5700 的三卡槽机型(C2000 系列)也支持首页切卡,走 fm350sim.sh
		-- C5800 的多卡槽只有 MT5700 才能切(四脚编码+SCICHG 都是华为 AT), 别的模组不给
		supported = _sim_is5700() or (isc2000 and not isc5800),
		is_c2000 = isc2000 and not isc5800,
		is_c5800 = isc5800 and true or false,
		ak68 = _ak68_on(),
		current = cur,
		slots = slots,
	})
end

function action_simset()
	-- 和 wifi_set 一样:真正的闸门在服务端, 必须 POST + CSRF token。
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end

	luci.http.prepare_content("application/json")

	if _ak68_on() then
		luci.http.write_json({ ok = false, error = "已外接 AK68，上网使用 AK68 自带的卡，本机卡槽暂不可切换；拔掉 AK68 后再切换" })
		return
	end

	local is5700 = _sim_is5700()
	local slots, isc2000, isc5800 = _sim_slots()
	if not is5700 and (not isc2000 or isc5800) then
		luci.http.write_json({ ok = false, error = "当前模组不支持在本页切卡" })
		return
	end

	local target = luci.http.formvalue("slot") or ""
	local allow = false
	for _, s in ipairs(slots) do
		if s.v == target then allow = true break end
	end
	-- 白名单: 只认本机型清单里的卡槽值, 其它一律拒绝(含空值)。
	if not allow then
		luci.http.write_json({ ok = false, error = "该卡槽在本机型不可用" })
		return
	end

	local uci = require "luci.model.uci".cursor()
	local cur = uci:get_first("mwrt", "ndis", "simsel") or ""
	-- s157 非 5700 模组切内置卡必须带用户确认(confirm=1);已在内置卡且此前确认过则放行。
	local innerok = (uci:get_first("mwrt", "ndis", "inner_ok") or "") == "1"
	if not is5700 and target == "1" then
		if luci.http.formvalue("confirm") ~= "1" and not (cur == "1" and innerok) then
			luci.http.write_json({ ok = false, error = "切换到内置卡前需要确认本机是原装鲲鹏模组" })
			return
		end
	end
	if cur == target and (is5700 or target ~= "1" or innerok) then
		-- 已经在目标卡槽, 不必再跑一次 30 秒的切卡脚本。
		luci.http.write_json({ ok = true, noop = true, current = cur })
		return
	end

	-- 写 simsel → commit, 再后台跑切卡脚本。顺序和 cbi/modem5700.lua 的 apply 分支一致:
	-- 先把配置落地(mt5700m.sh 无参, 读的是 commit 后的 uci), 脚本才在后台(~30s)真正切卡。
	local sname = uci:get_first("mwrt", "ndis")
	if not sname then
		luci.http.write_json({ ok = false, error = "找不到模组配置节" })
		return
	end
	uci:set("mwrt", sname, "simsel", target)
	if not is5700 then
		-- 确认标记随选中内置卡写入;换到别的卡槽就清掉,下次再选要重新确认
		if target == "1" then uci:set("mwrt", sname, "inner_ok", "1")
		else uci:delete("mwrt", sname, "inner_ok") end
	end
	uci:commit("mwrt")

	-- 后台异步切卡 —— 脚本自己拿 /tmp/rm520n.lock, 切换中 simstat 的 busy 会置 1,
	-- 前端轮询 simstat 显示"切换中→完成", 不在这里阻塞请求。
	if is5700 then
		os.execute("/usr/share/modem/mt5700m.sh >/dev/null 2>&1 &")
	else
		-- 350/520: 硬件 mux 切卡 + 模组软重启读卡(脚本自带 5700/无引脚保护);
		-- 切卡期间借用 rm520n.lock 让 simstat 回"切换中"。
		os.execute("sh -c 'echo $$ > /tmp/rm520n.lock; FM350SIM_INNER_OK=" .. (target == "1" and "1" or "0") ..
			" /usr/share/modem/fm350sim.sh " .. target .. "; rm -f /tmp/rm520n.lock' >/dev/null 2>&1 &")
	end

	luci.http.write_json({ ok = true, current = target })
end

-- ============================================================================
-- 首页「无线网桥」(STA / apcli 客户端桥接) —— 扫描 / 状态 / 加入 / 断开。
--
-- 机制(板上实测): mtwifi 的 apcli 客户端口(apcli0=2.4G、apclii0=5G)现成存在。
--   · 扫描 = ubus call iwinfo scan {device=ra0/rai0}(和 LuCI wireless 页 getScanList 同源)。
--   · 桥接 = 建一个 mode='sta' 的 wifi-iface(device=对应 radio、ssid/encryption/key、
--            network='wwan'), network.wwan proto='dhcp', 把 wwan 加进 wan 防火墙区域。
--            /sbin/mtwifi_cfg 的 sta 分支据此把 ApCliEnable/ApCliSsid/... 写进驱动。
--   · 主路由 = Mwrt-Assurance.wan_failover 把 primary_if 设成 apcli 网卡、enabled=1、
--            force_primary=1; 常驻守护 mwrt_wan_failover.sh 每轮热读 uci, 自动按 metric 切。
--   · 本机热点(AP)一律不动, apcli 与 AP 同频共存。
-- 风险高(改无线/网络/防火墙/路由), 写操作全部 POST+CSRF, 应用异步不阻塞响应。
-- ============================================================================

-- 固定的桥接网络名 / sta 配置节名(幂等: 每次 join 先按这个名清旧再建)。
local WLB_NET = "wwan"
local WLB_SID = "mwrt_wlbridge"
-- 无线网桥事件文件: 写 "<epoch>|up|<ssid>" / "<epoch>|down|<ssid>", 供右上角
-- 通知中心(rpcd luci.mwrt-notice)当"一次性事件"读出来显示一小会儿。两边路径一致。
local WLB_EVENT = "/tmp/mwrt-wlbridge.event"

-- 写一条桥接事件。kind = "up" / "down"。ssid 里的竖线/换行剔掉(分隔符安全),
-- 用 nixio.fs.writefile 直接落地(不 fork、不经 shell, 免注入)。
local function wlb_write_event(kind, ssid)
	local fs = require "nixio.fs"
	local s = tostring(ssid or ""):gsub("[|\r\n]", " ")
	local ts = os.time()
	fs.writefile(WLB_EVENT, string.format("%d|%s|%s\n", ts, kind, s))
end

-- 按 band('2g'/'5g')拿 { device=wifi-device名, phy=ra0/rai0, netdev=apcli0/apclii0 }。
-- netdev 由 phy 推: ra0→apcli0, rai0→apclii0(prefix + idx0, 和 l1util apcli_ifname 一致)。
local function wlb_radio(band)
	local uci = require "luci.model.uci".cursor()
	local dev, phy
	uci:foreach("wireless", "wifi-device", function(s)
		if not dev and s.band == band then dev = s[".name"]; phy = s.phy end
	end)
	if not dev then return nil end
	-- ra0 → apcli0 ; rai0 → apclii0(把 phy 里 ra 后面那段插 "cli")
	local netdev
	if phy == "ra0" then netdev = "apcli0"
	elseif phy == "rai0" then netdev = "apclii0"
	else
		-- 兜底: raX → apcliX、raiX → apcliiX
		local base, idx = (phy or ""):match("^(ra[i]?)(%d+)$")
		if base then netdev = base .. "cli" .. idx else netdev = "apcli0" end
	end
	return { device = dev, phy = phy, netdev = netdev }
end

-- 把 iwinfo scan 的 encryption 对象映射成 uci encryption 值(与 mtwifi enc2dat / wireless.js 同口径)。
local function wlb_enc(e)
	if type(e) ~= "table" or not e.enabled then return "none" end
	local auth = e.authentication or {}
	local has = function(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
	if has(auth, "sae") then
		-- 对端是 WPA3(或 WPA2/WPA3 过渡), 都用 sae(mtwifi sae 能连过渡 AP)
		return "sae"
	end
	if has(auth, "psk") then
		local wpa = e.wpa or {}
		local w1, w2 = has(wpa, 1), has(wpa, 2)
		if w1 and w2 then return "psk-mixed" end
		if w2 then return "psk2" end
		if w1 then return "psk" end
		return "psk2"
	end
	-- 只有 WEP 或未知加密: 不支持桥接(返回空让前端标"不支持")
	if e.wep then return "wep" end
	return "unknown"
end

-- 字符串是否是「干净可显示」的 UTF-8 SSID(过滤隐藏/乱码 AP)。
-- 严格校验 UTF-8: ASCII 可见字符直接过; 多字节必须是合法 UTF-8 续字节序列。
-- 非法字节(单独的 0x80-0xBF、0xFE/0xFF、DEL 0x7F、控制符)→ 判脏。
local function wlb_utf8_ok(s)
	if not s or s == "" then return false end
	if s:find("\239\191\189") then return false end  -- U+FFFD 替换符
	local i, n = 1, #s
	while i <= n do
		local c = s:byte(i)
		if c < 0x20 or c == 0x7F then
			return false  -- 控制字符 / DEL
		elseif c < 0x80 then
			i = i + 1     -- ASCII 可见
		elseif c >= 0xC2 and c <= 0xDF then
			-- 2 字节: 后面 1 个 0x80-0xBF
			local c2 = s:byte(i + 1)
			if not c2 or c2 < 0x80 or c2 > 0xBF then return false end
			i = i + 2
		elseif c >= 0xE0 and c <= 0xEF then
			-- 3 字节(含中文): 后面 2 个 0x80-0xBF
			local c2, c3 = s:byte(i + 1), s:byte(i + 2)
			if not c2 or c2 < 0x80 or c2 > 0xBF or not c3 or c3 < 0x80 or c3 > 0xBF then return false end
			i = i + 3
		elseif c >= 0xF0 and c <= 0xF4 then
			-- 4 字节: 后面 3 个 0x80-0xBF
			local c2, c3, c4 = s:byte(i + 1), s:byte(i + 2), s:byte(i + 3)
			if not c2 or c2 < 0x80 or c2 > 0xBF or not c3 or c3 < 0x80 or c3 > 0xBF or not c4 or c4 < 0x80 or c4 > 0xBF then return false end
			i = i + 4
		else
			return false  -- 0x80-0xC1 单独出现、0xF5-0xFF 非法
		end
	end
	return true
end

function action_wlbridge_scan()
	local band = luci.http.formvalue("band")
	luci.http.prepare_content("application/json")
	if band ~= "2g" and band ~= "5g" then
		luci.http.write_json({ ok = false, error = "频段参数不合法" })
		return
	end
	local r = wlb_radio(band)
	if not r then
		luci.http.write_json({ ok = false, error = "找不到 " .. band .. " 频段的无线设备" })
		return
	end

	-- ubus call iwinfo scan {"device":"ra0"} —— 返回结构化结果, 不用解析 iwpriv。
	local jsonc = require "luci.jsonc"
	local out = luci.sys.exec("ubus call iwinfo scan '{\"device\":\"" .. r.phy .. "\"}' 2>/dev/null") or ""
	local parsed = jsonc.parse(out)
	local results = (type(parsed) == "table" and parsed.results) or {}

	local list = {}
	for _, b in ipairs(results) do
		local enc = wlb_enc(b.encryption)
		local ssid = b.ssid
		local ok = wlb_utf8_ok(ssid)
		-- 保留能连的(psk/psk2/psk-mixed/sae/none); wep/unknown 标出来但置灰不可点
		list[#list + 1] = {
			ssid = ok and ssid or "",
			hidden = (not ok),
			bssid = b.bssid,
			signal = b.signal,
			quality = b.quality,
			quality_max = b.quality_max,
			channel = b.channel,
			enc = enc,
			joinable = ok and (enc ~= "wep" and enc ~= "unknown"),
		}
	end
	-- 按信号质量降序
	table.sort(list, function(a, bb) return (a.quality or 0) > (bb.quality or 0) end)
	luci.http.write_json({ ok = true, band = band, netdev = r.netdev, list = list })
end

-- 读当前桥接状态: 有没有 sta iface、apcli 关联到哪、拿没拿到 IP、是否已设为主路由。
local function wlb_read_status()
	local uci = require "luci.model.uci".cursor()
	local fs = require "nixio.fs"
	local st = { bridged = false, band = "", ssid = "", bssid = "", ip = "",
		signal = nil, associated = false, primary_on = false, netdev = "" }

	-- 找我们建的 sta iface
	local sid
	uci:foreach("wireless", "wifi-iface", function(s)
		if s.mode == "sta" then sid = s[".name"]; return false end
	end)
	if not sid then return st end
	local dev = uci:get("wireless", sid, "device")
	st.ssid = uci:get("wireless", sid, "ssid") or ""
	-- device → band → netdev
	local band = uci:get("wireless", dev or "", "band") or ""
	st.band = band
	local r = band ~= "" and wlb_radio(band) or nil
	local netdev = r and r.netdev or "apcli0"
	st.netdev = netdev
	st.bridged = true

	-- 关联状态: iwconfig 的 Access Point(Not-Associated 为未连)
	local iw = luci.sys.exec("iwconfig " .. netdev .. " 2>/dev/null") or ""
	local ap = iw:match("Access Point:%s*([%x:]+)")
	st.associated = (ap ~= nil and ap:upper() ~= "NOT-ASSOCIATED" and ap ~= "00:00:00:00:00:00")
	if st.associated then st.bssid = ap:upper() end
	local essid = iw:match('ESSID:"([^"]*)"')
	if essid and essid ~= "" then st.ssid = essid end

	-- 拿到 IP 没(apcli netdev 上的 ipv4)
	local ipout = luci.sys.exec("ip -4 addr show dev " .. netdev .. " 2>/dev/null") or ""
	st.ip = ipout:match("inet%s+([%d%.]+)") or ""

	-- 是否已设为主路由(Mwrt-Assurance)
	local pif = uci:get("Mwrt-Assurance", "wan_failover", "primary_if") or ""
	local en = uci:get("Mwrt-Assurance", "wan_failover", "enabled") or "0"
	st.primary_on = (pif == netdev and en == "1")
	return st
end

function action_wlbridge_status()
	luci.http.prepare_content("application/json")
	luci.http.write_json(wlb_read_status())
end

function action_wlbridge_join()
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end
	luci.http.prepare_content("application/json")

	local band = luci.http.formvalue("band")
	local ssid = luci.http.formvalue("ssid") or ""
	local bssid = luci.http.formvalue("bssid") or ""
	local key = luci.http.formvalue("key") or ""
	local enc = luci.http.formvalue("enc") or ""
	local as_primary = (luci.http.formvalue("primary") == "1")

	if band ~= "2g" and band ~= "5g" then
		luci.http.write_json({ ok = false, error = "频段参数不合法" }); return
	end
	if ssid == "" or #ssid > 32 then
		luci.http.write_json({ ok = false, error = "上游网络名称不合法" }); return
	end
	local ENC_OK = { ["none"]=true, ["psk"]=true, ["psk2"]=true, ["psk-mixed"]=true, ["sae"]=true }
	if not ENC_OK[enc] then
		luci.http.write_json({ ok = false, error = "该网络的加密方式暂不支持桥接" }); return
	end
	if enc ~= "none" and (#key < 8 or #key > 63) then
		luci.http.write_json({ ok = false, error = "上游 WiFi 密码需要 8 - 63 个字符" }); return
	end

	local r = wlb_radio(band)
	if not r then
		luci.http.write_json({ ok = false, error = "找不到 " .. band .. " 频段的无线设备" }); return
	end

	local uci = require "luci.model.uci".cursor()

	-- 幂等: 先删掉所有已存在的 sta iface(本功能固定单桥接), 避免叠加 / 换频段残留。
	local to_del = {}
	uci:foreach("wireless", "wifi-iface", function(s)
		if s.mode == "sta" then to_del[#to_del + 1] = s[".name"] end
	end)
	for _, n in ipairs(to_del) do uci:delete("wireless", n) end

	-- 建 STA 客户端 iface
	uci:section("wireless", "wifi-iface", WLB_SID, {
		device = r.device,
		mode = "sta",
		network = WLB_NET,
		ssid = ssid,
		encryption = enc,
	})
	if enc ~= "none" then uci:set("wireless", WLB_SID, "key", key) end
	if bssid ~= "" and bssid:match("^[%x:]+$") then uci:set("wireless", WLB_SID, "bssid", bssid) end
	uci:commit("wireless")

	-- network.wwan = dhcp 接口(apcli netdev 由 netifd 自动挂进来)
	uci:delete("network", WLB_NET)
	uci:section("network", "interface", WLB_NET, { proto = "dhcp" })
	uci:commit("network")

	-- 把 wwan 加进 wan 防火墙区域(只增不删其它成员)
	uci:foreach("firewall", "zone", function(s)
		if s.name == "wan" then
			local nets = s.network or {}
			if type(nets) == "string" then nets = { nets } end
			local seen = false
			for _, n in ipairs(nets) do if n == WLB_NET then seen = true end end
			if not seen then nets[#nets + 1] = WLB_NET; uci:set("firewall", s[".name"], "network", nets) end
			return false
		end
	end)
	uci:commit("firewall")

	-- 设为主路由 + 开网关存活(可选, 默认开)。
	-- ⚠ 只改 primary_if, **不动 secondary_if** —— secondary 是原来的故障兜底口
	-- (通常是蜂窝 eth2)。早期版本把旧 primary 塞进 secondary, 结果把蜂窝兜底口
	-- 覆盖成了宽带口 eth1, 断开后"路由切换状态"里蜂窝一直显示离线(它在探 eth1)。
	-- 现在:桥接前的 primary_if / secondary_if / enabled 全存到 sta 节点, 断开时三者
	-- 原样还原, 谁都不越权覆盖。
	if as_primary then
		local old_pif = uci:get("Mwrt-Assurance", "wan_failover", "primary_if") or ""
		local old_sif = uci:get("Mwrt-Assurance", "wan_failover", "secondary_if") or ""
		local old_en  = uci:get("Mwrt-Assurance", "wan_failover", "enabled") or "0"
		uci:set("wireless", WLB_SID, "wlb_old_en", old_en)
		uci:set("wireless", WLB_SID, "wlb_old_pif", old_pif)
		uci:set("wireless", WLB_SID, "wlb_old_sif", old_sif)
		uci:commit("wireless")
		uci:set("Mwrt-Assurance", "wan_failover", "primary_if", r.netdev)
		uci:set("Mwrt-Assurance", "wan_failover", "enabled", "1")
		uci:set("Mwrt-Assurance", "wan_failover", "force_primary", "1")
		uci:commit("Mwrt-Assurance")
	end

	-- 异步应用: wifi reload 建 apcli + 关联, ifup wwan 起 DHCP。放后台, 不阻塞本响应
	-- (用户可能正用本机 WiFi 连着这页, 同步跑会把响应闷死)。
	os.execute("( wifi reload; sleep 2; /sbin/ifup " .. WLB_NET .. " ) >/dev/null 2>&1 &")

	-- 发一条"已接入"事件给右上角通知中心
	wlb_write_event("up", ssid)

	luci.http.write_json({ ok = true, netdev = r.netdev, band = band })
end

function action_wlbridge_leave()
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end
	luci.http.prepare_content("application/json")

	local uci = require "luci.model.uci".cursor()

	-- 记下当前桥接网卡, 好把网关存活主口还原
	local st = wlb_read_status()

	-- 删 sta iface 前, 先读出桥接时存下的"桥接前网关存活状态", 用于精确还原
	local old_en, old_pif, old_sif = nil, nil, nil
	uci:foreach("wireless", "wifi-iface", function(s)
		if s.mode == "sta" then
			old_en = s.wlb_old_en; old_pif = s.wlb_old_pif; old_sif = s.wlb_old_sif
		end
	end)

	-- 删 sta iface
	local dels = {}
	uci:foreach("wireless", "wifi-iface", function(s)
		if s.mode == "sta" then dels[#dels + 1] = s[".name"] end
	end)
	for _, n in ipairs(dels) do uci:delete("wireless", n) end
	uci:commit("wireless")

	-- 从 wan 区域移除 wwan + 删 network.wwan
	uci:foreach("firewall", "zone", function(s)
		if s.name == "wan" then
			local nets = s.network or {}
			if type(nets) == "string" then nets = { nets } end
			local keep = {}
			for _, n in ipairs(nets) do if n ~= WLB_NET then keep[#keep + 1] = n end end
			uci:set("firewall", s[".name"], "network", keep)
			return false
		end
	end)
	uci:commit("firewall")
	uci:delete("network", WLB_NET)
	uci:commit("network")

	-- 网关存活还原: 只有当前主口确实是桥接网卡时才动它(别人手动改过就不越权)。
	-- 把桥接前存下的 primary_if / secondary_if / enabled 三者原样还原 —— 尤其
	-- secondary_if 必须还原, 否则蜂窝兜底口会一直停在错的网卡上, 状态页显示离线。
	local pif = uci:get("Mwrt-Assurance", "wan_failover", "primary_if") or ""
	if pif == st.netdev and st.netdev ~= "" then
		local changed = false
		if old_pif and old_pif ~= "" and old_pif ~= st.netdev then
			uci:set("Mwrt-Assurance", "wan_failover", "primary_if", old_pif); changed = true
		else
			-- 存不到桥接前主口: 回落到 secondary 兜底口(不把 primary 留在已删的桥接网卡上)
			local sif = uci:get("Mwrt-Assurance", "wan_failover", "secondary_if") or ""
			if sif ~= "" and sif ~= st.netdev then
				uci:set("Mwrt-Assurance", "wan_failover", "primary_if", sif); changed = true
			end
		end
		-- secondary_if 原样还原(桥接时本不该动它, 这里兜底把早期版本搞乱的也纠回来)
		if old_sif and old_sif ~= "" and old_sif ~= st.netdev then
			uci:set("Mwrt-Assurance", "wan_failover", "secondary_if", old_sif); changed = true
		end
		-- 桥接前是关着的, 就还原成关(桥接是唯一把它打开的原因)
		if old_en ~= nil then
			uci:set("Mwrt-Assurance", "wan_failover", "enabled", old_en); changed = true
		end
		if changed then uci:commit("Mwrt-Assurance") end
	end

	os.execute("( wifi reload ) >/dev/null 2>&1 &")

	-- 发一条"已断开"事件给右上角通知中心(用拆桥前记下的 ssid)
	wlb_write_event("down", st.ssid)

	luci.http.write_json({ ok = true })
end

-- USB 摄像头预览。抓帧由 /usr/libexec/mwrt-camsnap 在后台做(单实例, 心跳 6 秒无更新自退),
-- 这里只转一手: 命令串是写死的, 不含任何用户输入。
local CAM_BIN = "/usr/libexec/mwrt-camsnap"
local CAM_JPG = "/tmp/mwrt-cam.jpg"
local CAM_BEAT = "/tmp/mwrt-cam.beat"
local CAM_RL = "/tmp/mwrt-cam.rl"
local CAM_RL_GAP = 2        -- camstart 限频(秒)
local CAM_JPG_MAX = 2097152 -- 单帧上限, 和脚本里的一致

local function cam_call(sub)
	local out = luci.sys.exec(CAM_BIN .. " " .. sub .. " 2>/dev/null") or ""
	local j = require("luci.jsonc").parse((out:match("^%s*(.-)%s*$")))
	if type(j) ~= "table" then return { ok = false, error = "fail" } end
	if j.dev and not tostring(j.dev):match("^/dev/video%d+$") then j.dev = nil end
	return j
end

function action_camstart()
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end
	local fs = require "nixio.fs"
	luci.http.prepare_content("application/json")

	-- 限频: 2 秒内重复点直接回上一次的结果(文件里存的就是上次的 JSON)
	local st = fs.stat(CAM_RL)
	if st and st.mtime and math.abs(os.time() - st.mtime) < CAM_RL_GAP then
		local last = fs.readfile(CAM_RL)
		if last and #last > 0 then
			luci.http.write(last)
			return
		end
	end

	local res = cam_call("start")
	local body = require("luci.jsonc").stringify(res) or '{"ok":false,"error":"fail"}'
	fs.writefile(CAM_RL, body)
	luci.http.write(body)
end

function action_camframe()
	local fs = require "nixio.fs"
	luci.http.header("Cache-Control", "no-store")
	-- 读帧就是心跳: 浏览器还在看, 抓帧就别退
	if fs.access(CAM_BEAT) then
		local now = os.time()
		if not fs.utimes(CAM_BEAT, now, now) then fs.writefile(CAM_BEAT, "") end
	end
	local st = fs.stat(CAM_JPG)
	local data = st and st.size and st.size > 0 and st.size <= CAM_JPG_MAX and fs.readfile(CAM_JPG)
	if not data or #data == 0 then
		luci.http.status(503, "No Frame")
		luci.http.prepare_content("text/plain")
		luci.http.write("")
		return
	end
	luci.http.prepare_content("image/jpeg")
	luci.http.write(data)
end

function action_camstop()
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end
	luci.http.prepare_content("application/json")
	-- 停了就让下一次 camstart 立刻生效, 不吃限频
	require("nixio.fs").remove(CAM_RL)
	luci.http.write_json(cam_call("stop"))
end

-- USB 声卡。所有逻辑在 /usr/libexec/mwrt-audio(一次性子命令输出一行 JSON), 这里只做参数白名单和转手。
local AUDIO_BIN = "/usr/libexec/mwrt-audio"
local AUDIO_DIR = "/tmp/mwrt-music"      -- 上传落盘目录, 与脚本里的默认值一致
local AUDIO_FILE_MAX = 31457280          -- 单个上传文件上限, 与脚本里的一致

local function audio_exec(args)
	local out = luci.sys.exec(AUDIO_BIN .. " " .. args .. " 2>/dev/null") or ""
	out = out:match("^%s*(.-)%s*$")
	-- 脚本只会输出一行 JSON 对象; 不是就当音频服务不可用
	if out:sub(1, 1) ~= "{" or out:sub(-1) ~= "}" then
		return '{"ok":false,"err":"音频服务暂不可用"}'
	end
	return out
end

local function audio_reply(args)
	luci.http.prepare_content("application/json")
	luci.http.header("Cache-Control", "no-store")
	luci.http.write(audio_exec(args))
end

local function audio_bad(msg)
	luci.http.prepare_content("application/json")
	luci.http.write_json({ ok = false, err = msg })
end

-- 取表单值并只放行白名单; 不合格返回 nil
local function audio_enum(k, ...)
	local v = luci.http.formvalue(k)
	if type(v) ~= "string" then return nil end
	for _, w in ipairs({ ... }) do if v == w then return v end end
	return nil
end

local function audio_id(k)
	local v = luci.http.formvalue(k)
	if type(v) == "string" and v:match("^[tus]%x%x%x%x%x%x%x%x$") then return v end
	return nil
end

function action_audio_state()
	audio_reply("state")
end

-- audio_wave 每 300 毫秒一次, 每次都 fork sh + lua 太费。守护活着时在这里直接读它写的电平文件、顺手刷新心跳;
-- 守护没起(或文件对不上)才走子命令 wave 去拉起守护。取值规则与 /usr/libexec/mwrt-audio 的 cmd_wave 保持一致(改一边要改另一边)。
local AUDIO_RUN = "/tmp/mwrt-audio"
local AUDIO_RING = 200

local function audio_rd(p)
	local f = io.open(p, "rb")
	if not f then return nil end
	local d = f:read("*a")
	f:close()
	return d
end

local function audio_daemon_alive()
	local pid = tonumber((audio_rd(AUDIO_RUN .. "/daemon.pid") or ""):match("^%d+"))
	if not pid or pid < 2 then return false end
	local c = audio_rd("/proc/" .. pid .. "/cmdline")
	return (c and c:find("mwrt-audio", 1, true) and c:find("daemon", 1, true)) and true or false
end

local function audio_wave_fast(q)
	if not audio_daemon_alive() then return nil end
	local d = audio_rd(AUDIO_RUN .. "/state.json")
	local ol = audio_rd(AUDIO_RUN .. "/out.lv")
	local ml = audio_rd(AUDIO_RUN .. "/mic.lv")
	if not d or not ol or not ml then return nil end
	local os_, ov = ol:match("^(%d+)\n([^\n]*)")
	local ms_, mv = ml:match("^(%d+)\n([^\n]*)")
	local cs = tonumber(os_)
	if not cs or ms_ ~= os_ then return nil end
	-- 刷新心跳(与 ensure_daemon 的 touch 等价)
	local nfs = require "nixio.fs"
	local t = os.time()
	if not nfs.utimes(AUDIO_RUN .. "/beat", t, t) then return nil end
	local ovals, mvals = {}, {}
	for v in ov:gmatch("%d+") do ovals[#ovals + 1] = tonumber(v) end
	for v in mv:gmatch("%d+") do mvals[#mvals + 1] = tonumber(v) end
	local have = math.min(#ovals, #mvals)
	local cur = tonumber(q)
	local want
	if not cur or cur > cs or cs - cur > AUDIO_RING then want = 20 else want = math.min(cs - cur, 40) end
	want = math.min(want, have)
	local o, m = {}, {}
	for i = have - want + 1, have do
		o[#o + 1] = ovals[i]
		m[#m + 1] = mvals[i]
	end
	local micon = d:match('"on":(%a+)') == "true"
	local pstate = d:match('"player":{.-"state":"(%a+)"') or "idle"
	return ('{"ok":true,"seq":%.0f,"step":50,"out":[%s],"mic":[%s],"micon":%s,"pstate":"%s"}'):format(
		cs, table.concat(o, ","), table.concat(m, ","), micon and "true" or "false", pstate)
end

function action_audio_wave()
	-- seq 只放行纯整数(<=15 位), 否则当没给
	local q = luci.http.formvalue("seq")
	if not (type(q) == "string" and q:match("^%d+$") and #q <= 15) then q = nil end
	local fast = audio_wave_fast(q)
	if fast then
		luci.http.prepare_content("application/json")
		luci.http.header("Cache-Control", "no-store")
		luci.http.write(fast)
	elseif q then
		audio_reply("wave " .. q)
	else
		audio_reply("wave")
	end
end

function action_audio_vol()
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end
	local kind = audio_enum("kind", "play", "cap")
	if not kind then return audio_bad("参数不正确") end
	local raw = luci.http.formvalue("pct")
	-- 只接受十进制数字(拒绝 nan、inf、十六进制、科学计数法), 再四舍五入夹紧到 0-100
	if type(raw) ~= "string" or #raw > 12 or not raw:match("^%-?%d+%.?%d*$") then
		return audio_bad("音量必须是 0 到 100 的数字")
	end
	local n = math.floor(tonumber(raw) + 0.5)
	if n < 0 then n = 0 elseif n > 100 then n = 100 end
	audio_reply(("vol %s %d"):format(kind, n))
end

function action_audio_mute()
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end
	local kind = audio_enum("kind", "play", "cap")
	local on = audio_enum("on", "1", "0")
	if not kind or not on then return audio_bad("参数不正确") end
	audio_reply(("mute %s %s"):format(kind, on))
end

function action_audio_play()
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end
	local id = audio_id("id")
	if not id then return audio_bad("曲目不存在或已被删除") end
	local card = luci.http.formvalue("card")
	if card == nil or card == "" then
		audio_reply("play " .. id)
	elseif type(card) == "string" and card:match("^%d+$") and #card <= 3 then
		audio_reply(("play %s %d"):format(id, tonumber(card)))
	else
		audio_bad("声卡参数不正确")
	end
end

function action_audio_ctl()
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end
	local act = audio_enum("act", "pause", "resume", "stop")
	if not act then return audio_bad("参数不正确") end
	audio_reply("ctl " .. act)
end

function action_audio_mic()
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end
	local on = audio_enum("on", "1", "0")
	if not on then return audio_bad("参数不正确") end
	audio_reply("mic " .. on)
end

function action_audio_del()
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end
	local id = audio_id("id")
	if not id then return audio_bad("曲目不存在或已被删除") end
	audio_reply("del " .. id)
end

-- 上传: multipart, 字段名 file。用 setfilehandler 边收边写到上传目录里的 .up<数字>(不整个读进内存),
-- 原文件名单独存进 .up<数字>.name(只当数据, 不进命令行), 收完叫 mwrt-audio ingest <数字> 做扩展名 / 大小 /
-- 总量 / 剩余内存校验与安全改名。文件处理器必须在 test_post_security() 之前登记(它会触发整个请求体解析)。
-- 超过 CONTENT_LENGTH 明显过大的请求直接拒绝, 不读请求体。
local audio_seeded = false

function action_audio_upload()
	local http = luci.http
	local fs = require "nixio.fs"
	local dsp = require "luci.dispatcher"

	local clen = tonumber(http.getenv("CONTENT_LENGTH") or "")
	if clen and clen > AUDIO_FILE_MAX + 1048576 then
		return audio_bad("文件太大，单个文件不能超过 30 MB")
	end

	if not audio_seeded then
		math.randomseed(os.time())
		audio_seeded = true
	end

	local st = { fp = nil, num = nil, tmp = nil, size = 0, err = nil, done = false, started = false }

	local function drop()
		if st.fp then st.fp:close(); st.fp = nil end
		if st.tmp then fs.remove(st.tmp); fs.remove(st.tmp .. ".name") end
	end

	http.setfilehandler(function(meta, chunk, eof)
		if not meta or meta.name ~= "file" or st.done or st.err then return end
		if not st.started then
			st.started = true
			-- 预检: 单文件 / 总量 / 剩余内存(按 CONTENT_LENGTH 估大小; 估不出来就按 0, 落盘后 ingest 还会再验)
			local q = audio_exec("quota " .. string.format("%d", clen or 0))
			local j = require("luci.jsonc").parse(q)
			if type(j) ~= "table" or j.ok ~= true then
				st.err = (type(j) == "table" and j.err) or "音频服务暂不可用"
				return
			end
			for _ = 1, 20 do
				st.num = string.format("%d", math.random(100000000, 999999999))
				st.tmp = AUDIO_DIR .. "/.up" .. st.num
				if not fs.stat(st.tmp) then break end
			end
			st.fp = io.open(st.tmp, "wb")
			if not st.fp then st.err = "保存失败，请重试"; st.tmp = nil; return end
			-- 原文件名最多留 1024 字节, 只作数据写入, ingest 里会清洗
			local nf = io.open(st.tmp .. ".name", "wb")
			if nf then nf:write(tostring(meta.file or ""):sub(1, 1024)); nf:close() end
		end
		if chunk and #chunk > 0 and st.fp then
			st.size = st.size + #chunk
			if st.size > AUDIO_FILE_MAX then
				st.err = "文件太大，单个文件不能超过 30 MB"
				drop()
				return
			end
			if not st.fp:write(chunk) then
				st.err = "保存失败，可能是设备内存不足"
				drop()
				return
			end
		end
		if eof then
			if st.fp then st.fp:close(); st.fp = nil end
			st.done = true
		end
	end)

	if not dsp.test_post_security() then drop(); return end

	if st.err then drop(); return audio_bad(st.err) end
	if not st.done or not st.tmp or st.size == 0 then drop(); return audio_bad("没有收到文件") end
	audio_reply("ingest " .. st.num)
end


-- =============================================================================
-- s90: 网络拓扑数据 topo_data / 插件菜单解锁状态 unlock_state
--
-- topo_data: GET admin/modem/topo_data, 登录后可读, 只读 /proc /sys /tmp 缓存 + ubus + uci,
--            绝不碰串口 / AT(蜂窝部分只读 /tmp/mwrt_cellinfo.json 与 /tmp/run/mwrt/modem_info_*.json 两份已落盘缓存)。
--            在线设备清单来自 /usr/libexec/mwrt-clients(与首页"在线设备"数同一份口径)。
-- 所有 helper 收进一个 TOPO 表, 不占用文件顶层 local 名额(Lua 5.1 每个函数最多 200 个 local)。
-- =============================================================================
local TOPO = {}
local T_NULL = setmetatable({}, { __tostring = function() return "null" end })
local T_ARR = setmetatable({}, { __mode = "k" })

function TOPO.arr(t) T_ARR[t] = true; return t end

function TOPO.rd(p)
	local f = io.open(p, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

function TOPO.num(s)
	if s == nil then return nil end
	return tonumber(tostring(s):match("^%s*(-?%d+%.?%d*)"))
end

-- 校验 UTF-8: 非法字节(截断序列 / 过长编码 / 代理对 / 超出 U+10FFFF)换成 U+FFFD; maxb 非空时按字节截断且不切断字符
-- (与 /usr/libexec/mwrt-clients 的 u8clean 同一算法, 保证严格 JSON 解析器能收)
function TOPO.u8(s, maxb)
	s = tostring(s)
	if not s:find("[\128-\255]") then
		if maxb and #s > maxb then return s:sub(1, maxb) end
		return s
	end
	local out, i, n, nb = {}, 1, #s, 0
	while i <= n do
		local c = s:byte(i)
		local len = nil
		if c < 0x80 then len = 1
		elseif c >= 0xC2 and c <= 0xDF then len = 2
		elseif c >= 0xE0 and c <= 0xEF then len = 3
		elseif c >= 0xF0 and c <= 0xF4 then len = 4 end
		local ok = len ~= nil
		if ok and len > 1 then
			if i + len - 1 > n then
				ok = false
			else
				for k = 1, len - 1 do
					local d = s:byte(i + k)
					if d < 0x80 or d > 0xBF then ok = false; break end
				end
				if ok then
					local c2 = s:byte(i + 1)
					if (c == 0xE0 and c2 < 0xA0) or (c == 0xED and c2 > 0x9F)
					   or (c == 0xF0 and c2 < 0x90) or (c == 0xF4 and c2 > 0x8F) then ok = false end
				end
			end
		end
		local piece
		if ok then piece = s:sub(i, i + len - 1); i = i + len
		else piece = "\239\191\189"; i = i + 1 end
		if maxb and nb + #piece > maxb then break end
		out[#out + 1] = piece
		nb = nb + #piece
	end
	return table.concat(out)
end

-- 自带序列化: luci.jsonc 把 nil 字段直接丢掉、把空对象写成 [], 都不符合契约("读不到给 null")
function TOPO.enc(v)
	if v == nil or v == T_NULL then return "null" end
	local t = type(v)
	if t == "boolean" then return v and "true" or "false" end
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then return "null" end
		if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return string.format("%.0f", v) end
		return string.format("%.1f", v)
	end
	if t == "string" then
		return '"' .. TOPO.u8(v):gsub('[%c"\\]', function(c)
			if c == '"' then return '\\"' elseif c == "\\" then return "\\\\"
			elseif c == "\n" then return "\\n" elseif c == "\r" then return "\\r" elseif c == "\t" then return "\\t" end
			return string.format("\\u%04x", c:byte())
		end) .. '"'
	end
	if t == "table" then
		if v.__raw then return v.__raw end
		local out = {}
		if T_ARR[v] then
			for i = 1, #v do out[#out + 1] = TOPO.enc(v[i]) end
			return "[" .. table.concat(out, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys)
		for _, k in ipairs(keys) do out[#out + 1] = TOPO.enc(tostring(k)) .. ":" .. TOPO.enc(v[k]) end
		return "{" .. table.concat(out, ",") .. "}"
	end
	return "null"
end

function TOPO.nz(v)         -- nil -> null 占位
	if v == nil then return T_NULL end
	return v
end

-- 机型: 与 router3d-data 同口径(小写, 对应 /luci-static/router3d/<model>.png)
function TOPO.model()
	local board = TOPO.rd("/tmp/sysinfo/board_name") or TOPO.rd("/proc/device-tree/model") or ""
	local id = (board:gsub("%s+$", "") .. " " .. (TOPO.rd("/tmp/sysinfo/model") or ""):gsub("%s+$", "")):lower()
	if id:find("h5000m", 1, true) then return "h5000m" end
	if id:find("n5000", 1, true) then return "n5000" end
	if id:find("tr3000", 1, true) then return "tr3000" end
	if id:find("ap3000m", 1, true) then return "ap3000m" end
	if id:find("wh3000", 1, true) then return "wh3000" end
	if id:find("q30", 1, true) then return "q30pro" end
	if id:find("e87n", 1, true) or id:find("edgepi", 1, true) then return "e87n" end
	if id:find("c5800", 1, true) then return "c5800" end   -- s201 仅 NRadio C5800: 拓扑用自己的产品图, 不再按 CPU 核数猜成 C2000
	local n = 0
	for _ in (TOPO.rd("/proc/cpuinfo") or ""):gmatch("\nprocessor") do n = n + 1 end
	if (TOPO.rd("/proc/cpuinfo") or ""):match("^processor") then n = n + 1 end
	return n >= 4 and "ultra" or "max"
end

function TOPO.hex_ip(h)     -- /proc/net/route 的小端十六进制 -> 点分
	if not h or #h ~= 8 then return "" end
	return string.format("%d.%d.%d.%d", tonumber(h:sub(7, 8), 16), tonumber(h:sub(5, 6), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(1, 2), 16))
end

-- 默认路由(metric 最小): 出口口 + 网关
function TOPO.default_route()
	local best, dev, gw = nil, "", ""
	for line in (TOPO.rd("/proc/net/route") or ""):gmatch("[^\r\n]+") do
		local ifn, dst, g, _, _, _, metric, mask = line:match("^(%S+)%s+(%x+)%s+(%x+)%s+(%x+)%s+(%S+)%s+(%S+)%s+(%d+)%s+(%x+)")
		if ifn and dst == "00000000" and mask == "00000000" then
			local m = tonumber(metric) or 0
			if not best or m < best then best, dev, gw = m, ifn, TOPO.hex_ip(g) end
		end
	end
	return dev, gw
end

-- 在线设备: 调 mwrt-clients, 原样取出 clients 数组与 counts
function TOPO.clients()
	local fs = require "nixio.fs"
	local res = { list = TOPO.arr({}), counts = { wired = 0, wifi = 0, total = 0 }, aps = {}, raw = nil }
	if not fs.access("/usr/libexec/mwrt-clients", "x") then return res end
	-- 进程内复用: loadfile 取出 run 函数直接调(0 fork); 脚本文件改了(mtime 变)才重新加载。
	-- 取不到或报错时才退回 popen(1 次 sh + 1 次 lua)。
	local raw
	local st = fs.stat("/usr/libexec/mwrt-clients")
	if st and (TOPO.mc_mtime ~= st.mtime or not TOPO.mc_fn) then
		TOPO.mc_fn, TOPO.mc_mtime = nil, st.mtime
		local chunk = loadfile("/usr/libexec/mwrt-clients")
		if chunk then
			local okc, fn = pcall(chunk, { lib = true })
			if okc and type(fn) == "function" then TOPO.mc_fn = fn end
		end
	end
	if TOPO.mc_fn then
		local okr, body = pcall(TOPO.mc_fn, false)
		if okr and type(body) == "string" and body ~= "" then raw = body end
	end
	if not raw then
		local p = io.popen("/usr/libexec/mwrt-clients 2>/dev/null")
		raw = p and p:read("*a") or ""
		if p then p:close() end
	end
	local jsonc = require "luci.jsonc"
	local d = raw ~= "" and jsonc.parse(raw) or nil
	if type(d) ~= "table" or d.ok ~= true then return res end
	-- clients 原文直接拼接(保留 null 字段); 解析失败再退回重新编码
	local a = raw:find('"clients":[', 1, true)
	local b = raw:find('],"counts":{', 1, true)
	if a and b and b > a then
		local arr = raw:sub(a + 10, b)
		if type(jsonc.parse(arr)) == "table" then res.raw = arr end
	end
	if type(d.counts) == "table" then
		res.counts = { wired = d.counts.wired or 0, wifi = d.counts.wifi or 0, total = d.counts.total or 0 }
	end
	res.aps = type(d.aps) == "table" and d.aps or {}
	res.lan_dev = d.lan_dev
	return res
end

function TOPO.prefix_bits(mask)
	local bits = 0
	for o in (mask or ""):gmatch("%d+") do
		local n = tonumber(o) or 0
		while n > 0 do bits = bits + (n % 2); n = math.floor(n / 2) end
	end
	return bits
end

function TOPO.lan(uci, aps)
	local ip = uci:get("network", "lan", "ipaddr")
	if type(ip) == "table" then ip = ip[1] end
	ip = tostring(ip or "")
	local mask = uci:get("network", "lan", "netmask")
	local bits = 24
	local ip_only, cidr = ip:match("^([%d%.]+)/(%d+)$")
	if ip_only then ip = ip_only; bits = tonumber(cidr) or 24
	elseif mask and mask ~= "" then bits = TOPO.prefix_bits(mask) end
	local r = { ip = ip, mask = bits, ssid24 = T_NULL, ssid5 = T_NULL, ch24 = T_NULL, ch5 = T_NULL, w24 = T_NULL, w5 = T_NULL }
	local seen = {}
	for _, ap in ipairs(aps or {}) do
		local key = (ap.band == "2.4G" and "24") or (ap.band == "5G" and "5") or nil
		if key and not ap.guest and not seen[key] then
			seen[key] = true
			if ap.ssid and ap.ssid ~= "" then r["ssid" .. key] = ap.ssid end
			if ap.channel then r["ch" .. key] = ap.channel end
			if ap.htmode then r["w" .. key] = ap.htmode end
		end
	end
	-- AP 没起来(读不到运行时信道)时, ssid / 带宽 / 固定信道退回 uci
	local dev_band, dev_cfg = {}, {}
	uci:foreach("wireless", "wifi-device", function(s)
		local b = tostring(s.band or ""):lower()
		dev_band[s[".name"]] = (b:match("^2") and "24") or (b:match("^5") and "5") or nil
		dev_cfg[s[".name"]] = s
	end)
	uci:foreach("wireless", "wifi-iface", function(s)
		local key = dev_band[s.device or ""]
		if key and s.mode == "ap" and s.disabled ~= "1" and not seen["u" .. key] then
			seen["u" .. key] = true
			if r["ssid" .. key] == T_NULL and s.ssid then r["ssid" .. key] = s.ssid end
			local dc = dev_cfg[s.device]
			if r["w" .. key] == T_NULL and dc and dc.htmode then r["w" .. key] = dc.htmode end
			if r["ch" .. key] == T_NULL and dc and tonumber(dc.channel) then r["ch" .. key] = tonumber(dc.channel) end
		end
	end)
	return r
end

-- ubus network.interface dump(Lua 绑定, 不 fork)
function TOPO.ifaces()
	local ok, ubus = pcall(require, "ubus")
	if not ok then return {} end
	local c = ubus.connect()
	if not c then return {} end
	local d = c:call("network.interface", "dump", {})
	c:close()
	return (d and d.interface) or {}
end

function TOPO.find_iface(list, dev, name)
	for _, i in ipairs(list) do
		if i.up and ((name and i.interface == name) or (dev and (i.l3_device == dev or i.device == dev))) then return i end
	end
end

-- 出口速率: 两次调用之间的字节差 / 时间差; 状态落 /tmp, 间隔 <1 秒复用上次结果
function TOPO.rate(dev)
	local base = "/sys/class/net/" .. dev .. "/statistics/"
	local rx, tx = TOPO.num(TOPO.rd(base .. "rx_bytes")), TOPO.num(TOPO.rd(base .. "tx_bytes"))
	if not rx or not tx then return 0, 0 end
	local up = TOPO.num((TOPO.rd("/proc/uptime") or ""):match("^([%d%.]+)")) or 0
	local path = "/tmp/.mwrt-topo-rate"
	local pd, pu, prx, ptx, prb, ptb = (TOPO.rd(path) or ""):match("^(%S+) ([%d%.]+) (%d+) (%d+) (%d+) (%d+)")
	local rb, tb = 0, 0
	if pd == dev then
		local dt = up - tonumber(pu)
		if dt >= 1 and dt <= 60 then
			rb = math.max(0, math.floor((rx - tonumber(prx)) / dt))
			tb = math.max(0, math.floor((tx - tonumber(ptx)) / dt))
		else
			rb, tb = tonumber(prb) or 0, tonumber(ptb) or 0
			if dt < 0 or dt > 60 then rb, tb = 0, 0 end
		end
		if dt < 1 and dt >= 0 then return rb, tb end   -- 采样点不动, 沿用旧值
	end
	local f = io.open(path, "w")
	if f then f:write(string.format("%s %.2f %.0f %.0f %.0f %.0f\n", dev, up, rx, tx, rb, tb)); f:close() end
	return rb, tb
end

-- 出口: kind 判定与 router3d-data 同口径, 另把 USB 网卡拆成 usbnic
function TOPO.egress(uci, ifaces)
	local fs = require "nixio.fs"
	local dev, gw = TOPO.default_route()
	local e = { kind = "none", dev = "", gw = "", ip = "", proto = "", rx_bps = 0, tx_bps = 0, rtt_ms = T_NULL }
	if dev == "" then return e, nil end
	local wandev = uci:get("network", "wan", "device") or uci:get("network", "wan", "ifname") or "eth0"
	local rec = TOPO.rd("/tmp/mwrt-usbnic.d/" .. dev:gsub("[^%w%._%-]", "_")) or ""
	local ukind = rec:match("kind=(%a+)")
	local kind
	if ukind == "tether" then kind = "tether"
	elseif ukind == "nic" then kind = "usbnic"
	elseif dev:match("^apcli") or dev:match("^wlan") then kind = "wifi"
	elseif dev:match("^pppoe%-") or dev == wandev then kind = "wired"
	else
		local ue = TOPO.rd("/sys/class/net/" .. dev .. "/uevent") or ""
		kind = ue:find("OF_NAME=mac", 1, true) and "wired" or "cell"
	end
	local i = TOPO.find_iface(ifaces, dev, nil)
	e.kind, e.dev, e.gw = kind, dev, gw
	if i then
		local a = i["ipv4-address"]
		e.ip = (a and a[1] and a[1].address) or ""
		e.proto = i.proto or ""
		if e.proto == "dhcp" and dev:match("^pppoe") then e.proto = "pppoe" end
	end
	if e.ip == "" then
		-- 没有 ubus 记录(例如手工配的口): 退回 route get 式读取不方便, 保持空串
	end
	e.rx_bps, e.tx_bps = TOPO.rate(dev)
	return e, i
end

local T_ENC2SEC = {
	none = "开放", psk2 = "WPA2-PSK", ["psk2+ccmp"] = "WPA2-PSK", psk = "WPA-PSK", ["psk-mixed"] = "WPA/WPA2-PSK",
	["psk-mixed+ccmp"] = "WPA/WPA2-PSK", sae = "WPA3-SAE", ["sae-mixed"] = "WPA2/WPA3-PSK", owe = "增强开放(OWE)",
	wep = "WEP", wpa2 = "WPA2-Enterprise", wpa3 = "WPA3-Enterprise",
}

-- 上联 WiFi(无线网桥 sta/apcli)。没配 sta 返回 nil。走 ubus iwinfo(Lua 绑定, 0 fork)。
function TOPO.uplink_wifi(uci, ifaces, egress)
	local sid
	uci:foreach("wireless", "wifi-iface", function(s)
		if s.mode == "sta" and s.disabled ~= "1" then sid = s[".name"]; return false end
	end)
	if not sid then return nil end
	local dev = uci:get("wireless", sid, "device") or ""
	local band_cfg = (uci:get("wireless", dev, "band") or ""):lower()
	local phy = uci:get("wireless", dev, "phy") or ""
	local netdev
	if phy == "ra0" then netdev = "apcli0"
	elseif phy == "rai0" then netdev = "apclii0"
	else
		local base, idx = phy:match("^(ra[ix]?)(%d+)$")
		netdev = base and (base .. "cli" .. idx) or "apcli0"
	end
	local r = { state = "down", ssid = uci:get("wireless", sid, "ssid") or "", bssid = T_NULL,
		band = (band_cfg:match("^2") and "2.4G") or (band_cfg:match("^5") and "5G") or (band_cfg:match("^6") and "6G") or T_NULL,
		channel = T_NULL, width = T_NULL, rssi = T_NULL, noise = T_NULL, snr = T_NULL, tx_rate = T_NULL, rx_rate = T_NULL,
		security = T_ENC2SEC[uci:get("wireless", sid, "encryption") or ""] or (uci:get("wireless", sid, "encryption") or T_NULL),
		iface = netdev, last_seen_s = T_NULL }
	local flags = TOPO.rd("/sys/class/net/" .. netdev .. "/flags")
	local up = flags and ((tonumber(flags:match("0x(%x+)") or "0", 16) or 0) % 2 == 1)
	if not up then return r end
	-- ubus iwinfo(Lua 绑定, 不 fork): info 给 ssid/bssid/信道/频率/htmode/信号/噪声/速率, assoclist 给对端站点的信号与收发速率
	local info, al = {}, nil
	local okb, ubus = pcall(require, "ubus")
	local conn = okb and ubus.connect() or nil
	if conn then
		local ok1, v1 = pcall(conn.call, conn, "iwinfo", "info", { device = netdev })
		local ok2, v2 = pcall(conn.call, conn, "iwinfo", "assoclist", { device = netdev })
		if ok1 and type(v1) == "table" then info = v1 end
		if ok2 and type(v2) == "table" and type(v2.results) == "table" then al = v2.results[1] end
		pcall(conn.close, conn)
	end
	local ap = type(info.bssid) == "string" and info.bssid:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") or nil
	local essid = info.ssid
	if type(essid) == "string" and essid ~= "" and essid ~= "unknown" then r.ssid = TOPO.u8(essid, 32) end
	local assoc = ap and ap:upper() ~= "00:00:00:00:00:00"
	local i = TOPO.find_iface(ifaces, netdev, nil)
	local has_ip = i and i["ipv4-address"] and i["ipv4-address"][1] ~= nil
	if assoc then
		r.bssid = ap:upper()
		r.state = has_ip and "up" or "connecting"
		r.last_seen_s = 0
		local ch = tonumber(info.channel)
		if ch then r.channel = ch end
		local g = tonumber(info.frequency)
		if g then
			g = g / 1000
			r.band = (g < 3 and "2.4G") or (g < 5.9 and "5G") or "6G"
		end
		local ht = type(info.htmode) == "string" and info.htmode or nil
		if ht then
			local w = ht:match("(%d+)$")
			r.width = w and (w .. "MHz") or "20MHz"
		end
		-- 信号 / 噪声: info 里有就用, 没有再取 assoclist 里对端(上游 AP)那一条
		local sig = tonumber(info.signal) or (al and tonumber(al.signal)) or nil
		local noi = tonumber(info.noise) or (al and tonumber(al.noise)) or nil
		if sig then r.rssi = sig end
		if noi then r.noise = noi end
		if sig and noi then r.snr = sig - noi end
		-- 速率(kbit/s -> Mbit/s): assoclist 的收发各自一个值, 没有则用 info.bitrate 同时给两个方向
		local rxr = al and type(al.rx) == "table" and tonumber(al.rx.rate) or nil
		local txr = al and type(al.tx) == "table" and tonumber(al.tx.rate) or nil
		local br = tonumber(info.bitrate)
		if br and br > 0 then rxr = rxr or br; txr = txr or br end
		if txr then r.tx_rate = math.floor(txr / 1000 + 0.5) end
		if rxr then r.rx_rate = math.floor(rxr / 1000 + 0.5) end
	else
		r.state = "connecting"
	end
	return r
end

local T_PLMN = {
	["46000"] = "中国移动", ["46002"] = "中国移动", ["46004"] = "中国移动", ["46007"] = "中国移动", ["46008"] = "中国移动",
	["46001"] = "中国联通", ["46006"] = "中国联通", ["46009"] = "中国联通",
	["46003"] = "中国电信", ["46005"] = "中国电信", ["46011"] = "中国电信",
	["46015"] = "中国广电",
}

function TOPO.rat_of(mode, cat)
	mode = tostring(mode or "")
	if mode:find("NR5G%-SA") then return "5G SA" end
	if mode:find("NR5G%-NSA") or mode:find("EN%-DC") then return "5G NSA" end
	if mode:find("NR5G") then return "5G" end
	if mode:find("LTE") then return "LTE" end
	if mode:find("WCDMA") or mode:find("UMTS") then return "3G" end
	if mode:find("GSM") or mode:find("EDGE") then return "2G" end
	if cat == "NR" then return "5G" elseif cat == "LTE" then return "LTE" end
	return T_NULL
end

-- 蜂窝: 只读已落盘缓存。没有模组返回 nil。
function TOPO.cell(uci, model, ifaces, egress, ei)
	local fs = require "nixio.fs"
	local jsonc = require "luci.jsonc"
	local modconf = (TOPO.rd("/tmp/modconf.conf") or ""):gsub("%s+$", "")
	if modconf == "" then return nil end
	-- qmodem 配置段: 段名 = modeminfo 缓存文件名后缀, option network = netifd 接口名, option path = 模组的 USB sysfs 目录
	local cfg, netif, mpath
	uci:foreach("qmodem", "modem-device", function(s)
		cfg, netif, mpath = s[".name"], s.network, s.path
		return false
	end)
	-- USB 位置与速率: 先读 qmodem 配置里的 sysfs 目录(0 fork); 读不到再退回 mwrt-usbinfo(1 次 fork,
	-- N5000 无转接板时 modconf 会残留, 以 USB 上真有 modem 为准)
	local usb_dev, usb_speed, has_mod = T_NULL, T_NULL, false
	if mpath and mpath ~= "" then
		local spd = TOPO.num(TOPO.rd((mpath:gsub("/+$", "")) .. "/speed"))
		if spd then
			has_mod = true
			usb_dev = mpath:gsub("/+$", ""):match("([^/]+)$") or T_NULL
			usb_speed = tostring(math.floor(spd))
		end
	end
	local usb_checked = false
	if not has_mod and fs.access("/usr/libexec/mwrt-usbinfo", "x") then
		usb_checked = true
		local p = io.popen("/usr/libexec/mwrt-usbinfo 2>/dev/null")
		local out = p and p:read("*a") or ""
		if p then p:close() end
		for line in out:gmatch("[^\r\n]+") do
			local bus, _, _, spd, ty = line:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|")
			if ty == "modem" then has_mod = true; usb_dev = bus; usb_speed = spd; break end
		end
	end
	-- 模组实际不在总线上(热拔后 /tmp/modconf.conf 残留)时对所有机型一视同仁返回 nil:
	-- 查过 USB 且没有 modem; 或者根本没有 qmodem 设备段(没有任何已登记的模组)
	if not has_mod and (usb_checked or not cfg) then return nil end
	local ci = jsonc.parse(TOPO.rd("/tmp/mwrt_cellinfo.json") or "")
	if type(ci) ~= "table" then ci = {} end
	local sv = type(ci.serving) == "table" and ci.serving or {}

	-- modeminfo 落盘缓存(modemCtrl 写的): 按 key 取值
	local mi, mi_age = {}, T_NULL
	if cfg then
		local raw = TOPO.rd("/tmp/run/mwrt/modem_info_" .. cfg:gsub("[^%w_%-]", "_") .. ".json")
		local c = raw and jsonc.parse(raw)
		if type(c) == "table" and type(c.modem_info) == "table" then
			for _, e in ipairs(c.modem_info) do
				if type(e) == "table" and e.key and e.value ~= nil and e.value ~= "" then mi[tostring(e.key)] = tostring(e.value) end
			end
			mi_age = os.time() - (tonumber(c.time) or 0)
		end
	end

	local mcc = sv.mcc or mi["MMC"]
	local mnc = sv.mnc or mi["MNC"]
	local plmn = (mcc and mnc) and (tostring(mcc) .. tostring(mnc)) or nil
	if not plmn and mi["IMSI"] then plmn = mi["IMSI"]:sub(1, 5) end
	local operator = plmn and T_PLMN[plmn] or T_NULL

	local ca, nr = TOPO.arr({}), (ci.rat == "NR")
	for _, c in ipairs(type(ci.ca) == "table" and ci.ca or {}) do
		if c.band then ca[#ca + 1] = ((c.rat == "NR" or (c.rat == nil and nr)) and "n" or "B") .. tostring(c.band) end
	end
	local band = ca[1] or T_NULL
	local arfcn = tonumber(sv.arfcn) or TOPO.num(mi["ARFCN"])
	local function ni(v) v = tonumber(v); if v == nil then return T_NULL end return v end

	-- 拨号: 优先 qmodem 对应的 netifd 接口(接口名=配置段名), 其次出口口
	local iface = netif and TOPO.find_iface(ifaces, nil, netif) or nil
	if not iface and egress.kind == "cell" then iface = ei end
	local dial = { state = "disconnected", ip = "", dns = "", apn = T_NULL, uptime_s = T_NULL, mtu = T_NULL, rx_bytes = T_NULL, tx_bytes = T_NULL }
	if iface then
		local a = iface["ipv4-address"]
		dial.ip = (a and a[1] and a[1].address) or ""
		local dns = iface["dns-server"]
		dial.dns = (dns and dns[1]) or ""
		dial.uptime_s = iface.uptime or T_NULL
		local dev = iface.l3_device or iface.device
		if dev then
			dial.mtu = ni(TOPO.num(TOPO.rd("/sys/class/net/" .. dev .. "/mtu")))
			dial.rx_bytes = ni(TOPO.num(TOPO.rd("/sys/class/net/" .. dev .. "/statistics/rx_bytes")))
			dial.tx_bytes = ni(TOPO.num(TOPO.rd("/sys/class/net/" .. dev .. "/statistics/tx_bytes")))
		end
		if dial.ip ~= "" then dial.state = "connected" end
	elseif cfg then
		-- 接口不在 ubus 里(down): 不能判 connected(要求接口 up 且有 IPv4)。
		-- modem_info 缓存没有年龄检查, 只有缓存足够新(<=60 秒)才认为是在拨号中, 否则按已断开
		dial.state = (type(mi_age) == "number" and mi_age >= 0 and mi_age <= 60) and "dialing" or "disconnected"
	end
	if ci.apn and ci.apn ~= "" then dial.apn = ci.apn end

	local slot = tonumber(mi["SIM Slot"])
	local simc = TOPO.rd("/tmp/simstat.cache") or ""
	local iccid = simc:match("^[^|]*|[^|]*|[^|]*|(%w+)")
	local imei = mi["IMEI"]
	return {
		present = true, operator = operator, plmn = plmn or T_NULL,
		rat = TOPO.rat_of(mi["network_mode"], ci.rat), band = band, arfcn = arfcn or T_NULL,
		pci = ni(mi["Physical Cell ID"]), cell_id = mi["Cell ID"] or sv.cid or T_NULL, tac = sv.tac or mi["TAC"] or T_NULL,
		rsrp = ni(sv.rsrp or mi["RSRP"]), rsrq = ni(sv.rsrq or mi["RSRQ"]), sinr = ni(sv.sinr or mi["SINR"]),
		ca = ca, dial = dial,
		module = {
			model = mi["name"] or modconf, vendor = mi["manufacturer"] or T_NULL, fw = mi["revision"] or T_NULL,
			usb_speed = usb_speed, usb_dev = usb_dev,
			imei_tail = imei and imei:sub(-4) or T_NULL,
		},
		sim = { slot = slot or T_NULL, state = mi["SIM Status"] or T_NULL, iccid_tail = iccid and iccid:sub(-4) or T_NULL },
		age_s = ci.ts and math.max(0, os.time() - tonumber(ci.ts)) or mi_age,
	}
end

function TOPO.usb(ifaces)
	local fs = require "nixio.fs"
	local r = { nic = T_NULL, tether = T_NULL }
	local dir = fs.dir("/tmp/mwrt-usbnic.d")
	if not dir then return r end
	for name in dir do
		local rec = TOPO.rd("/tmp/mwrt-usbnic.d/" .. name) or ""
		local kind = rec:match("kind=(%a+)")
		local function g(k) return rec:match("\n?" .. k .. "=([^\n]*)") or "" end
		if kind == "nic" and r.nic == T_NULL then
			local spd = TOPO.num(TOPO.rd("/sys/class/net/" .. name .. "/speed"))
			local nm = g("name")
			r.nic = { dev = name, vendor = (nm ~= "" and nm) or (g("vid") .. ":" .. g("pid")),
				speed_mbps = (spd and spd > 0) and spd or T_NULL, role = (g("role") ~= "" and g("role")) or "pending" }
		elseif kind == "tether" and r.tether == T_NULL then
			local drv, vid = g("drv"), g("vid"):lower()
			local k = (drv == "ipheth" or vid == "05ac") and "iphone" or ((drv == "rndis_host" or drv == "cdc_ether" or drv == "cdc_ncm") and "android" or "unknown")
			local ti = TOPO.find_iface(ifaces or {}, name, nil)
			local ta = ti and ti["ipv4-address"]
			local ip = (ta and ta[1] and ta[1].address) or ""
			r.tether = { dev = name, kind = k, ip = ip }
		end
	end
	return r
end

function TOPO.ports(uci)
	local fs = require "nixio.fs"
	local wandev = uci:get("network", "wan", "device") or uci:get("network", "wan", "ifname") or "eth0"
	local names = {}
	local out = TOPO.arr({})
	-- s201 仅 NRadio C5800: 四个网口是交换机 DSA 口 lan1-4(不是 ethN), 照实列出, WAN 角色看 network.wan.device
	if _is_c5800() then
		for _, n in ipairs({ "lan1", "lan2", "lan3", "lan4" }) do
			if fs.access("/sys/class/net/" .. n) then
				local car = eth_carrier(n)
				local spd = car and TOPO.num(TOPO.rd("/sys/class/net/" .. n .. "/speed")) or nil
				out[#out + 1] = { name = n, role = (n == wandev) and "WAN" or "LAN", up = car,
					speed = (spd and spd > 0) and spd or T_NULL }
			end
		end
		return out
	end
	for n in (fs.dir("/sys/class/net") or function() end) do
		if n:match("^eth%d+$") then names[#names + 1] = n end
	end
	table.sort(names)
	for _, n in ipairs(names) do
		local base = "/sys/class/net/" .. n
		local ue = TOPO.rd(base .. "/uevent") or ""
		-- 只收物理真实网口: 设备树 GMAC 且绑了 PHY(与 router3d-data 同判据)
		if ue:find("OF_NAME=mac", 1, true) and fs.access(base .. "/phydev") then
			local car = eth_carrier(n)
			local spd = car and TOPO.num(TOPO.rd(base .. "/speed")) or nil
			out[#out + 1] = { name = n, role = (n == wandev) and "WAN" or "LAN", up = car,
				speed = (spd and spd > 0) and spd or T_NULL }
		end
	end
	return out
end

-- s201 NRadio C5800 only: 外接 AK68(LAN4 口, 里面是 MT5700 / RM520N)已接入且出口就走 LAN4 时, 返回 AK68 信息, 其余一律 nil。
-- 此时上网用的是 AK68 里的蜂窝, 拓扑不能画成"有线宽带 / 上级路由器", 要画成"互联网 - 基站 - AK68 - 本设备"。
function TOPO.ak68(eg)
	if not _is_c5800() or eg.kind ~= "wired" or eg.dev ~= "lan4" then return nil end
	local ok, j = pcall(function() return require("luci.jsonc").parse(TOPO.rd("/tmp/mwrt-ak68.json") or "") end)
	if not ok or type(j) ~= "table" or tonumber(j.present) ~= 1 then return nil end
	return { port = "LAN4", kind = tostring(j.kind or ""), gw = tostring(j.gw or eg.gw or ""),
		poe = (tonumber(j.poe) == 1) and 1 or 0, atsd = (tonumber(j.atsd) == 1) and 1 or 0 }
end

function action_topo_data()
	local uci = require "luci.model.uci".cursor()
	local cl = TOPO.clients()
	local ifaces = TOPO.ifaces()
	local model = TOPO.model()
	local eg, ei = TOPO.egress(uci, ifaces)
	local ak68 = TOPO.ak68(eg)
	if ak68 then eg.kind = "cell" end   -- 出口按蜂窝算(经 AK68), 下面 TOPO.cell 才会取 lan4 的拨号信息
	local rv = {
		ok = true, v = 1, now = os.time(), model = model,
		lan = TOPO.lan(uci, cl.aps),
		egress = eg,
		uplink_wifi = TOPO.nz(TOPO.uplink_wifi(uci, ifaces, eg)),
		cell = TOPO.nz(TOPO.cell(uci, model, ifaces, eg, ei)),
		usb = TOPO.usb(ifaces),
		ports = TOPO.ports(uci),
		clients = cl.raw and { __raw = cl.raw } or TOPO.arr({}),
		counts = cl.counts,
	}
	-- 蜂窝以外的出口, 如果是手机共享, 把 tether 的 IP 补上(出口口就是它)
	if eg.kind == "tether" and type(rv.usb.tether) == "table" and rv.usb.tether.dev == eg.dev then rv.usb.tether.ip = eg.ip end
	-- s201 AK68: 模组在 AK68 里, 本机没有它的 USB 信息(缓存里残留的是内置模组的), 置空免得误导
	if ak68 then
		rv.ak68 = ak68
		if type(rv.cell) == "table" and type(rv.cell.module) == "table" then
			rv.cell.module.usb_speed, rv.cell.module.usb_dev = T_NULL, T_NULL
		end
	end
	luci.http.prepare_content("application/json")
	luci.http.write(TOPO.enc(rv))
end

-- 插件菜单是否已解锁: 与 openclash / passwall / shadowsocks 控制器 index() 里的判据完全一致
-- (readfile("/etc/config/Outofnetwork") 以 "ok" 开头, 由 fancontrol.lua action_Outofnetwork 认证成功后写入)。
function action_unlock_state()
	local v = (require("nixio.fs").readfile("/etc/config/Outofnetwork") or ""):match("^ok") ~= nil
	luci.http.prepare_content("application/json")
	luci.http.write(v and '{"ok":true,"unlocked":true}' or '{"ok":true,"unlocked":false}')
end

-- ===================== s101: 5700 通话 / 来电 / 短信通知 =====================
-- 读接口只读 /tmp/mwrt-phone/state.json 与 events,绝不碰串口。
-- 写接口(拨号/接听/挂断)只把已校验的参数交给 /usr/bin/mwrt-phone-ctl,由它构造 AT 并经 sendat 发出;
-- 本文件不拼 AT、不复用 send_atcmd。
local PHONE_DIR = "/tmp/mwrt-phone"

local function phone_reply(code, tbl)
	luci.http.status(code, code == 200 and "OK" or "Error")
	luci.http.header("Cache-Control", "no-store")
	luci.http.prepare_content("application/json")
	luci.http.write(require("luci.jsonc").stringify(tbl))
end

local function phone_fail(code, err, msg)
	phone_reply(code, { ok = false, err = err, msg = msg })
end

-- 在场判据与 footer.ut / mwrt-phoned / mwrt-phone-ctl 同一套: modconf 含 5700 且 sysfs 有 idVendor=3466
local function phone_present()
	local fs = require "nixio.fs"
	local mc = (fs.readfile("/tmp/modconf.conf", 128) or ""):lower()
	if not mc:find("5700", 1, true) then return false end
	local it = fs.dir("/sys/bus/usb/devices")
	if not it then return false end
	for name in it do
		local v = fs.readfile("/sys/bus/usb/devices/" .. name .. "/idVendor", 16)
		if v and (v:gsub("%s+", "")) == "3466" then return true end
	end
	return false
end

-- 直接读 /etc/config/mwrt 文本(小文件),不走 uci cursor(cursor 在常驻进程里会缓存旧值)。缺省视为开启。
local function phone_enabled()
	local txt = require("nixio.fs").readfile("/etc/config/mwrt", 65536) or ""
	local v = txt:match("option%s+phoneen%s+['\"]?([^'\"%s]*)")
	return v ~= "0"
end

local function phone_read_state()
	local raw = require("nixio.fs").readfile(PHONE_DIR .. "/state.json", 8192)
	if not raw then return nil end
	local st = require("luci.jsonc").parse(raw)
	if type(st) ~= "table" or type(st.call) ~= "table" then return nil end
	return st
end

local PHONE_EMERG = { "110", "112", "119", "120", "122", "911", "999", "000" }

-- 紧急号码与常见短号: 本身,或去掉 + 与 1~3 位国家码后的同号
local function phone_emergency(n)
	local d = (n:gsub("^%+", ""))
	for _, e in ipairs(PHONE_EMERG) do
		if d == e then return true end
		local extra = #d - #e
		if extra >= 1 and extra <= 3 and d:sub(-#e) == e then return true end
	end
	return false
end

function action_phone_state()
	local fs = require "nixio.fs"
	local jsonc = require "luci.jsonc"
	local http = luci.http

	if not phone_present() then
		return phone_reply(200, { ok = true, supported = false, reason = "not5700" })
	end
	if not phone_enabled() then
		return phone_reply(200, { ok = true, supported = false, reason = "disabled" })
	end
	-- 页面在看: 给守护一个心跳(只有 mtime 有意义)。hidden=1(后台标签)不续。
	if http.formvalue("hidden") ~= "1" then
		fs.mkdirr(PHONE_DIR)
		fs.writefile(PHONE_DIR .. "/seen", "")
	end
	local st = phone_read_state()
	if not st or st.supported == false then
		return phone_reply(200, { ok = true, supported = false, reason = st and "not5700" or "nodaemon" })
	end

	local now = os.time()
	local age = math.max(0, now - (tonumber(st.ts) or 0))
	local body = {
		ok = true, supported = true, enabled = true,
		age = age, stale = age > 20,
		fake = st.fake, gen = st.gen, seq = st.seq, health = st.health, ims = st.ims,
		cfg = st.cfg, call = st.call, sms = st.sms,
	}

	-- 事件: 仅当 gen 一致且带 since 才回放; 否则只返回 seq,由前端落基线
	local evs = {}
	local since = tonumber(http.formvalue("since") or "")
	if since and http.formvalue("gen") == st.gen then
		local raw = fs.readfile(PHONE_DIR .. "/events", 65536) or ""
		for line in raw:gmatch("[^\n]+") do
			local ev = jsonc.parse(line)
			if type(ev) == "table" and tonumber(ev.id) and ev.id > since then
				ev.age = math.max(0, now - (tonumber(ev.ts) or now))
				evs[#evs + 1] = jsonc.stringify(ev)
			end
		end
		while #evs > 20 do table.remove(evs, 1) end
	end

	-- events 必须是 JSON 数组(空也是 []),手工拼接最稳
	local out = jsonc.stringify(body)
	out = out:sub(1, -2) .. ',"events":[' .. table.concat(evs, ",") .. "]}"
	http.status(200, "OK")
	http.header("Cache-Control", "no-store")
	http.prepare_content("application/json")
	http.write(out)
end

local function phone_write(verb, number)
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end      -- 要求 POST + token,不通过它自己回 405/403
	local util = require "luci.util"
	local jsonc = require "luci.jsonc"

	if not phone_present() then return phone_fail(503, "not5700", "未检测到 5700 模组") end
	if not phone_enabled() then return phone_fail(503, "disabled", "通话功能已关闭") end

	if verb == "dial" then
		local digits = type(number) == "string" and number:match("^%+?(%d+)$") or nil
		if not digits or #digits < 3 or #digits > 20 then
			return phone_fail(400, "bad_number", "号码格式不正确(仅支持 3~20 位数字,可带开头的 +)")
		end
		if phone_emergency(number) then
			return phone_fail(400, "emergency_blocked", "不支持拨打紧急号码或短号")
		end
	end

	local st = phone_read_state()
	if not st or math.abs(os.time() - (tonumber(st.ts) or 0)) > 20 then
		return phone_fail(503, "daemon_down", "通话守护进程未运行或无响应")
	end

	-- 审计日志: 号码只留末 4 位 + 来源 IP
	local ip = luci.http.getenv("REMOTE_ADDR") or "?"
	local tail = (verb == "dial") and (" ****" .. number:sub(-4)) or ""
	os.execute("logger -t mwrt-phone " .. util.shellquote("api " .. verb .. tail .. " from " .. ip) .. " 2>/dev/null")

	local cmd = "/usr/bin/mwrt-phone-ctl " .. verb
	if verb == "dial" then cmd = cmd .. " " .. util.shellquote(number) end
	local pipe = io.popen(cmd .. " 2>/dev/null", "r")
	local out = pipe and pipe:read("*a") or ""
	if pipe then pipe:close() end
	local res = jsonc.parse(out)
	if type(res) ~= "table" then
		return phone_fail(500, "ctl_failed", "通话控制工具没有返回结果")
	end
	if res.ok == false then
		local code = tonumber(res.http) or 500
		res.http = nil
		return phone_reply(code, res)
	end
	return phone_reply(200, res)
end

function action_phone_dial()
	phone_write("dial", luci.http.formvalue("number"))
end

function action_phone_answer()
	phone_write("answer")
end

function action_phone_hangup()
	phone_write("hangup")
end
-- =================== s101 end ===================

-- =================== s105: 通知已读 ===================
-- 短信 / 未接来电通知中心的「已读」写入口。POST + CSRF token(dispatcher 在 post(...) 注册处核对: 非 POST 回 405, token 不对回 403)。
-- 参数(二选一):
--   ids    卡片 id 列表, 逗号分隔, 最多 50 个, 每个必须是 sms-<数字>-<数字> / miss-<数字>-<数字>
--   scope  sms | miss | all        把 events 里当前所有该类事件标为已读; 可再带 upto=<数字>: 只标事件序号 <= upto 的
--          sms_older | older       汇总卡 ×: 只标比 keep 里最老一张还老的未读事件(sms_older 只短信, older 短信 + 未接来电);
--                                  必须带 keep=<已显示的卡片 id 列表, 逗号分隔, 最多 10 个>
-- 真正写文件的是 /usr/libexec/mwrt-notice-ack.uc(flock 串行、原子压缩), 这里只做严格校验后把参数逐个 shellquote 传过去。
local function ack_key_ok(k)
	if type(k) ~= "string" or #k > 40 then return false end
	local evid, ts = k:match("^sms%-(%d+)%-(%d+)$")
	if not evid then evid, ts = k:match("^miss%-(%d+)%-(%d+)$") end
	return evid ~= nil and #evid <= 10 and #ts <= 12
end

local function ack_keys(raw, max)
	if type(raw) ~= "string" or raw == "" or #raw > 45 * max + 8 then return nil end
	local list = {}
	for k in (raw .. ","):gmatch("([^,]*),") do
		if not ack_key_ok(k) then return nil end
		list[#list + 1] = k
		if #list > max then return nil end
	end
	if #list == 0 then return nil end
	return list
end

function action_notice_ack()
	local dsp = require "luci.dispatcher"
	if not dsp.test_post_security() then return end      -- 双保险: 非 POST / token 不对直接结束(post(...) 注册本身也会核对)
	local util = require "luci.util"
	local jsonc = require "luci.jsonc"
	local http = luci.http

	local ids = http.formvalue("ids")
	local scope = http.formvalue("scope")
	local args

	if ids ~= nil and scope == nil then
		local list = ack_keys(ids, 50)
		if not list then return phone_reply(400, { ok = false, err = "bad_ids", msg = "消息编号不合法" }) end
		args = { "ids" }
		for _, k in ipairs(list) do args[#args + 1] = util.shellquote(k) end
	elseif scope ~= nil and ids == nil then
		local allowed = { sms = true, miss = true, all = true, sms_older = true, older = true }
		if not allowed[scope] then return phone_reply(400, { ok = false, err = "bad_scope", msg = "范围不合法" }) end
		local upto = http.formvalue("upto")
		local keep = http.formvalue("keep")
		args = { "scope", scope }
		if scope == "sms_older" or scope == "older" then
			if upto ~= nil then return phone_reply(400, { ok = false, err = "bad_args", msg = "参数不合法" }) end
			local list = ack_keys(keep, 10)
			if not list then return phone_reply(400, { ok = false, err = "bad_keep", msg = "已显示的消息编号不合法" }) end
			args[#args + 1] = "keep=" .. table.concat(list, ",")
		else
			if keep ~= nil then return phone_reply(400, { ok = false, err = "bad_args", msg = "参数不合法" }) end
			if upto ~= nil then
				if not upto:match("^%d+$") or #upto > 10 then
					return phone_reply(400, { ok = false, err = "bad_upto", msg = "序号不合法" })
				end
				args[#args + 1] = "upto=" .. upto
			end
		end
		-- 上面每一项都已通过白名单 / 数字 / 键格式校验, 仍统一过 shellquote
		for i = 2, #args do args[i] = util.shellquote(args[i]) end
	else
		return phone_reply(400, { ok = false, err = "bad_args", msg = "需要 ids 或 scope 之一" })
	end

	local pipe = io.popen("/usr/bin/ucode /usr/libexec/mwrt-notice-ack.uc " .. table.concat(args, " ") .. " 2>/dev/null", "r")
	local out = pipe and pipe:read("*a") or ""
	if pipe then pipe:close() end
	local res = jsonc.parse(out)
	if type(res) ~= "table" or res.ok ~= true then
		return phone_reply(500, { ok = false, err = "ack_failed", msg = (type(res) == "table" and res.error) or "写入已读记录失败" })
	end
	return phone_reply(200, { ok = true, added = tonumber(res.added) or 0 })
end
-- =================== s105 end ===================
