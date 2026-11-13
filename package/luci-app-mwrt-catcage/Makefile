#
# luci-app-mwrt-catcage —— 侧栏「笼中猫」破笼动画 + 插件解锁
#
# 从 Mwrt 固件提取的前端彩蛋（美术库 / 动画控制 / 解锁认证框），
# 已完全去除原作者服务器依赖：解锁为纯本地判定，不向任何外部服务器发起请求。
#
# 依赖 luci-compat / luci-lua-runtime：控制器用 Lua 编写，跑在 25.12 的兼容层上。
#
include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI 侧栏破笼动画与本地解锁 (Mwrt 提取, 去服务器依赖)
LUCI_DEPENDS:=+luci-base +luci-compat +luci-lua-runtime
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-mwrt-catcage
PKG_VERSION:=1.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=lai-art

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
