import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

/**
 * 参考华为菜单栏适配示例：系统材质按设备能力自动调整，背景模糊供不支持材质时使用。
 * https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-spatiality-immersive
 */
export function menuMaterialOptions(): MenuOptions {
  if (deviceInfo.apiAvailable('26.0.0')) {
    try {
      if (uiMaterial.isImmersiveMaterialSupported()) {
        return {
          backgroundBlurStyle: BlurStyle.COMPONENT_THICK,
          systemMaterial: new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.THICK,
            interactive: true,
            lightEffect: {}
          })
        };
      }
    } catch {
      // 能力查询失败时使用系统背景模糊。
    }
  }
  return { backgroundBlurStyle: BlurStyle.COMPONENT_THICK };
}
