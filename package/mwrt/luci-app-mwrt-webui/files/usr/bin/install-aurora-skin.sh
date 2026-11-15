#!/bin/sh
#
# install-aurora-skin.sh —— 安装/自愈 aurora 浅色皮肤
#
# 把 luci-theme-aurora 1.3.0 的整套样式叠加到 argon 上, 并把 argon 的导航壳
# 也换成 aurora 的浅色调性。三个资源:
#
#   mwrt-aurora-boot.js     锁定浅色 + 运行时停用 argon 的两个本地定制表
#                           (argon-menu-custom.css 深色霓虹导航、
#                            argon-global-custom.css 青绿控件皮) 和内联 dark.css
#   mwrt-aurora-full.css    aurora 全量样式(已剔除 aurora 自己的导航规则)
#   mwrt-aurora-chrome.css  argon 侧边栏/顶栏的 aurora 化 + 变量对齐 + 质感统一
#
# 加载顺序有意义: boot.js 必须在两张表之前(先静音旧表再上新表, 不闪);
# chrome.css 必须在 full.css 之后(它要覆盖 argon 而非被 aurora 覆盖)。
#
# 幂等:重复跑不会重复注入,可以放 cron 里当兜底。
# luci-base 升级会覆盖 header.ut,所以需要 cron 自愈 —— 和 disclaimer 一样。
#
# 注入点是 luci-base 的全局模板 /usr/share/ucode/luci/template/header.ut,
# 不是主题目录。写进 themes/argon/ 的话换主题就没了。
# 插在 include(themes/${theme}/header) 之后 —— 主题 header 里已经输出了
# </head><body>,所以落在 body 开头:仍先于首次绘制,且排在主题 CSS 之后。
#
# 用法:  ./install-aurora-skin.sh          安装或自愈
#        ./install-aurora-skin.sh --remove 卸载

set -u

HEADER=/usr/share/ucode/luci/template/header.ut
RES=/www/luci-static/resources
JS=$RES/mwrt-aurora-boot.js
CSS=$RES/mwrt-aurora-full.css
CHROME=$RES/mwrt-aurora-chrome.css
FONT=$RES/mwrt-lato-regular.woff2
OLD_JS=$RES/mwrt-aurora-darkmode.js
OLD_CSS=$RES/mwrt-aurora-skin.css
MARK_BEGIN="{# mwrt-aurora-skin:begin"
MARK_END="{# mwrt-aurora-skin:end #}"
VER=85
# 资源地址里再拼上 pkgs_update_time(= opkg/status 的 mtime, mwrt-cachebust 按静态资源
# 指纹校正), 刷了内容不同的固件浏览器就不会再用旧缓存。
V="$VER-{{ pkgs_update_time }}"
# v21 起整块只在 argon 主题下输出。aurora 皮是给 argon 量身做的(boot.js 会去停
# argon 的定制表, chrome.css 改的是 argon 的壳), 切到 bootstrap 等别的主题时
# 不分主题注入会把对方样式压坏。
GATE="{% if (theme == 'argon'): %}"

case "${1:-}" in
	--remove)
		if [ -f "$HEADER" ]; then
			awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
				index($0,b){skip=1} !skip{print} index($0,e){skip=0}
			' "$HEADER" > "$HEADER.tmp" && mv "$HEADER.tmp" "$HEADER"
		fi
		rm -f "$JS" "$CSS" "$CHROME" "$FONT" "$OLD_JS" "$OLD_CSS"
		rm -f /tmp/luci-indexcache* 2>/dev/null
		rm -rf /tmp/luci-modulecache 2>/dev/null
		echo "已卸载"
		exit 0
		;;
esac

[ -f "$HEADER" ] || { echo "错误: 找不到 $HEADER"; exit 1; }
for f in "$JS" "$CSS" "$CHROME"; do
	[ -f "$f" ] || { echo "错误: 请先部署 $f"; exit 1; }
done

# 上一版的资源名, 顺手清掉
rm -f "$OLD_JS" "$OLD_CSS"

# v20 及以前的块没有主题门控, 整段摘掉重插
if grep -q 'mwrt-aurora-skin:begin' "$HEADER" && ! grep -qF "$GATE" "$HEADER"; then
	[ -f "$HEADER.bak-aurora-skin" ] || cp "$HEADER" "$HEADER.bak-aurora-skin"
	awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
		index($0,b){skip=1} !skip{print} index($0,e){skip=0}
	' "$HEADER" > "$HEADER.tmp" && mv "$HEADER.tmp" "$HEADER"
	echo "已摘掉无主题门控的旧块,重新注入"
fi

if grep -q 'mwrt-aurora-skin:begin' "$HEADER"; then
	# 已注入 —— 只校正资源版本号, 不重复插块
	sed -i "s/mwrt-aurora-boot\.js?v=[^\"]*/mwrt-aurora-boot.js?v=$V/;
	        s/mwrt-aurora-full\.css?v=[^\"]*/mwrt-aurora-full.css?v=$V/;
	        s/mwrt-aurora-chrome\.css?v=[^\"]*/mwrt-aurora-chrome.css?v=$V/" "$HEADER"
	echo "header.ut 已注入,已校正资源版本为 v$VER"
else
	grep -qF 'include(`themes/${theme}/header`)' "$HEADER" || {
		echo "错误: header.ut 里找不到主题 include 锚点"; exit 1; }

	# busybox 的 sed -i 插多行不可靠,用 awk
	awk -v ver="$V" -v gate="$GATE" '
	/^-%\}/ && !done {
		print
		print "{# mwrt-aurora-skin:begin  aurora 浅色皮肤(仅 argon) #}"
		print gate
		print "<script src=\"{{ resource }}/mwrt-aurora-boot.js?v=" ver "\"></script>"
		print "<link rel=\"stylesheet\" href=\"{{ resource }}/mwrt-aurora-full.css?v=" ver "\">"
		print "<link rel=\"stylesheet\" href=\"{{ resource }}/mwrt-aurora-chrome.css?v=" ver "\">"
		print "{% endif %}"
		print "{# mwrt-aurora-skin:end #}"
		done = 1
		next
	}
	{ print }
	' "$HEADER" > "$HEADER.tmp" || { echo "错误: awk 处理失败"; rm -f "$HEADER.tmp"; exit 1; }

	if ! grep -q 'mwrt-aurora-skin:begin' "$HEADER.tmp"; then
		echo "错误: 注入后校验失败,已回滚"
		rm -f "$HEADER.tmp"
		exit 1
	fi

	[ -f "$HEADER.bak-aurora-skin" ] || cp "$HEADER" "$HEADER.bak-aurora-skin"
	mv "$HEADER.tmp" "$HEADER"
	echo "已注入 $HEADER"
fi

rm -f /tmp/luci-indexcache* 2>/dev/null
rm -rf /tmp/luci-modulecache 2>/dev/null

echo "完成。"
echo "  启动脚本 : $JS"
echo "  全量样式 : $CSS"
echo "  外壳样式 : $CHROME"
echo "  卸载     : $0 --remove"
