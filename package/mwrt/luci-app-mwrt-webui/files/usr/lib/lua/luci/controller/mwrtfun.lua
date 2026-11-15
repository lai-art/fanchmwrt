module("luci.controller.mwrtfun", package.seeall)

-- 趣玩中心：一级菜单 + 子菜单由更新服务器下发，设备把结果缓存在 /tmp/mwrt-fun/fun.json，
-- 本控制器的 index() 读这份缓存动态生成菜单（缓存没有/服务器关闭 => 不生成，菜单不出现）。
-- 缓存由 /usr/libexec/mwrt-fun 维护：开机联网查一次、之后每天一次、侧栏 funny 按钮手动拉；
-- 缓存一变它就清 LuCI 的菜单索引缓存，下一次请求才会重新跑本文件的 index()。

local FUN = "/tmp/mwrt-fun/fun.json"
local BIN = "/usr/libexec/mwrt-fun"

-- 总开关：uci mwrt.@ndis[0].funen（「Mwrt设定 -> 界面与趣玩」），默认关，没有这个选项等同关闭。
-- 必须走 uci 命令行问文件：uhttpd 里 luci.model.uci 的 cursor 是跨请求单例，带着旧缓存，
-- 刚保存完开关再来重建菜单索引时会读到旧值。index() 只在菜单索引缓存失效时才跑，多一次 popen 不碍事。
local function fun_on()
	local p = io.popen("uci -q get 'mwrt.@ndis[0].funen' 2>/dev/null")
	local v = p and p:read("*l") or ""
	if p then p:close() end
	return v == "1"
end

local function load_items()
	local f = io.open(FUN, "r")
	if not f then return nil end
	local s = f:read("*a") or ""
	f:close()
	local d = require("luci.jsonc").parse(s)
	if type(d) ~= "table" or d.enabled ~= true or type(d.items) ~= "table" then
		return nil
	end
	return d.items
end

function index()
	-- 开关关着就不建 admin/fun 菜单（即使 /tmp 里还有旧缓存）；关开关时 mwrt-fun 会清缓存和菜单索引
	local items = fun_on() and load_items() or nil
	if items and #items > 0 then
		entry({"admin", "fun"}, firstchild(), _("趣玩中心"), 26).dependent = false
		for i, it in ipairs(items) do
			if type(it.id) == "string" and it.id:match("^f%x%x%x%x%x%x$")
					and type(it.name) == "string" then
				entry({"admin", "fun", it.id}, call("action_page", it.id), it.name, i).dependent = false
			end
		end
	end

	-- funny 按钮 / 服务器配置页用的接口（始终存在：refresh 在开关关闭时由 mwrt-fun 回 disabled，
	-- probe 是服务器配置页的“测试连接”，趣玩关闭后也要能用）
	entry({"admin", "mwrtfun", "refresh"}, call("action_refresh"))
	entry({"admin", "mwrtfun", "probe"}, call("action_probe"))
	entry({"admin", "mwrtfun", "go"}, call("action_go"))
end

function action_page(id)
	local items = load_items() or {}
	local it
	for _, x in ipairs(items) do
		if x.id == id then it = x break end
	end
	if not it then
		-- 菜单已撤（服务器关闭/已删除），回到首页
		luci.http.redirect(luci.dispatcher.build_url("admin/modeminfo"))
		return
	end
	-- 真实网址不进页面源码：页面只拿到 id 和一个本机跳转地址，网址由 action_go 现跳。
	-- 内嵌前的几项检查（网址有效/同源/混合内容）也在这里做完，只把结论交给页面。
	local url = type(it.url) == "string" and it.url or ""
	local scheme, auth = url:match("^(https?)://([^/?#]+)")
	local state = "ok"
	if not scheme or auth:find("@", 1, true) then
		state = "bad"
	else
		local function norm(a, sch)
			a = a:lower()
			if sch == "http" then a = a:gsub(":80$", "") else a = a:gsub(":443$", "") end
			return a
		end
		local https = luci.http.getenv("HTTPS") == "on"
		local host = luci.http.getenv("HTTP_HOST") or ""
		if norm(auth, scheme) == norm(host, https and "https" or "http") then
			state = "same"
		elseif https and scheme == "http" then
			state = "mixed"
		end
	end
	luci.template.render("zmode/fun", {
		item = { id = it.id, name = it.name, mode = it.mode },
		state = state,
		gourl = luci.dispatcher.build_url("admin", "mwrtfun", "go") .. "?id=" .. it.id,
	})
end

-- 现跳到子菜单的真实网址（内嵌 iframe 和“在新窗口打开”都走这里）。
-- 只给已登录会话用（admin 子树自带鉴权），id 严格校验，网址以设备缓存里校验过的为准。
function action_go()
	local id = luci.http.formvalue("id") or ""
	if not id:match("^f%x%x%x%x%x%x$") then
		luci.http.status(404, "Not Found")
		return
	end
	for _, x in ipairs(load_items() or {}) do
		if x.id == id and type(x.url) == "string" and x.url:match("^https?://") then
			luci.http.header("Referrer-Policy", "no-referrer")
			luci.http.redirect(x.url)
			return
		end
	end
	luci.http.status(404, "Not Found")
end

-- 只接 POST + CSRF token；脚本自己做 30 秒间隔限频，这里不信任前端
local function post_only()
	if luci.http.getenv("REQUEST_METHOD") ~= "POST" then
		luci.http.status(405, "Method Not Allowed")
		luci.http.prepare_content("application/json")
		luci.http.write('{"ok":false,"error":"method"}')
		return false
	end
	return require("luci.dispatcher").test_post_security()
end

local function run_json(cmd)
	local p = io.popen(cmd .. " 2>/dev/null")
	local out = p and p:read("*a") or ""
	if p then p:close() end
	if out ~= "" and require("luci.jsonc").parse(out) then return out end
	return '{"ok":false,"error":"internal"}'
end

function action_refresh()
	if not post_only() then return end
	luci.http.prepare_content("application/json")
	luci.http.write(run_json(BIN .. " manual"))
end

-- 测试某个服务器地址能不能连上并通过证书校验（Mwrt服务器配置页的“测试连接”）
function action_probe()
	if not post_only() then return end
	luci.http.prepare_content("application/json")
	local host = luci.http.formvalue("host") or ""
	-- 只放过 域名/IPv4/IPv6 字符，拼进命令前再卡一道，不留任何引号和空白
	host = host:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^[Hh][Tt][Tt][Pp][Ss]://", ""):gsub("/+$", "")
	if host == "" or #host > 253 or not host:match("^[%w%.%-:%[%]_]+$") then
		luci.http.write('{"ok":false,"error":"bad_server"}')
		return
	end
	luci.http.write(run_json(BIN .. " probe 'https://" .. host .. "'"))
end
