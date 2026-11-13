#
# luci-theme-aurora —— aurora 浅色皮肤（argon 叠加层）
# 从 Mwrt 固件提取，来源 commit r33648-ec9ef10efc
#
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-theme-aurora
PKG_VERSION:=1.3.0
PKG_RELEASE:=1

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Manper-zcy (extracted by lai-art)

include $(INCLUDE_DIR)/package.mk

define Package/luci-theme-aurora
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=5. Themes
  TITLE:=Aurora light skin overlay for argon
  DEPENDS:=+luci-theme-argon
  PKGARCH:=all
endef

define Package/luci-theme-aurora/description
  Aurora light skin for the argon theme.
  Overlays three resources (boot.js / full.css / chrome.css) onto argon
  and injects them into luci-base header.ut at first boot.
  Extracted from the Mwrt firmware (padavanonly/immortalwrt-mt798x-24.10
  based, r33648-ec9ef10efc).
endef

define Build/Compile
	true
endef

define Package/luci-theme-aurora/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources
	$(CP) ./files/www/luci-static/resources/* $(1)/www/luci-static/resources/
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/* $(1)/etc/uci-defaults/
endef

$(eval $(call BuildPackage,luci-theme-aurora))
