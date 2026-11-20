import {
  hdsMaterial, HdsNavigationIconOptions, HdsNavigationMenuItemOptions, HdsNavigationTitleBarOptions,
  ScrollEffectType, TitleBarContentOptions
} from '@kit.UIDesignKit';

/** https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-navigation-dynamic-blur */
export function scrollingTitleBar(content: TitleBarContentOptions): HdsNavigationTitleBarOptions {
  return {
    enableComponentSafeArea: true,
    content: content,
    style: {
      scrollEffectOpts: {
        enableScrollEffect: true,
        scrollEffectType: ScrollEffectType.GRADIENT_BLUR
      },
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
