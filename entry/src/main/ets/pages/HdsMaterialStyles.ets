import {
  hdsMaterial, HdsNavigationTitleBarOptions, ScrollEffectType, TitleBarContentOptions
} from '@kit.UIDesignKit';

/**
 * HdsNavigationBackgroundStyle.maskExtraHeight defaults to 32vp for GRADIENT_BLUR.
 * Share that documented extent with the content safe area; do not shorten the blur to move text.
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsnavigation
 */
export const TITLE_BLUR_EXTENSION: number = 32;

/** One titlebar contract for the library, settings and document destinations. */
export function scrollingTitleBar(content: TitleBarContentOptions): HdsNavigationTitleBarOptions {
  return {
    enableComponentSafeArea: true,
    content: content,
    style: {
      // ui-design-hds-component-material: false keeps the gradient blur active; it does NOT
      // disable blur. The button material is independent of the titlebar background effect.
      scrollEffectOpts: {
        enableScrollEffect: false,
        scrollEffectType: ScrollEffectType.GRADIENT_BLUR
      },
      originalStyle: { backgroundStyle: { maskExtraHeight: TITLE_BLUR_EXTENSION } },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    }
  };
}
