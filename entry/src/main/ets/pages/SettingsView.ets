import { PageScrollPolicy } from './PageScrollPolicy';
import { SettingsGroupStyle, SettingsListRow } from './SettingsListRow';

export const THEME_VALUES: string[] = ['system', 'light', 'dark'];
export const THEME_LABELS: string[] = ['跟随系统', '浅色', '深色'];

/** 二级页标题，和设置首页的行名一致。 */
export function settingTitle(section: string): string {
  if (section === 'appearance') return '外观';
  if (section === 'privacy') return '隐私说明';
  if (section === 'license-list') return '开源许可证';
  if (section === 'project-license') return '本项目开源许可证';
  if (section === 'licenses') return '第三方开源许可证';
  if (section === 'help') return '使用帮助';
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
 * 设置首页。这一层只放导航条目，正文在各自的二级页。
 *
 * ListItemGroup 和 ListItem 的 CARD 样式负责分组背板及行交互。
 * 参见官方 ts-container-listitemgroup 和 ts-container-listitem。
 */
@Component
export struct SettingsView {
  scroller: Scroller = new Scroller();
  private scrollPolicy: PageScrollPolicy<ListAttribute> = new PageScrollPolicy<ListAttribute>();
  private groupStyle: SettingsGroupStyle = new SettingsGroupStyle();
  /** @Link keeps the displayed theme in sync with the owner when returning from its detail page. */
  @Link theme: string;
  onOpen: (section: string) => void = (_section: string): void => {};

  @Builder
  private LinkRow(title: string, status: string, section: string) {
    ListItem({ style: ListItemStyle.CARD }) {
      SettingsListRow({ title: title, value: status, showArrow: true })
    }
    .onClick(() => this.onOpen(section))
  }

  build() {
    List({ spaceWidth: $r('sys.float.padding_level6'), scroller: this.scroller }) {
      ListItemGroup({ style: ListItemGroupStyle.CARD }) {
        this.LinkRow('外观', themeLabel(this.theme), 'appearance')
      }.attributeModifier(this.groupStyle)
      ListItemGroup({ style: ListItemGroupStyle.CARD }) {
        this.LinkRow('隐私说明', '', 'privacy')
        this.LinkRow('开源许可证', '', 'license-list')
        this.LinkRow('关于', '', 'about')
      }.attributeModifier(this.groupStyle)
    }
    .attributeModifier(this.scrollPolicy)
    .width('100%')
    .height('100%')
  }
}
