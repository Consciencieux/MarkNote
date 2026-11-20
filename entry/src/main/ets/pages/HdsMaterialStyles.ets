import {
  hdsMaterial, HdsNavigationIconOptions, HdsNavigationMenuItemOptions, HdsNavigationTitleBarOptions,
  ScrollEffectType, TitleBarContentOptions
} from '@kit.UIDesignKit';

/**
 * HdsNavigationBackgroundStyle.maskExtraHeight defaults to 32vp for GRADIENT_BLUR.
 * Share that documented extent with the content safe area; do not shorten the blur to move text.
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsnavigation
 */
export const TITLE_BLUR_EXTENSION: number = 32;

/** One titlebar contract for the library, settings and document destinations. */
export function scrollingTitleBar(content: TitleBarContentOptions, followScroll: boolean = false): HdsNavigationTitleBarOptions {
  return {
    enableComponentSafeArea: true,
    content: content,
    style: {
      // Settings fades in the gradient as the list scrolls. Library and document pages keep it active.
      scrollEffectOpts: {
        enableScrollEffect: followScroll,
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

/** 标题栏菜单项的数据。页面自己决定有哪些项、顺序和动作。 */
export function navigationMenuIcon(label: ResourceStr, symbol: Resource, id: string,
  action: () => void, enabled: boolean = true): HdsNavigationMenuItemOptions {
  const content: HdsNavigationIconOptions = {
    label: label,
    icon: symbol,
    isEnabled: enabled,
    action: action,
    componentId: id
  };
  const item: HdsNavigationMenuItemOptions = { content: content };
  return item;
}
