/**
 * 设置列表共用行。文字、图标和单选标记使用华为组件体验示例中的系统资源：
 * https://gitcode.com/HarmonyOS_Samples/HarmonyOSComponentUXExamples/blob/dev/commons/componentuxexamplesbase/src/main/ets/common/CommonListRow.ets
 * https://gitcode.com/HarmonyOS_Samples/HarmonyOSComponentUXExamples/blob/dev/products/phone/src/main/ets/components/select/checkbox/components/ListSingleSelection.ets
 * https://gitcode.com/HarmonyOS_Samples/HarmonyOSComponentUXExamples/blob/dev/products/phone/src/main/ets/components/container/list/components/EfficientList.ets
 * 行的高度和按压态由外层 ListItemStyle.CARD 提供。
 */
@Component
export struct SettingsListRow {
  @Prop title: string = '';
  @Prop value: string = '';
  @Prop showArrow: boolean = false;
  @Prop selected: boolean = false;

  build() {
    Row() {
      Text(this.title)
        .fontSize($r('sys.float.Subtitle_M'))
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)

      if (this.value.length > 0) {
        Text(this.value)
          .fontSize($r('sys.float.Subtitle_S'))
          .fontColor($r('sys.color.font_secondary'))
          .margin({ right: this.showArrow ? 8 : 0 })
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
