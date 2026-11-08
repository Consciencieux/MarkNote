import { uiMaterial } from '@kit.ArkUI';

/**
 * 沉浸材质随设备能力和系统设置调整；不支持时使用组件默认样式。
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-overview
 */
export function searchFieldMaterial(): uiMaterial.Material | undefined {
  return uiMaterial.isImmersiveMaterialSupported() ?
    new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THIN, colorInvert: true }) : undefined;
}

/**
 * 分段按钮背板用系统材质。样式取自《SegmentButtonV2》背景板材质示例的 ULTRA_THIN，
 * 并与编辑工具栏一样开启自动反色。不支持时由分段按钮使用自己的系统默认色。
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ohos-arkui-advanced-segmentbuttonv2
 */
export function segmentButtonMaterial(): uiMaterial.Material | undefined {
  return uiMaterial.isImmersiveMaterialSupported() ?
    new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      colorInvert: true,
      interactive: true,
      lightEffect: {}
    }) : undefined;
}

export function formatChipMaterial(): uiMaterial.Material | undefined {
  return uiMaterial.isImmersiveMaterialSupported() ?
    new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      colorInvert: true,
      // 横向滚动容器会裁切阴影；触摸光效仍由系统材质提供。
      applyShadow: false,
      lightEffect: {}
    }) : undefined;
}
