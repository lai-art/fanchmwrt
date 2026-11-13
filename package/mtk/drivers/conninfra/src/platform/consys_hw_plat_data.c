// SPDX-License-Identifier: GPL-2.0
/*
 * Copyright (c) 2019 MediaTek Inc.
 */
/*******************************************************************************
*                    E X T E R N A L   R E F E R E N C E S
********************************************************************************
*/
#include <linux/of_device.h>
/*
 * Linux 6.11 起 include/linux/of_device.h 被精简为只含前向声明
 * (struct of_device_id;), 真正的结构体定义在 mod_devicetable.h。
 * 6.6 及更早版本 of_device.h 会间接带出它, 6.12 不再带出,
 * 于是下面 apconninfra_of_ids[] 的数组元素类型变成不完整类型而编译失败:
 *   error: array type has incomplete element type 'struct of_device_id'
 * 显式包含以消除对头文件传递性包含的依赖。
 */
#include <linux/mod_devicetable.h>

#include "consys_hw.h"

/*******************************************************************************
*                            P U B L I C   D A T A
********************************************************************************
*/

/* Platform data */
#ifdef CONNINFRA_APSOC_MT7986
extern struct conninfra_plat_data mt7986_plat_data;
const struct of_device_id apconninfra_of_ids[] = {
	{
		.compatible = "mediatek,mt7986-consys",
		.data = (void*)&mt7986_plat_data,
	},
	{}
};
#endif

#ifdef CONNINFRA_APSOC_MT7981
extern struct conninfra_plat_data mt7981_plat_data;
const struct of_device_id apconninfra_of_ids[] = {
	{
		.compatible = "mediatek,mt7981-consys",
		.data = (void*)&mt7981_plat_data,
	},
	{}
};
#endif
