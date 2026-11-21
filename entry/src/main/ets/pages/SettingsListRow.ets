import { ComposeListItem, SymbolGlyphModifier } from '@kit.ArkUI';

/** CARD owns the row action. ComposeListItem lays out its title, status and accessory.
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ohos-arkui-advanced-composelistitem/
 */
@Component
export struct SettingsListRow {
  @Prop title: ResourceStr = '';
  @Prop value: ResourceStr | undefined = undefined;
  @Prop showArrow: boolean = false;
  @Prop selected: boolean = false;

  build() {
    ComposeListItem({
      contentItem: { primaryText: this.title },
      operateItem: {
        text: this.value,
        arrow: this.showArrow ? { value: $r('sys.symbol.chevron_right'),
          symbolStyle: new SymbolGlyphModifier($r('sys.symbol.chevron_right')) } : undefined,
        radio: this.selected ? { isCheck: true, accessibilityLevel: 'no' } : undefined
      }
    })
    .hitTestBehavior(HitTestMode.None)
  }
}

/** 设置里可点击的导航行。带右侧状态或单选标记的行仍由页面直接组合。 */
@Component
export struct SettingsActionRow {
  @Prop title: ResourceStr = '';
  onSelect: () => void = (): void => {};

  build() {
    ListItem({ style: ListItemStyle.CARD }) {
      SettingsListRow({ title: this.title, showArrow: true })
    }
    .onClick(() => this.onSelect())
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
