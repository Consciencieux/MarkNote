import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

/**
 * 菜单在 SMOOTH 档位实测可能失去背板；仅对菜单关闭应用级材质，使用系统默认背板。
 * 这是针对菜单透明问题的兼容处理，不表示低算力设备不支持沉浸材质。
 * Material.empty 是华为提供的组件级关闭接口：
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-uimaterial
 * 高、中算力档沿用华为菜单栏适配示例：
 * https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-spatiality-immersive
 */
export function menuMaterialOptions(): MenuOptions {
  if (deviceInfo.apiAvailable('26.0.0')) {
    try {
      if (!uiMaterial.isImmersiveMaterialSupported() ||
        uiMaterial.getGlobalMaterialLevel() === uiMaterial.MaterialLevel.SMOOTH) {
        return { systemMaterial: uiMaterial.Material.empty };
      }
      return {
        backgroundBlurStyle: BlurStyle.COMPONENT_THICK,
        systemMaterial: new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THICK,
          interactive: true,
          lightEffect: {}
        })
      };
    } catch {
      // 查询失败时避免应用级材质使菜单背板透明。
      return { systemMaterial: uiMaterial.Material.empty };
    }
  }
  return {};
}
