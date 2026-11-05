import { PageScrollPolicy } from './PageScrollPolicy';
import { HdsListItemCard, SuffixArrow, SuffixTextAndArrow } from '@kit.UIDesignKit';

export const THEME_VALUES: string[] = ['system', 'light', 'dark'];
export const THEME_LABELS: string[] = ['跟随系统', '浅色', '深色'];
export const TOOLBAR_POSITION_VALUES: string[] = ['top', 'left', 'right'];
export const TOOLBAR_POSITION_LABELS: string[] = ['顶部', '左侧', '右侧'];

/** 二级页标题，和设置首页的行名一致。 */
export function settingTitle(section: string): string {
  if (section === 'appearance') return '外观';
  if (section === 'toolbar') return '编辑工具栏位置';
  if (section === 'privacy') return '隐私说明';
  if (section === 'project-license') return '本项目开源许可证';
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
 * 设置首页。这一层只放导航条目，正文在各自的二级页。
 *
 * 行用 HdsListItemCard，照《设置列表卡片样式》（ui-design-set-listitem-style）：
 * ListItem 里直接放卡片，右侧状态和箭头使用官方 suffix 组件；不叠加额外卡片样式。
 */
@Component
export struct SettingsView {
  scroller: Scroller = new Scroller();
  private scrollPolicy: PageScrollPolicy<ListAttribute> = new PageScrollPolicy<ListAttribute>();
  /** @Link keeps the displayed theme in sync with the owner when returning from its detail page. */
  @Link theme: string;
  @Prop toolbarPosition: string = 'top';
  @Prop version: string = '';
  onOpen: (section: string) => void = (_section: string): void => {};

  @Builder
  private LinkRow(title: string, status: string, section: string) {
    // 有状态文字时用「文字 + 箭头」，没有状态时只留箭头。颜色都不填，用组件默认。
    if (status.length > 0) {
      ListItem() {
        HdsListItemCard({
          textItem: {
            primaryText: { text: title }
          },
          suffixItem: new SuffixTextAndArrow({ text: status }),
          onClick: (): void => this.onOpen(section)
        })
      }
    } else {
      ListItem() {
        HdsListItemCard({
          textItem: {
            primaryText: { text: title }
          },
          suffixItem: new SuffixArrow(),
          onClick: (): void => this.onOpen(section)
        })
      }
    }
  }

  build() {
    // 按官方《设置列表卡片样式》(ui-design-set-listitem-style) 示例设置卡片行间距。
    List({ space: 10, scroller: this.scroller }) {
      this.LinkRow('外观', themeLabel(this.theme), 'appearance')
      this.LinkRow('编辑工具栏位置', this.toolbarPosition === 'left' ? '左侧' :
        (this.toolbarPosition === 'right' ? '右侧' : '顶部'), 'toolbar')
      this.LinkRow('隐私说明', '', 'privacy')
      this.LinkRow('本项目开源许可证', '', 'project-license')
      this.LinkRow('第三方开源许可证', '', 'licenses')
      this.LinkRow('关于', this.version.length > 0 ? `版本 ${this.version}` : '', 'about')
    }
    .attributeModifier(this.scrollPolicy)
    .width('100%')
    .height('100%')
  }
}
