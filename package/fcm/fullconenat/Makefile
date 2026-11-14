#
# Copyright (C) 2018 Chion Tang <tech@chionlab.moe>
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=fullconenat
PKG_RELEASE:=1

PKG_SOURCE_DATE:=2018-12-15
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/Chion82/netfilter-full-cone-nat.git
PKG_SOURCE_VERSION:=d4daedd0e25309e822577e92b96ae4c7184abe83

PKG_LICENSE:=GPL-2.0
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/iptables-mod-fullconenat
  SUBMENU:=Firewall
  SECTION:=net
  CATEGORY:=Network
  TITLE:=FULLCONENAT iptables extension
  DEPENDS:=+iptables +kmod-ipt-fullconenat
  MAINTAINER:=Chion Tang <tech@chionlab.moe>
endef

define Package/iptables-mod-fullconenat/install
	$(INSTALL_DIR) $(1)/usr/lib/iptables
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/libipt_FULLCONENAT.so $(1)/usr/lib/iptables
endef

define KernelPackage/ipt-fullconenat
  SUBMENU:=Netfilter Extensions
  TITLE:=FULLCONENAT netfilter module
  DEPENDS:=+kmod-nf-ipt +kmod-nf-nat
  MAINTAINER:=Chion Tang <tech@chionlab.moe>
  KCONFIG:=CONFIG_NF_CONNTRACK_EVENTS=y CONFIG_NF_CONNTRACK_CHAIN_EVENTS=y
  FILES:=$(PKG_BUILD_DIR)/xt_FULLCONENAT.ko
endef

include $(INCLUDE_DIR)/kernel-defaults.mk

define Build/Prepare
	$(call Build/Prepare/Default)
	$(CP) ./files/Makefile $(PKG_BUILD_DIR)/
	# 2018 年的老代码把 iptables 扩展的注册函数直接命名成 _init（源码第 168 行）：
	#   void _init(void) { xtables_register_target(&fullconenat_tg_reg); }
	# 而 _init 是 ELF 的保留初始化符号，musl 的 crti.o 里已经定义了一份，于是链接报
	#   multiple definition of `_init'; crti.o:... first defined here
	# Makefile 里那句 -D_INIT=$*_init 帮不上忙 —— 它只影响 -D 宏，源码里是硬写的 _init。
	# 老 GCC/binutils 不报这个错，新版才当成硬错误。只能改源码。
	sed -i 's/^void _init(void)/void fullconenat_xt_init(void)/' $(PKG_BUILD_DIR)/libipt_FULLCONENAT.c
	grep -n "void fullconenat_xt_init" $(PKG_BUILD_DIR)/libipt_FULLCONENAT.c
endef

define Build/Compile
	+$(MAKE) $(PKG_JOBS) -C "$(LINUX_DIR)" \
        CROSS_COMPILE="$(TARGET_CROSS)" \
        ARCH="$(LINUX_KARCH)" \
        SUBDIRS="$(PKG_BUILD_DIR)" \
        EXTRA_CFLAGS="$(BUILDFLAGS)" \
        modules
	$(call Build/Compile/Default)
endef

$(eval $(call BuildPackage,iptables-mod-fullconenat))
$(eval $(call KernelPackage,ipt-fullconenat))
