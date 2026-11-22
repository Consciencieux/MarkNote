import { HdsListItemCard, SuffixArrow, SuffixRadio, SuffixText, SuffixTextAndArrow } from '@kit.UIDesignKit';

/**
 * 由原生 ListItem 承载列表项。HDS 处理行内标题、状态和箭头。
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdslistitemcard
 * 行卡片在组内使用零外边距和透明背景，沿用 EfficientList 的嵌入方式。
 * https://gitcode.com/HarmonyOS_Samples/HarmonyOSComponentUXExamples/blob/dev/products/phone/src/main/ets/components/container/list/components/EfficientList.ets
 */
@Component
export struct SettingsListRow {
  @Prop title: ResourceStr = '';
  @Prop value: ResourceStr | undefined = undefined;
  @Prop showArrow: boolean = false;
  @Prop selected: boolean | undefined = undefined;
  onSelect?: () => void;

  private suffix(): SuffixArrow | SuffixRadio | SuffixText | SuffixTextAndArrow | undefined {
    if (this.selected === true) {
      return new SuffixRadio({ isCheck: true, accessibilityOptions: { accessibilityLevel: 'no' } });
    }
    if (this.showArrow) {
      return this.value === undefined ? new SuffixArrow({}) : new SuffixTextAndArrow({ text: this.value }, {});
    }
    return this.value === undefined ? undefined : new SuffixText({ text: this.value });
  }

  build() {
    HdsListItemCard({
      textItem: { primaryText: { text: this.title } },
      suffixItem: this.suffix(),
      cardPrefixMargin: 0,
      cardSuffixMargin: 0,
      cardBackgroundColor: Color.Transparent,
      onClick: this.onSelect,
      accessibilityOptions: this.selected === undefined ? undefined : {
        accessibilityGroup: { isGroup: true },
        accessibilityText: this.title,
        accessibilityRole: AccessibilityRoleType.RADIO,
        accessibilitySelected: this.selected
      }
    })
  }
}

/**
 * 分割线使用系统颜色，起止缩进对齐组内行的内容区。
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-listitemgroup/
 */
export class SettingsGroupStyle implements AttributeModifier<ListItemGroupAttribute> {
  applyNormalAttribute(group: ListItemGroupAttribute): void {
    group.divider({
      strokeWidth: '1px',
      color: $r('sys.color.comp_divider'),
      startMargin: $r('sys.float.padding_level4'),
      endMargin: $r('sys.float.padding_level4')
    });
  }
}
