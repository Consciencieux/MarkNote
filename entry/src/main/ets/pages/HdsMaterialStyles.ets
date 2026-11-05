import { hdsMaterial, ScrollEffectType, SystemMaterialParams, TitleBarStyleOptions } from '@kit.UIDesignKit';

/** 华为《沉浸光感》(ui-design-hds-component-material) 推荐的标题栏按钮自适应材质。 */
function adaptiveSystemMaterial(): SystemMaterialParams {
  return {
    materialType: hdsMaterial.MaterialType.ADAPTIVE,
    materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
  };
}

export function adaptiveHdsTitleBarStyle(): TitleBarStyleOptions {
  return { systemMaterialEffect: adaptiveSystemMaterial() };
}

/**
 * HDS titlebar button material without a full-width titlebar blur backdrop.
 * The API keeps only originalStyle active when enableScrollEffect is false;
 * COMMON_BLUR's default backdrop is transparent (ui-design-hdsnavigation).
 */
export function adaptiveFloatingHdsTitleBarStyle(): TitleBarStyleOptions {
  return {
    scrollEffectOpts: {
      enableScrollEffect: false,
      scrollEffectType: ScrollEffectType.COMMON_BLUR
    },
    systemMaterialEffect: adaptiveSystemMaterial()
  };
}

/** ui-design-navigation-dynamic-blur: use GRADIENT_BLUR for immersion; keep it fixed because
 * Web, TextArea, and TreeView do not share an HDS-bindable Scroller for dynamic titlebar effects. */
export function adaptiveBlurredHdsTitleBarStyle(): TitleBarStyleOptions {
  return {
    scrollEffectOpts: {
      enableScrollEffect: false,
      scrollEffectType: ScrollEffectType.GRADIENT_BLUR
    },
    systemMaterialEffect: adaptiveSystemMaterial()
  };
}
