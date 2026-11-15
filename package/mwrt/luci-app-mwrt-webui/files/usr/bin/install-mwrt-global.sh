#!/bin/sh
#
# install-mwrt-global.sh —— 安装/自愈与主题无关的全局脚本块
#
# 注入三样东西, 所有主题(argon / bootstrap)都生效:
#   mwrt-unlock.js      后台连续键入 mwrtmwrt 弹出插件认证框
#   mwrt-cat-art.js     侧栏「笼中猫」美术库(s90 起)
#   mwrt-catcage.js     侧栏「笼中猫」游戏控制: 破笼后弹出上面的认证框(s90 起)
#   mwrt-notice.js      右上角全局消息中心(多条叠加, 部分可已读关闭;
#                       新固件提示也在这里, v2 起替代 mwrt-ota-notify.js)
#   (s96/s101 起块里还有三段服务端判据, 随块整体下发: funen/catshow/funrev → MwrtUi.fun/cathide/funrev,
#    5700 在场 + phoneen → MwrtUi.phone/phoneSrc 以及按条件输出的 mwrt-phone.js。块文本现在是
#    footer.ut 里 mwrt-global 块的逐字副本(见下面 emit_block), 各脚本 ?v= 以块文本为准, 与 VER 无关。
#    s103 起块文本同步到 mwrt-phone.js ?v=5 / mwrt-notice.js ?v=13(含 data-sms), VER 11→12。
#    s105 起 mwrt-notice.js ?v=14 并多一个 data-ack(已读状态改由设备端记录), VER 12→13。
#    s107 起整站日夜模式: mwrt-notice.js ?v=15 / mwrt-phone.js ?v=6(两者的深色改读 html[data-darkmode]), VER 13→14。)
#    s155 起 mwrt-notice.js ?v=16(故障报修维护人员新消息的右上角全局通知), VER 14→15。
#   mwrt-portsw.js      单网口机型(C2000 MAX)的网口 WAN/LAN 切换浮窗 + 接入检测:
#                       网口当 LAN 时插上光猫/上级路由, 全屏问要不要改成 WAN(v4 起);
#                       别的机型后端回 ok:false, 脚本问一次就停
#                       (v8 起还负责 USB 网卡接入时全屏问「是否当作 WAN」, 轮询 usbnic_state;
#                        mwrt-notice.js 同步加了 USB 网卡 / 手机共享六种事件的文案和「去选择」)
#
# 写法照 install-wizard.sh: 注入点是 luci-base 的全局模板
# /usr/share/ucode/luci/template/footer.ut, 插在 include(themes/${theme}/footer)
# 之前(主题 footer 会输出 </body></html>)。登录页也会渲染 footer, 所以要求
# ctx.authsession —— 没登录时这几段脚本都没用。
#
# 幂等: 重复跑不会重复注入; 块里的版本号不对就整段换掉。luci-base 升级会把
# footer.ut 覆盖回去, 所以挂 cron 自愈。
#
# v3 起资源地址带 ?v=<VER>-{{ pkgs_update_time }}, 并在最后调 mwrt-cachebust:
# 刷了内容不同的新固件, pkgs_update_time 就跟着变, 浏览器不会再拿旧缓存。
# 顺带给 bootstrap 系主题 header.ut 里写死版本号的 cascade/mobile/cbi 也补上。
#
# 用法:  ./install-mwrt-global.sh          安装或自愈
#        ./install-mwrt-global.sh --remove 卸载注入块

set -u

FOOTER=/usr/share/ucode/luci/template/footer.ut
RES=/www/luci-static/resources
MARK_BEGIN="{# mwrt-global:begin #}"
MARK_END="{# mwrt-global:end #}"
VER=15   # 块文本修订号(仅标识; 块内各脚本的 ?v= 取自 emit_block 的逐字文本)
PV='{{ pkgs_update_time }}'

strip_block() {
	[ -f "$FOOTER" ] || return 0
	grep -q 'mwrt-global:begin' "$FOOTER" || return 0
	awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
		index($0,b){skip=1} !skip{print} index($0,e){skip=0}
	' "$FOOTER" > "$FOOTER.tmp" && mv "$FOOTER.tmp" "$FOOTER"
}

