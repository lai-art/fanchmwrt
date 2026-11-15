#
# luci-app-mwrt-webui —— Mwrt 整套 Web 界面（业务层）
# 从 Mwrt-5.1.1162-24 (r33648-ec9ef10efc) 原样提取，446 个文件
#
# 内容：zmode 业务页面 / 控制器 / router3d-data CGI / 3D 机型图 /
#       mwrt-* 后端脚本 / rpcd / 12 个 init.d / 产品 uci 配置 / 厂商模组 Web
#
# 注意：本包不包含 device 相关配置（network/wireless/system/fstab），
#       避免固件里覆盖掉本 target 自己的默认网络设置。
#
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-mwrt-webui
PKG_VERSION:=5.1.1162
PKG_RELEASE:=24

PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Manper-zcy (extracted by lai-art)

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-mwrt-webui
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Mwrt full web UI (home page, modem pages, tools)
  DEPENDS:=+luci-base +luci-compat +luci-lua-runtime \
           +luci-theme-argon +luci-theme-aurora \
           +kmod-usb-core +kmod-usb-serial +kmod-usb-serial-option +usb-modeswitch +usbutils
  PKGARCH:=all
endef

define Package/luci-app-mwrt-webui/description
  The complete Mwrt web UI layer extracted from a running Cudy TR3000
  (Mwrt-5.1.1162-24, ImmortalWrt-mt798x-24.10 base):

   - admin/modeminfo home page (3D device render, CPU/mem/storage/temp cards,
     WAN/LAN port status, egress IP, live throughput, online clients)
   - modem pages: webui (5700 vendor SPA), nets, smsc, smscfg, settings
   - tools: fun center (admin/fun), network assurance, fault repair, wizard
   - backend: /www/cgi-bin/router3d-data status endpoint (read-only shell CGI),
     mwrt-* helper scripts, rpcd services (notice/ota/wizard)
   - routers: 12 init.d services, product uci configs, USB hotplug rules

  Device-specific configs (network/wireless/system/fstab) are intentionally
  NOT shipped, so the target's own defaults are preserved.
endef

define Build/Compile
	true
endef

define Package/luci-app-mwrt-webui/install
	$(INSTALL_DIR) $(1)/
	$(CP) ./files/. $(1)/
	# 可执行位（cp 已保留，这里兜底）
	$(CHMOD) 0755 $(1)/usr/bin/mwrt-* 2>/dev/null || true
	$(CHMOD) 0755 $(1)/usr/libexec/rpcd/* 2>/dev/null || true
	$(CHMOD) 0755 $(1)/www/cgi-bin/* 2>/dev/null || true
	$(CHMOD) 0755 $(1)/etc/init.d/* 2>/dev/null || true
endef

define Package/luci-app-mwrt-webui/conffiles
/etc/config/WTMmodem
/etc/config/mwrt_led
/etc/config/mwrt_ota
/etc/config/mwrt_ota.pre-retarget
/etc/config/apninfo
/etc/config/atsd_tools
/etc/config/smsforward
/etc/config/Mwrt-Assurance
/etc/config/Outofnetwork
endef

$(eval $(call BuildPackage,luci-app-mwrt-webui))
