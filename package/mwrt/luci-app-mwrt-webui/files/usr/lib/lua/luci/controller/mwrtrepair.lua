module("luci.controller.mwrtrepair", package.seeall)

-- 故障报修(s152)：「Mwrt设定 -> 故障报修」页签的后端接口。
-- 真正干活的是 /usr/libexec/mwrt-repair(生成报修码、拉起/停止 frpc)；
-- 这里只做 POST + CSRF 校验，再把脚本输出的 JSON 原样交回页面。
-- 注册在 admin 子树下，自带登录鉴权；脚本参数写死，不接收任何前端输入。
--
-- 在线聊天(s154)：聊天 worker 由脚本常驻，消息落在 /tmp/mwrt-repair/chat.* 里，
-- 这里的 chat 接口纯读本地文件(毫秒级)；chat_send 的文本只走管道标准输入交给脚本，
-- 不进命令行；cid / id 严格白名单校验。

local BIN = "/usr/libexec/mwrt-repair"
local RUN = "/tmp/mwrt-repair"
local STATE_FILE = "/etc/mwrt-repair/state"
local CHAT_MAX = 200      -- 单次最多回给页面的消息条数
local TEXT_MAX_BYTES = 4096
local TEXT_MAX_CHARS = 500
local LINK_FRESH = 60     -- chat.poll 多少秒内被刷新过，算 worker 在线

function index()
	entry({"admin", "mwrtrepair", "status"}, call("action_status")).dependent = false
	entry({"admin", "mwrtrepair", "apply"}, call("action_apply")).dependent = false
	entry({"admin", "mwrtrepair", "stop"}, call("action_stop")).dependent = false
	entry({"admin", "mwrtrepair", "chat"}, call("action_chat")).dependent = false
	entry({"admin", "mwrtrepair", "chat_send"}, call("action_chat_send")).dependent = false
	entry({"admin", "mwrtrepair", "chat_ack"}, call("action_chat_ack")).dependent = false
end

local function reply(s)
	luci.http.prepare_content("application/json")
	luci.http.header("Cache-Control", "no-store")
	luci.http.write(s)
end

local function run(arg)
	local p = io.popen(BIN .. " " .. arg .. " 2>/dev/null")
	local out = p and p:read("*a") or ""
	if p then p:close() end
	out = out:gsub("%s+$", "")
	if out == "" then out = '{"ok":false,"error":"nobin"}' end
	return out
end

-- 只接 POST + CSRF token(状态查询是只读的，GET 就行)
local function post_only()
	if luci.http.getenv("REQUEST_METHOD") ~= "POST" then
		luci.http.status(405, "Method Not Allowed")
		reply('{"ok":false,"error":"method"}')
		return false
	end
	return require("luci.dispatcher").test_post_security()
end

function action_status()
	reply(run("status"))
end

function action_apply()
	if not post_only() then return end
	reply(run("apply"))
end

function action_stop()
	if not post_only() then return end
	reply(run("stop"))
end

-- ---- 在线聊天(s154) ----------------------------------------------------------
-- 下面这组纯函数不碰文件、不碰 luci，挂在 core 表里便于单独审阅和本机测试
-- (decode 由调用方传入，线上是 luci.jsonc.parse)。
local core = {}

-- JSON 字符串转义(不用 jsonc.stringify：Lua 空表会被写成 {} 而不是 []，数字也可能带小数点)
local ESC = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r',
              ['\t'] = '\\t', ['\b'] = '\\b', ['\f'] = '\\f' }
function core.jstr(s)
	s = tostring(s == nil and "" or s)
	s = s:gsub('[%c"\\]', function(c)
		return ESC[c] or string.format("\\u%04x", c:byte())
	end)
	return '"' .. s .. '"'
end

local SIDES = { dev = true, adm = true, sys = true }

local function to_int(v)
	v = tonumber(v)
	if not v or v ~= v or v < 0 or v > 2147483647 then return nil end
	return math.floor(v)
end

