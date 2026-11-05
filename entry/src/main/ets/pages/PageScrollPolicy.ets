import { HdsTabsAttribute } from '@kit.UIDesignKit';
import { TITLE_BLUR_EXTENSION } from './HdsMaterialStyles';

/**
 * Shared by native Scroll and List; controllers remain local to each page/tab.
 * safeAreaPadding lays out the first item below the extra titlebar mask. SAFE_AREA lets moving
 * content paint back into that area and the surrounding HDS component safe area.
 * Sources: arkts-develop-apply-immersive-effects (滚动类场景),
 * ts-container-scrollable-common (clipContent / edgeEffect / autoAdjustScrollBarMargin),
 * faqs-arkui-271 (cross-file AttributeModifier reuse).
 */
export class PageScrollPolicy<T extends ScrollAttribute | ListAttribute> implements AttributeModifier<T> {
  applyNormalAttribute(instance: T): void {
    instance
      .safeAreaPadding({ top: TITLE_BLUR_EXTENSION })
      .clipContent(ContentClipMode.SAFE_AREA)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Auto)
      // API 26: keep the indicator out of padding and component safe areas without measuring them.
      .autoAdjustScrollBarMargin(true);
  }
}

/**
 * TabContent clips by default. Release the ancestor clip as well as configuring Scroll's
 * content clip; otherwise the HDS titlebar can only blur the empty page background.
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-tabcontent
 */
export class PageTabContentPolicy implements AttributeModifier<TabContentAttribute> {
  applyNormalAttribute(instance: TabContentAttribute): void {
    instance.clip(false);
  }
}

/**
 * Tabs and TabContent each clip by default; both must release their clip for content to pass
 * through the component-safe titlebar. This is a page-container rule, not a Scroll rule.
 * Huawei FAQ: 嵌套Tabs时渐变导航无法穿透标题栏的解决方法 (faqs-arkui-component-3).
 */
export class PageTabsPolicy implements AttributeModifier<HdsTabsAttribute> {
  applyNormalAttribute(instance: HdsTabsAttribute): void {
    instance.clip(false);
  }
}
