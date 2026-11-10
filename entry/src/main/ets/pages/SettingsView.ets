import { PageScrollPolicy } from './PageScrollPolicy';
import { SettingsGroupStyle, SettingsListRow } from './SettingsListRow';
import { AppText } from '../i18n/AppText';
import { LANGUAGE_VALUES } from '../i18n/AppLanguage';

export const THEME_VALUES: string[] = ['system', 'light', 'dark'];
export { LANGUAGE_VALUES };

/** 二级页标题，和设置首页的行名一致。 */
export function settingTitle(section: string): string {
  if (section === 'language') return AppText.text($r('app.string.settings_language'));
  if (section === 'appearance') return AppText.text($r('app.string.settings_appearance'));
  if (section === 'privacy') return AppText.text($r('app.string.settings_privacy'));
  if (section === 'license-list') return AppText.text($r('app.string.settings_licenses'));
  if (section === 'project-license') return AppText.text($r('app.string.settings_project_license'));
  if (section === 'licenses') return AppText.text($r('app.string.settings_third_party'));
  if (section === 'help') return AppText.text($r('app.string.settings_help'));
  return AppText.text($r('app.string.settings_about'));
}

/** 把保存的主题取值翻成设置行右侧显示的文字。 */
export function themeLabel(choice: string): string {
  if (choice === 'light') return AppText.text($r('app.string.theme_light'));
  if (choice === 'dark') return AppText.text($r('app.string.theme_dark'));
  return AppText.text($r('app.string.theme_system'));
}

/** 把保存的语言取值翻成设置行右侧显示的文字。 */
export function languageLabel(choice: string): string {
  if (choice === 'zh-Hans') return AppText.text($r('app.string.language_zh'));
  if (choice === 'en-US') return AppText.text($r('app.string.language_en'));
  return AppText.text($r('app.string.language_system'));
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
  /** @Link keeps the displayed theme and language in sync with the owner when returning from a detail page. */
  @Link theme: string;
  @Link language: string;
  onOpen: (section: string) => void = (_section: string): void => {};
  onFeedback: () => void = (): void => {};

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
        this.LinkRow(AppText.text($r('app.string.settings_appearance')), themeLabel(this.theme), 'appearance')
        this.LinkRow(AppText.text($r('app.string.settings_language')), languageLabel(this.language), 'language')
      }.attributeModifier(this.groupStyle)
      ListItemGroup({ style: ListItemGroupStyle.CARD }) {
        this.LinkRow(AppText.text($r('app.string.settings_help')), '', 'help')
        ListItem({ style: ListItemStyle.CARD }) {
          SettingsListRow({ title: AppText.text($r('app.string.settings_feedback')), showArrow: true })
        }.onClick(() => this.onFeedback())
      }.attributeModifier(this.groupStyle)
      ListItemGroup({ style: ListItemGroupStyle.CARD }) {
        this.LinkRow(AppText.text($r('app.string.settings_privacy')), '', 'privacy')
        this.LinkRow(AppText.text($r('app.string.settings_about')), '', 'about')
      }.attributeModifier(this.groupStyle)
    }
    .attributeModifier(this.scrollPolicy)
    .width('100%')
    .height('100%')
  }
}