# 当前 footer.ut 里 mwrt-global 块的逐字副本(s105 定稿; 改 footer.ut 的块时这里要同步)。
emit_block() {
cat <<'MWRT_GLOBAL_BLOCK'
{# mwrt-global:begin #}
{%
  // 与主题无关的全局脚本: 插件认证框 + 侧栏笼中猫(美术库 + 游戏控制) + 消息中心 + 网口切换/接入检测。只给已登录页面。
  let _mg_show = false;
  try { _mg_show = !!ctx?.authsession; } catch (_e) { _mg_show = false; }

  // s96: 「Mwrt设定 -> 界面与趣玩」两个开关(uci mwrt.@ndis[0])。
  //   funen   趣玩中心, 默认关(没有这个选项等同关闭): 决定侧栏 funny 按钮渲不渲染;
  //   catshow 桌面猫咪, 默认开(只有明确写 0 才隐藏): 隐藏的只是解锁后的玩偶猫。
  // 在服务端渲染页面时读好、直接写进页面, 前端就不用再发请求, 也不会"先出现再消失"。
  // 笼中猫是解锁入口, 没解锁时不受 catshow 控制, 所以隐藏猫之前要确认已解锁
  // (判据同 admin/modem/unlock_state: /etc/config/Outofnetwork 以 ok 开头)。
  // 隐藏时干脆不下发猫咪的两个脚本: 不建 DOM、不挂监听/观察器/定时器/rAF, 比"加载后再关"省得彻底。
  // 每次整页加载多一次 ~0.2ms 的 uci 读取, 失败一律按默认值(趣玩关、猫显示)处理。
  //   funrev  趣玩菜单的"版本戳": 趣玩关着是 "0"; 开着是 "1." + 菜单缓存 fun.json 的修改时间(还没有缓存是 "1.0")。
  //           浏览器把侧栏菜单树缓存在 sessionStorage, 开关/菜单内容一变它就是旧的,
  //           mwrt-aurora-boot.js 看到戳和上次不同就清掉那份缓存并重画侧栏。
  let _mg_fun = false, _mg_cathide = false, _mg_funrev = "0";
  if (_mg_show) {
    try {
      let _mg_uc = require("uci").cursor();
      _mg_fun = _mg_uc.get_first("mwrt", "ndis", "funen") == "1";
      if (_mg_fun)
        _mg_funrev = "1." + (require("fs").stat("/tmp/mwrt-fun/fun.json")?.mtime ?? 0);
      if (_mg_uc.get_first("mwrt", "ndis", "catshow") == "0")
        _mg_cathide = substr(require("fs").readfile("/etc/config/Outofnetwork", 4) ?? "", 0, 2) == "ok";
    } catch (_e) { _mg_fun = false; _mg_cathide = false; _mg_funrev = "0"; }
  }

  // s101: 5700 通话功能(首页「拨号」按钮 + 全局来电/短信通知)的在场判据 → MwrtUi.phone。
  // 两个条件都满足才算 1: /tmp/modconf.conf(开机识别模组时写的型号串, 几十字节)含 "5700",
  // 并且 USB 总线上真有 VID 3466 的设备(热拔后 modconf 会残留, 单看它会误判)。
  // 只有第一条成立才去扫 sysfs; 共约 1 次小文件读 + 十几次 sysfs 读, 不 fork、不碰串口、不碰 AT。
  // 登录页没有 authsession, _mg_show 为假, 整段不执行, 登录页也就不会下发 phone 脚本。
  // 再加一道开关: uci mwrt.@ndis[0].phoneen 为 '0' 时按"不在场"处理(MwrtUi.phone=0, 不下发脚本)。
  // 任何异常都按"不在场"处理。phoneSrc 带 pkgs_update_time, 刷机后浏览器不吃旧缓存; 改 mwrt-phone.js 时升这里的 v=。
  let _mg_phone = false;
  if (_mg_show) {
    try {
      let _pfs = require("fs");
      if (index(lc(_pfs.readfile("/tmp/modconf.conf", 128) ?? ""), "5700") >= 0) {
        for (let _pd in (_pfs.lsdir("/sys/bus/usb/devices") ?? [])) {
          if (trim(_pfs.readfile(`/sys/bus/usb/devices/${_pd}/idVendor`, 16) ?? "") == "3466") {
            // 开关 uci mwrt.@ndis[0].phoneen: 只有明确写 0 才关(缺省开)。读失败落到外层 catch → 按不在场处理。
            _mg_phone = (require("uci").cursor().get_first("mwrt", "ndis", "phoneen") != "0");
            break;
          }
        }
      }
    } catch (_e) { _mg_phone = false; }
  }
%}
{% if (_mg_show): %}
	<script>window.MwrtUi = { fun: {{ _mg_fun ? 1 : 0 }}, cathide: {{ _mg_cathide ? 1 : 0 }}, funrev: "{{ _mg_funrev }}", phone: {{ _mg_phone ? 1 : 0 }}{% if (_mg_phone): %}, phoneSrc: {{ sprintf('%J', `${resource}/mwrt-phone.js?v=6-${pkgs_update_time}`) }}{% endif %} };</script>
	<script src="{{ resource }}/mwrt-unlock.js?v=8-{{ pkgs_update_time }}" data-url="{{ dispatcher.build_url('admin/Outofnetwork') }}"></script>
{% if (_mg_phone): %}
	<script src="{{ resource }}/mwrt-phone.js?v=6-{{ pkgs_update_time }}" data-base="{{ dispatcher.build_url('admin/modem') }}" data-sms="{{ dispatcher.build_url('admin/modem/smsc') }}"></script>
{% endif %}
{% if (!_mg_cathide): %}
	<script src="{{ resource }}/mwrt-cat-art.js?v=5-{{ pkgs_update_time }}"></script>
	<script src="{{ resource }}/mwrt-catcage.js?v=6-{{ pkgs_update_time }}" data-state="{{ dispatcher.build_url('admin/modem/unlock_state') }}"></script>
{% endif %}
	<script src="{{ resource }}/mwrt-notice.js?v=16-{{ pkgs_update_time }}" data-ota="{{ dispatcher.build_url('admin/system/ota') }}" data-sms="{{ dispatcher.build_url('admin/modem/smsc') }}" data-ack="{{ dispatcher.build_url('admin/modem/notice_ack') }}"></script>
	<script src="{{ resource }}/mwrt-portsw.js?v=6-{{ pkgs_update_time }}" data-base="{{ dispatcher.build_url('admin/modem') }}" data-fo="{{ dispatcher.build_url('admin/network/mwrt_assurance') }}" data-lan="{{ dispatcher.build_url('admin/network/network') }}" data-home="{{ dispatcher.build_url('admin/modeminfo') }}"></script>
{% endif %}
{# mwrt-global:end #}
MWRT_GLOBAL_BLOCK
}

drop_cache() {
	rm -f /tmp/luci-indexcache* 2>/dev/null
	rm -rf /tmp/luci-modulecache 2>/dev/null
}

case "${1:-}" in
	--remove)
		strip_block
		drop_cache
		echo "已卸载注入块"
		exit 0
		;;
esac

[ -f "$FOOTER" ] || { echo "错误: 找不到 $FOOTER"; exit 1; }
for f in mwrt-unlock.js mwrt-cat-art.js mwrt-catcage.js mwrt-notice.js mwrt-portsw.js; do
	[ -f "$RES/$f" ] || { echo "错误: 请先部署 $RES/$f"; exit 1; }
done

# 版本号不对(老块)就整段换。s90 起: 块里已经带 mwrt-catcage.js 的,说明是源码里直接携带的新版 footer.ut
# (各脚本版本号各自独立, 与这里的 VER 不一致是正常的), 不能再按 VER 判旧去整段换掉, 否则会把源码里
# 较新的版本号抹回旧值; 没有 catcage 那一行的才是老块, 整段换成带猫的新块。
# s101 起再加一条: 块里没有 phoneen(5700 通话判据及其 uci 开关)的也是老块(s90~s101 开发中间版的块), 同样整段换成当前块。
# 判据之所以安全: 源码里直接携带的新版 footer.ut 一定带 phoneen, 不会被误判为旧而降级。
if grep -q 'mwrt-global:begin' "$FOOTER" && { ! grep -q 'mwrt-catcage.js' "$FOOTER" || ! grep -q 'phoneen' "$FOOTER"; }; then
	strip_block
fi

if grep -q 'mwrt-global:begin' "$FOOTER"; then
	echo "footer.ut 已注入,跳过"
else
	ANCHOR='{% include(`themes/${theme}/footer`) %}'
	grep -qF "$ANCHOR" "$FOOTER" || { echo "错误: footer.ut 里找不到主题 include 锚点"; exit 1; }

	# 块文本是 footer.ut 里 mwrt-global 块的逐字副本(emit_block), 先落到临时文件再用 awk 读进来插到锚点前。
	# 不再用一串 print 拼接: 块里有反引号/${}/单引号/多行 ucode, 拼接极易走样, 手工跑一次就会把
	# funen/catshow/funrev/phone 等部分抹掉(s101 之前的老写法就有这个问题)。
	BLOCKF="$FOOTER.block.$$"
	emit_block > "$BLOCKF" || { echo "错误: 写块文本失败"; rm -f "$BLOCKF"; exit 1; }
	# busybox 的 sed -i 插多行不可靠,用 awk
	awk -v anchor="$ANCHOR" -v bf="$BLOCKF" '
	index($0, anchor) && !done {
		while ((getline line < bf) > 0) print line
		close(bf)
		done = 1
	}
	{ print }
	' "$FOOTER" > "$FOOTER.tmp" || { echo "错误: awk 处理失败"; rm -f "$FOOTER.tmp" "$BLOCKF"; exit 1; }
	rm -f "$BLOCKF"

	if ! grep -q 'mwrt-global:begin' "$FOOTER.tmp"; then
		echo "错误: 注入后校验失败,已回滚"
		rm -f "$FOOTER.tmp"
		exit 1
	fi

	mv "$FOOTER.tmp" "$FOOTER"
	echo "已注入 $FOOTER"
fi

# bootstrap / bootstrap-dark / bootstrap-light 的 header.ut 把 luci 版本号写死在
# ?v= 里, 新旧固件一样。只给还没带 pkgs_update_time 的那几行补上, 幂等。
for t in /usr/share/ucode/luci/template/themes/*/header.ut; do
	[ -f "$t" ] || continue
	grep -E '/(cascade|mobile)\.css\?v=|/cbi\.js\?v=' "$t" | grep -qv 'pkgs_update_time' || continue
	sed -i -E "/pkgs_update_time/! s#(/(cascade|mobile)\.css|/cbi\.js)\?v=([^\"{]*)\"#\1?v=\3-$PV\"#" "$t"
	echo "已补版本号 $t"
done

# 按静态资源指纹校正 pkgs_update_time(内容没变就什么都不做)
[ -x /usr/bin/mwrt-cachebust ] && /usr/bin/mwrt-cachebust

drop_cache
echo "完成。"