function core.msg_json(m)
	return string.format('{"id":%d,"ts":%d,"side":%s,"text":%s,"cid":%s}',
		m.id, m.ts, core.jstr(m.side), core.jstr(m.text), core.jstr(m.cid))
end

-- 解析 chat.jsonl：每行是一次 poll 的完整响应，msgs 里是那次新到的消息。
-- 按 id 去重(重复拉取/截断重放都不会重复)，只留 id > since，升序，最多 CHAT_MAX 条。
-- 返回 消息数组, 本次最大 id(没有则等于 since)。坏行(半截写入/乱码)直接跳过。
function core.parse_spool(text, since, decode)
	since = to_int(since) or 0
	local seen, list = {}, {}
	for line in tostring(text or ""):gmatch("[^\n]+") do
		local obj = decode(line)
		local msgs = type(obj) == "table" and obj.msgs
		if type(msgs) == "table" then
			for _, m in ipairs(msgs) do
				if type(m) == "table" then
					local id = to_int(m.id)
					if id and id > since and id > 0 and not seen[id]
					   and SIDES[m.side] and type(m.text) == "string" then
						seen[id] = true
						list[#list + 1] = {
							id = id, ts = to_int(m.ts) or 0, side = m.side, text = m.text,
							cid = type(m.cid) == "string" and m.cid or ""
						}
					end
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.id < b.id end)
	while #list > CHAT_MAX do list[#list] = nil end
	local last = since
	if #list > 0 then last = list[#list].id end
	return list, last
end

-- 解析 chat.poll(worker 最近一次拿到的服务器响应)，只取对端在线/已读/状态
function core.parse_poll(text, decode)
	local r = { ok = false, state = "", peer_online = false, peer_read = 0, ver_ok = false }
	local obj = decode(tostring(text or ""))
	if type(obj) ~= "table" or obj.ok ~= true then return r end
	r.ok = true
	if obj.state == "approved" or obj.state == "pending" or obj.state == "ended" then
		r.state = obj.state
	end
	r.peer_online = (obj.peer_online == true)
	r.peer_read = to_int(obj.peer_read) or 0
	r.ver_ok = (type(obj.ver) == "string" and obj.ver ~= "")
	return r
end

-- 读 /etc/mwrt-repair/state：返回 8 位报修码 与 是否仍有效(未过期)
function core.parse_state(text, now)
	text = "\n" .. tostring(text or "")
	local code = text:match("\ncode=([A-Z0-9]+)")
	local exp = tonumber(text:match("\nexp=(%d+)"))
	if not code or #code ~= 8 or not exp then return nil, false end
	return code, exp > now
end

-- 页面要的会话状态：none(没申请过) / pending(等放行) / approved(可聊天) / ended(已结束，历史只读)
function core.derive_state(active, poll_state, has_history)
	if active then
		if poll_state == "approved" or poll_state == "ended" then return poll_state end
		return "pending"
	end
	if has_history or poll_state ~= "" then return "ended" end
	return "none"
end

function core.valid_cid(s)
	return type(s) == "string" and #s >= 8 and #s <= 32 and s:find("^[A-Za-z0-9_-]+$") ~= nil
end

-- 校验聊天文本：返回清理后的文本，或 nil + 错误码(empty / toolong)。
-- 只做廉价的前置拦截，规则以服务器为准(服务器还会再 strip、限 12 行)。
function core.clean_text(s)
	if type(s) ~= "string" then return nil, "empty" end
	s = s:gsub("%z", "")
	if #s > TEXT_MAX_BYTES then return nil, "toolong" end
	if not s:find("%S") then return nil, "empty" end
	local _, n = s:gsub("[^\128-\191]", "")
	if n > TEXT_MAX_CHARS + 200 then return nil, "toolong" end  -- 首尾空白留余量，精确判断交给服务器
	return s
end

-- 正整数(已读回执的消息 id)：只接纯数字，最多 10 位且不带前导零
function core.valid_id(s)
	if type(s) ~= "string" or not s:find("^[1-9]%d*$") or #s > 10 then return nil end
	return to_int(s)
end

_chat_core = core   -- 仅供本机单元测试引用

