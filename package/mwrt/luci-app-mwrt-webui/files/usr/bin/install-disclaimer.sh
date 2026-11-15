#!/bin/sh
#
# install-disclaimer.sh —— 安装/自愈"首次登录免责说明弹窗"
#
# 幂等:重复跑不会重复注入,可以放 cron 里当兜底。
#
# 注入点是 luci-base 的全局模板 /usr/share/ucode/luci/template/footer.ut,
# 不是主题目录 —— 之前吃过亏,写进 themes/argon/ 的定制换主题就没了。
# 必须插在 include(themes/${theme}/footer) 之前,因为主题 footer 会输出
# </body></html>,插在后面浏览器会当成正文外的垃圾。
#
# gate 放在服务端:标识文件存在就整段不输出,已确认的用户连 JS 都不会下发。
# 登录页(sysauth.ut)也会渲染 footer,所以额外要求 ctx.authsession 存在,
# 免得没登录就先弹一个框。
#
# 用法:  ./install-disclaimer.sh          安装或自愈
#        ./install-disclaimer.sh --reset  清掉标识,让弹窗重新出现(测试用)
#        ./install-disclaimer.sh --remove 卸载

set -u

FOOTER=/usr/share/ucode/luci/template/footer.ut
JS=/www/luci-static/resources/mwrt-disclaimer.js
CTRL=/usr/lib/lua/luci/controller/mwrtdisclaimer.lua
FLAG=/usr/bin/disclaimer.conf
MARK_BEGIN="{# mwrt-disclaimer:begin #}"
MARK_END="{# mwrt-disclaimer:end #}"

case "${1:-}" in
	--reset)
		rm -f "$FLAG"
		echo "已清除 $FLAG,下次打开页面会重新弹出"
		exit 0
		;;
	--remove)
		[ -f "$FOOTER" ] && awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
			index($0,b){skip=1} !skip{print} index($0,e){skip=0}
		' "$FOOTER" > "$FOOTER.tmp" && mv "$FOOTER.tmp" "$FOOTER"
		rm -f "$JS" "$CTRL"
		rm -f /tmp/luci-indexcache* 2>/dev/null
		rm -rf /tmp/luci-modulecache 2>/dev/null
		echo "已卸载(标识文件 $FLAG 保留,如需重弹请手动删除)"
		exit 0
		;;
esac

[ -f "$FOOTER" ] || { echo "错误: 找不到 $FOOTER"; exit 1; }
[ -f "$JS" ]     || { echo "错误: 请先部署 $JS"; exit 1; }
[ -f "$CTRL" ]   || { echo "错误: 请先部署 $CTRL"; exit 1; }

# 已经注入过就不动(幂等)
if grep -q 'mwrt-disclaimer:begin' "$FOOTER"; then
	echo "footer.ut 已注入,跳过"
else
	ANCHOR='{% include(`themes/${theme}/footer`) %}'
	grep -qF "$ANCHOR" "$FOOTER" || { echo "错误: footer.ut 里找不到主题 include 锚点"; exit 1; }

	# busybox 的 sed -i 插多行不可靠,用 awk
	awk -v anchor="$ANCHOR" -v b="$MARK_BEGIN" -v e="$MARK_END" '
	index($0, anchor) && !done {
		print b
		print "{%"
		print "  // 刷机后首次登录弹免责说明。标识文件在则整段不输出。"
		print "  // 登录页也会渲染 footer,所以要求已登录(authsession)才注入。"
		print "  let _dc_show = false;"
		print "  try {"
		print "    let _fs = require(\"fs\");"
		print "    if (!_fs.access(\"/usr/bin/disclaimer.conf\") && ctx?.authsession)"
		print "      _dc_show = true;"
		print "  } catch (_e) { _dc_show = false; }"
		print "%}"
		print "{% if (_dc_show): %}"
		print "\t<script src=\"{{ resource }}/mwrt-disclaimer.js?v=1-{{ pkgs_update_time }}\"></script>"
		print "{% endif %}"
		print e
		done = 1
	}
	{ print }
	' "$FOOTER" > "$FOOTER.tmp" || { echo "错误: awk 处理失败"; rm -f "$FOOTER.tmp"; exit 1; }

	if ! grep -q 'mwrt-disclaimer:begin' "$FOOTER.tmp"; then
		echo "错误: 注入后校验失败,已回滚"
		rm -f "$FOOTER.tmp"
		exit 1
	fi

	cp "$FOOTER" "$FOOTER.bak-disclaimer" 2>/dev/null
	mv "$FOOTER.tmp" "$FOOTER"
	echo "已注入 $FOOTER"
fi

# 老块里是写死的 ?v=1, 新旧固件同一个地址, 浏览器会一直用旧缓存。补上 pkgs_update_time
# (opkg/status 的 mtime, mwrt-cachebust 按静态资源指纹校正), 幂等。
sed -i 's#/mwrt-disclaimer\.js?v=1"#/mwrt-disclaimer.js?v=1-{{ pkgs_update_time }}"#' "$FOOTER"

rm -f /tmp/luci-indexcache* 2>/dev/null
rm -rf /tmp/luci-modulecache 2>/dev/null

echo "完成。"
echo "  标识文件 : $FLAG  ($([ -f "$FLAG" ] && echo 已确认过 || echo 未确认,会弹窗))"
echo "  想重新弹 : $0 --reset"
