import { ComposeListItem, SymbolGlyphModifier } from '@kit.ArkUI';

export const THEME_VALUES: string[] = ['system', 'light', 'dark'];
export const THEME_LABELS: string[] = ['跟随系统', '浅色', '深色'];

/** 二级页标题，和设置首页的行名一致。 */
export function settingTitle(section: string): string {
  if (section === 'appearance') return '外观';
  if (section === 'privacy') return '隐私说明';
  if (section === 'licenses') return '第三方开源许可证';
  return '关于';
}

/** 把保存的主题取值翻成设置行右侧显示的文字。 */
export function themeLabel(choice: string): string {
  for (let index = 0; index < THEME_VALUES.length; index++) {
    if (THEME_VALUES[index] === choice) return THEME_LABELS[index];
  }
  return THEME_LABELS[0];
}

/**
 * 设置首页。这一层只放导航条目，正文在各自的二级页，和系统应用的设置页一致：
 * 卡片分组、行右侧写当前状态、再跟一个箭头。
 *
 * 行用官方 ComposeListItem，主标题、右侧文字和箭头都由组件按系统规范给出，
 * 不手写 Row + Text + SymbolGlyph，也不自己算行高和内边距。
 * 卡片用 ListItemGroupStyle.CARD 配 ListItemStyle.CARD，内外边距由系统给。
 * 隐私两组条目的分组标题沿用系统备忘录的写法，用 SubHeader 放在卡片外面。
 */
@Component
export struct SettingsView {
  /**
   * 用 @Link 而不是 @Prop：半模态的内容由 bindSheet 的 builder 持有，
   * @Prop 只在创建时取一次值，切完主题再回到首页，行右侧的状态不会跟着变。
   */
  @Link theme: string;
  @Prop version: string = '';
  onOpen: (section: string) => void = (_section: string): void => {};

  @Builder
  private LinkRow(title: string, status: string, section: string) {
    ListItem({ style: ListItemStyle.CARD }) {
      ComposeListItem({
        contentItem: { primaryText: title },
        operateItem: {
          text: status,
          arrow: {
            // arrow 的 value 必填，但 symbolStyle 优先级更高，实际显示的是这个系统符号。
            value: '',
            symbolStyle: new SymbolGlyphModifier($r('sys.symbol.chevron_forward'))
          }
        }
      })
    }
    .onClick(() => this.onOpen(section))
  }

  build() {
    // 卡片之间没有分组标题：官方设置页里，分组标题是小号的次要色文字，
    // 而且只在这组需要一个概括词时才出现。这里两组条目都是自解释的，
    // 加标题既没有文档依据，用 SubHeader 又比官方的字号大一倍多，所以不加。
    // 卡片是抬升的一层，页面底比它低一层，结构同《如何设置分组列表的圆角和间距》
    // (faqs-arkui-28)：外层容器给底色，卡片保持默认。底色由 HdsNavDestination
    // 根节点统一提供（见 Index 的 Destination），这里不再铺一层。
    Column() {
      List({ spaceWidth: $r('sys.float.padding_level6') }) {
        ListItemGroup({ style: ListItemGroupStyle.CARD }) {
          this.LinkRow('外观', themeLabel(this.theme), 'appearance')
        }
        ListItemGroup({ style: ListItemGroupStyle.CARD }) {
          this.LinkRow('隐私说明', '', 'privacy')
          this.LinkRow('第三方开源许可证', '', 'licenses')
        }
        ListItemGroup({ style: ListItemGroupStyle.CARD }) {
          this.LinkRow('关于', this.version.length > 0 ? `版本 ${this.version}` : '', 'about')
        }
      }
      .layoutWeight(1)
      // 边缘效果用 List 的默认值（滚动组件通用接口：List 默认 EdgeEffect.Spring）。
    }
    .width('100%')
    .height('100%')
  }
}
