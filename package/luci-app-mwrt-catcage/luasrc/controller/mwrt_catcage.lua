-- luci-app-mwrt-catcage —— 侧栏「笼中猫」破笼动画的后端
--
-- 前端三个脚本由 footer.ut 全局注入（见仓库 feeds_patches/luci 下的 footer.ut）：
--   mwrt-cat-art.js  美术库，纯绘图，无网络
--   mwrt-catcage.js  笼中猫互动动画，读 data-state 判断解锁状态
--   mwrt-unlock.js   解锁认证框，POST 到 data-url
--
-- 本文件只提供两个极简接口：
--   admin/Outofnetwork          破笼后写本地解锁标志（POST + CSRF token）
--   admin/modem/unlock_state    查询是否已解锁（GET，JSON）
--
-- 去作者服务器依赖说明：
--   原固件在这里把口令发给作者的更新服务器做联网核验。本实现已移除此远程校验，
--   改为纯本地解锁——直接写 /etc/config/Outofnetwork="ok" 即视为已解锁。
--   全程不向任何外部服务器发起请求，也不需要作者授权码；破笼动画照常播放。

module("luci.controller.mwrt_catcage", package.seeall)

local http = require "luci.http"
local fs = require "nixio.fs"

local UNLOCK_FILE = "/etc/config/Outofnetwork"

function index()
	-- 解锁动作：前端 mwrt-unlock.js 的 data-url 指向这里
	entry({"admin", "Outofnetwork"}, call("action_Outofnetwork"))
	-- 解锁状态：前端 mwrt-catcage.js 的 data-state 指向这里
	entry({"admin", "modem", "unlock_state"}, call("action_unlock_state")).leaf = true
end

-- 是否已解锁：/etc/config/Outofnetwork 以 "ok" 开头即为已解锁
-- （判据与原固件的 admin/modem/unlock_state 完全一致，前端逻辑无需改动）
function action_unlock_state()
	local v = (fs.readfile(UNLOCK_FILE) or ""):match("^ok") ~= nil
	http.prepare_content("application/json")
	http.header("Cache-Control", "no-store")
	http.write(v and '{"ok":true,"unlocked":true}' or '{"ok":true,"unlocked":false}')
end

-- 破笼解锁。纯本地：写标志 + 清 LuCI 菜单缓存（隐藏菜单据此显隐）。
--
-- 安全：
--  * 只收 POST，且必须带当前会话的 token（防 CSRF）。
--  * 口令仅用作本地触发，设备不持久化、不对外发送。
function action_Outofnetwork()
	local rv = {}
	local function reply(r)
		rv["resdd"] = r
		http.prepare_content("application/json")
		http.write_json(rv)
	end

	local ctx = luci.dispatcher.context
	if http.getenv("REQUEST_METHOD") ~= "POST" or
	   not ctx or not ctx.authtoken or http.formvalue("token") ~= ctx.authtoken then
		http.status(403, "Forbidden")
		return reply("denied")
	end

	local code = http.formvalue("set") or ""
	if code == "" or #code > 128 then
		return reply("no")
	end

	-- 纯本地解锁：不再向任何服务器核验，直接落标志
	local conf = io.open(UNLOCK_FILE, "w")
	if conf then conf:write("ok\n") conf:close() end

	-- 菜单缓存清掉，前端刷新即见原本隐藏的菜单
	os.execute("rm -f /tmp/luci-indexcache* 2>/dev/null; rm -rf /tmp/luci-modulecache 2>/dev/null")

	return reply("yes")
end
