import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

/**
 * 应用级沉浸光感默认覆盖菜单；MatePad 的 SMOOTH 档实机出现菜单背板透明。
 * 对低算力或不支持材质的设备，单独关闭菜单材质，让系统菜单绘制默认背板；
 * 这是兼容处理，并非华为要求所有低算力设备关闭材质。
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-uimaterial
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-enable
 */
export function menuMaterialOptions(): MenuOptions {
  if (!deviceInfo.apiAvailable('26.0.0')) {
    return {};
  }

  try {
    if (!uiMaterial.isImmersiveMaterialSupported() ||
      uiMaterial.getGlobalMaterialLevel() === uiMaterial.MaterialLevel.SMOOTH) {
      return { systemMaterial: uiMaterial.Material.empty };
    }
  } catch {
    // 无法判断设备能力时，优先让菜单回到系统默认样式。
    return { systemMaterial: uiMaterial.Material.empty };
  }

  return {};
}
