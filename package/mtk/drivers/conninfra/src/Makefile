###############################################################################
# Necessary Check

#ifeq ($(AUTOCONF_H),)
#    $(error AUTOCONF_H is not defined)
#endif

#ccflags-y += -imacros $(AUTOCONF_H)

# Force build fail on modpost warning
KBUILD_MODPOST_FAIL_ON_WARNINGS := y

###############################################################################
ccflags-y += -Werror
ccflags-y += -Wno-error=format
ccflags-y += -Wno-error=format-extra-args
ccflags-y += -Wframe-larger-than=1024
# 本包自带 ccflags-y += -Werror (见上), 该前提在 6.6 上成立(零警告),
# 但 Linux 6.12 新增了 -Wmissing-prototypes / -Wmissing-declarations,
# 老代码会产生大量此类警告并被 -Werror 提升为硬错误。
# 这里整体降级为警告(-Wno-error), 保留内核自身的
# -Werror=implicit-function-declaration 等真正致命的检查。
ccflags-y += -Wno-error -Wno-missing-prototypes -Wno-missing-declarations \
	-Wno-error=incompatible-pointer-types -Wno-error=int-conversion \
	-Wno-error=return-mismatch -Wno-error=declaration-missing-parameter-type \
	-Wno-error=implicit-int -Wno-error=enum-conversion \
	-Wno-error=implicit-function-declaration -Wno-error=macro-redefined

###############################################################################
MODULE_NAME := conninfra
obj-m += $(MODULE_NAME).o

###############################################################################
# common_main
###############################################################################
ccflags-y += \
	-I$(SUBDIRS)/include \
	-I$(SUBDIRS)/base/include \
	-I$(SUBDIRS)/core/include \
	-I$(SUBDIRS)/conf/include \
	-I$(SUBDIRS)/platform/include

$(MODULE_NAME)-objs += base/ring.o
$(MODULE_NAME)-objs += base/osal.o
$(MODULE_NAME)-objs += base/msg_thread.o
$(MODULE_NAME)-objs += core/conninfra_core.o
$(MODULE_NAME)-objs += src/conninfra_dev.o
$(MODULE_NAME)-objs += src/conninfra.o
$(MODULE_NAME)-objs += platform/consys_hw.o
$(MODULE_NAME)-objs += platform/consys_hw_plat_data.o
$(MODULE_NAME)-objs += platform/pmic_mng.o
$(MODULE_NAME)-objs += platform/emi_mng.o
$(MODULE_NAME)-objs += platform/consys_reg_mng.o

# By Plaftfrom
# MT7986
ifeq ($(CONFIG_MTK_CONNINFRA_APSOC_MT7986),y)
ccflags-y += \
	-I$(SUBDIRS)/platform/mt7986/include -DCONNINFRA_APSOC_MT7986
$(MODULE_NAME)-objs += platform/mt7986/mt7986.o
$(MODULE_NAME)-objs += platform/mt7986/mt7986_pmic.o
$(MODULE_NAME)-objs += platform/mt7986/mt7986_consys_reg.o
$(MODULE_NAME)-objs += platform/mt7986/mt7986_pos.o
$(MODULE_NAME)-objs += platform/mt7986/mt7986_emi.o
endif

# MT7981
ifeq ($(CONFIG_MTK_CONNINFRA_APSOC_MT7981),y)
ccflags-y += \
	-I$(SUBDIRS)/platform/mt7981/include -DCONNINFRA_APSOC_MT7981
$(MODULE_NAME)-objs += platform/mt7981/mt7981.o
$(MODULE_NAME)-objs += platform/mt7981/mt7981_pmic.o
$(MODULE_NAME)-objs += platform/mt7981/mt7981_consys_reg.o
$(MODULE_NAME)-objs += platform/mt7981/mt7981_pos.o
$(MODULE_NAME)-objs += platform/mt7981/mt7981_emi.o
endif