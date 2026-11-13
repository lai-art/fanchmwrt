#
# Copyright (C) 2026 FanchmWrt
#
# 简体中文语言包（元包）
#
# 背景：LuCI 的 luci-i18n-* 翻译包在 Makefile 中声明为 HIDDEN:=1，
#       这类符号没有 prompt，部分 OpenWrt 版本下 .config 里写 =y 也会被
#       make defconfig 回落成默认值 n（实测 luci-i18n-base-zh-cn 被丢弃，
#       而 tmp/.config-package.in 中该符号确实存在、依赖 luci-base 也满足）。
#       做法：用一个可见的元包把翻译包作为 DEPENDS 拉进来，
#       依赖关系不受 prompt 限制，一定参与构建。
#
# 包名刻意不使用 luci-i18n- 前缀，避免被 CI 自检当成“翻译包缺失可忽略”。
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-zh-cn-support
PKG_VERSION:=1.0
PKG_RELEASE:=1

PKG_MAINTAINER:=FanchmWrt
PKG_LICENSE:=Apache-2.0

include $(INCLUDE_DIR)/package.mk

define Package/luci-zh-cn-support
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=Translations
  TITLE:=Simplified Chinese language support for LuCI (meta)
  DEPENDS:=+luci-i18n-base-zh-cn \
           +luci-i18n-firewall-zh-cn \
           +luci-i18n-package-manager-zh-cn
  PKGARCH:=all
endef

define Package/luci-zh-cn-support/description
  Meta package that pulls the Simplified Chinese (zh-cn) LuCI translations in
  as hard dependencies, so they get built despite being HIDDEN packages.
  Installs no files of its own; all content comes from its dependencies.
endef

# 纯元包：不安装任何文件，内容全部来自 DEPENDS
define Package/luci-zh-cn-support/install
	true
endef

# 纯元包还必须把默认的 Build/Prepare 与 Build/Compile 清空。
# 否则 package.mk 的默认实现会建一个空构建目录然后执行 `make -C <dir> .`,
# 而这个目录里既没有源码也没有 Makefile, 报:
#   make[3]: *** No targets specified and no makefile found.  Stop.
# 报错还指向 build_dir 而不是本包, 很容易被误判成工具链问题。
define Build/Prepare
endef

define Build/Compile
endef

$(eval $(call BuildPackage,luci-zh-cn-support))