-- tail=true：文件超过 maxbytes 时读最后 maxbytes 字节(聊天 spool 只增不减，新消息在文件尾)，
-- 并丢掉被截断的半行，保证每行都是完整的 JSON。其余小文件仍读开头。
local function readfile(path, maxbytes, tail)
	local f = io.open(path, "rb")
	if not f then return nil end
	local lim = maxbytes or 524288
	local cut = false
	if tail then
		local size = f:seek("end")
		if size and size > lim then
			f:seek("set", size - lim)
			cut = true
		else
			f:seek("set", 0)
		end
	end
	local d = f:read(lim)
	f:close()
	if cut and d then
		local nl = d:find("\n", 1, true)
		d = nl and d:sub(nl + 1) or ""
	end
	return d
end

local function file_age(path)
	local ok, fs = pcall(require, "nixio.fs")
	if not ok then return nil end
	local mt = fs.stat(path, "mtime")
	if not mt then return nil end
	return os.time() - mt
end

local function fmt_code(code)
	return code and (code:sub(1, 4) .. "-" .. code:sub(5, 8)) or ""
end

-- GET chat?since=N：纯读本地 spool，毫秒级
function action_chat()
	local jsonc = require("luci.jsonc")
	local since = to_int(luci.http.formvalue("since")) or 0
	local spool = readfile(RUN .. "/chat.jsonl", nil, true)
	local msgs, last = core.parse_spool(spool, since, jsonc.parse)
	local pollraw = readfile(RUN .. "/chat.poll")
	local poll = core.parse_poll(pollraw, jsonc.parse)
	local code, active = core.parse_state(readfile(STATE_FILE, 4096), os.time())
	local age = pollraw and file_age(RUN .. "/chat.poll") or nil
	local link = active and poll.ok and poll.state == "approved" and age ~= nil and age <= LINK_FRESH
	local state = core.derive_state(active, poll.state, spool ~= nil or pollraw ~= nil)
	local parts = {}
	for i, m in ipairs(msgs) do parts[i] = core.msg_json(m) end
	reply(string.format(
		'{"ok":true,"msgs":[%s],"last":%d,"peer_online":%s,"peer_read":%d,"state":"%s","ver_ok":%s,"link":%s,"active":%s,"code":%s}',
		table.concat(parts, ","), last, tostring(link and poll.peer_online or false), poll.peer_read,
		state, tostring(poll.ver_ok), tostring(link and true or false), tostring(active and true or false),
		core.jstr(active and fmt_code(code) or "")))
end

-- POST chat_send：text / cid(表单)。文本只经管道标准输入交给脚本，脚本输出写到临时文件再读回
-- (popen 只能单向；不重定向的话脚本的输出会混进 CGI 响应)。命令行里只出现白名单校验过的 cid。
function action_chat_send()
	if not post_only() then return end
	local cid = luci.http.formvalue("cid")
	if not core.valid_cid(cid) then
		reply('{"ok":false,"error":"cid"}')
		return
	end
	local text, err = core.clean_text(luci.http.formvalue("text"))
	if not text then
		reply('{"ok":false,"error":"' .. err .. '"}')
		return
	end
	local ok, fs = pcall(require, "nixio.fs")
	if ok then pcall(fs.mkdir, RUN, "700") end
	local outf = RUN .. "/send." .. cid .. ".out"
	os.remove(outf)
	local p = io.popen(BIN .. " chat-send " .. cid .. " >" .. outf .. " 2>/dev/null", "w")
	if p then
		pcall(p.write, p, text)
		p:close()
	end
	local out = readfile(outf, 8192) or ""
	os.remove(outf)
	out = out:gsub("%s+$", "")
	if out:sub(1, 1) ~= "{" then out = '{"ok":false,"error":"nobin"}' end
	reply(out)
end

-- POST chat_ack：id(表单，纯数字)
function action_chat_ack()
	if not post_only() then return end
	local id = core.valid_id(luci.http.formvalue("id"))
	if not id then
		reply('{"ok":false,"error":"id"}')
		return
	end
	reply(run("chat-ack " .. string.format("%d", id)))
end
