import { LengthMetrics } from '@kit.ArkUI';
import { isRightToLeftLanguage } from '../i18n/AppLanguage';
import { listTitle, settingsValue } from './TextRoles';

/**
 * 设置列表共用行。文字、图标和单选标记使用华为组件体验示例中的系统资源：
 * https://gitcode.com/HarmonyOS_Samples/HarmonyOSComponentUXExamples/blob/dev/commons/componentuxexamplesbase/src/main/ets/common/CommonListRow.ets
 * https://gitcode.com/HarmonyOS_Samples/HarmonyOSComponentUXExamples/blob/dev/products/phone/src/main/ets/components/select/checkbox/components/ListSingleSelection.ets
 * https://gitcode.com/HarmonyOS_Samples/HarmonyOSComponentUXExamples/blob/dev/products/phone/src/main/ets/components/container/list/components/EfficientList.ets
 * 行的高度和按压态由外层 ListItemStyle.CARD 提供。
 */

@Component
export struct SettingsListRow {
  /** 传资源而不是取好的字符串，语言切换时由系统刷新，不必等所在页面重建。 */
  @Prop title: ResourceStr = '';
  @Prop value: ResourceStr = '';
  @Prop showArrow: boolean = false;
  @Prop selected: boolean = false;
  /** 语言名是从左到右的文字时，也要整段靠界面的起始侧，不改字符顺序。 */
  @StorageLink('marknote_language') language: string = 'default';

  /**
   * 文本方向跟随界面语言。textAlign 为 Start 时，从右到左则整段靠右，字符顺序仍由双向算法决定。
   * https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-internationalization
   */
  private labelDirection(): Direction {
    if (this.language === 'default') {
      return Direction.Auto;
    }
    return isRightToLeftLanguage(this.language) ? Direction.Rtl : Direction.Ltr;
  }

  private showsValue(): boolean {
    if (typeof this.value === 'string') {
      return this.value.length > 0;
    }
    return true;
  }

  build() {
    Row() {
      Text(this.title)
        .attributeModifier(listTitle)
        .layoutWeight(1)
        .direction(this.labelDirection())

      if (this.showsValue()) {
        Text(this.value)
          .attributeModifier(settingsValue)
          .direction(this.labelDirection())
          .margin({ end: LengthMetrics.vp(this.showArrow ? 8 : 0) })
      }

      if (this.showArrow) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize($r('sys.float.Title_M'))
          .fontColor([$r('sys.color.icon_fourth')])
      }

      if (this.selected) {
        // Official list-single-selection example shows the mark only on the selected row.
        // The row owns activation; the mark is not a second independent target.
        Checkbox()
          .shape(CheckBoxShape.CIRCLE)
          .select(true)
          .hitTestBehavior(HitTestMode.None)
          .accessibilityLevel('no')
      }
    }
    .width('100%')
    .height('100%')
  }
}

/**
 * The official ListSingleSelection example uses a 1px system divider with 12vp insets.
 * https://gitcode.com/HarmonyOS_Samples/HarmonyOSComponentUXExamples/blob/dev/products/phone/src/main/ets/components/select/checkbox/components/ListSingleSelection.ets
 */
export class SettingsGroupStyle implements AttributeModifier<ListItemGroupAttribute> {
  applyNormalAttribute(group: ListItemGroupAttribute): void {
    group.divider({
      strokeWidth: '1px',
      color: $r('sys.color.comp_divider'),
      startMargin: 12,
      endMargin: 12
    });
  }
}
