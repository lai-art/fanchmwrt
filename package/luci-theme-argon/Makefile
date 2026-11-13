#
# luci-theme-argon —— Argon 主题（从 Mwrt 固件提取的 v2.3.1 定制版）
#
# 提取来源：Mwrt 固件 rootfs（usr/lib/lua/luci/view/themes/argon + www/luci-static/argon）
# 该版本相对上游 jerrykuku/luci-theme-argon v2.3.1 有作者的渲染优化改动，
# 直接提取可 100% 还原原固件的前端外观。已剔除作者的备份垃圾文件（副本/.bak 等）。
# 模板内不含任何作者服务器地址（仅保留上游的 GitHub 版权注释链接）。
#
include $(TOPDIR)/rules.mk

LUCI_TITLE:=Argon Theme (Mwrt 提取版, 兼容 luci-compat)
# Lua 模板渲染依赖 luci-compat + luci-lua-runtime
LUCI_DEPENDS:=+luci-base +luci-compat +luci-lua-runtime
LUCI_PKGARCH:=all

PKG_NAME:=luci-theme-argon
PKG_VERSION:=2.3.1
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Jerrykuku (extracted by lai-art)

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
