import { PageScrollPolicy } from './PageScrollPolicy';
import { SettingsGroupStyle, SettingsListRow } from './SettingsListRow';
import { LANGUAGE_VALUES } from '../i18n/AppLanguage';

export const THEME_VALUES: string[] = ['system', 'light', 'dark'];
export const CODE_THEME_VALUES: string[] = ['off', 'github', 'atom', 'vs'];
export { LANGUAGE_VALUES };

/** 二级页标题，和设置首页的行名一致。返回资源，标题栏会随语言刷新。 */
export function settingTitle(section: string): Resource {
  if (section === 'language') return $r('app.string.settings_language');
  if (section === 'appearance') return $r('app.string.settings_appearance');
  if (section === 'code-theme') return $r('app.string.settings_code_theme');
  if (section === 'privacy') return $r('app.string.settings_privacy');
  if (section === 'license-list') return $r('app.string.settings_licenses');
  if (section === 'project-license') return $r('app.string.settings_project_license');
  if (section === 'licenses') return $r('app.string.settings_third_party');
  if (section === 'help') return $r('app.string.settings_help');
  return $r('app.string.settings_about');
}

export function codeThemeLabel(choice: string): Resource {
  if (choice === 'off') return $r('app.string.code_theme_off');
  if (choice === 'atom') return $r('app.string.code_theme_atom');
  if (choice === 'vs') return $r('app.string.code_theme_vs');
  return $r('app.string.code_theme_github');
}

/** 把保存的主题取值翻成设置行右侧的资源。 */
export function themeLabel(choice: string): Resource {
  if (choice === 'light') return $r('app.string.theme_light');
  if (choice === 'dark') return $r('app.string.theme_dark');
  return $r('app.string.theme_system');
}

/** 把保存的语言取值翻成设置行右侧的资源。语言名称在各语言里都用自称。 */
export function languageLabel(choice: string): Resource {
  if (choice === 'zh-Hans') return $r('app.string.language_zh');
  if (choice === 'zh-Hant') return $r('app.string.language_zh_hant');
  if (choice === 'bo') return $r('app.string.language_bo');
  if (choice === 'en-US') return $r('app.string.language_en');
  if (choice === 'ja') return $r('app.string.language_ja');
  if (choice === 'ko') return $r('app.string.language_ko');
  if (choice === 'ru') return $r('app.string.language_ru');
  if (choice === 'ar') return $r('app.string.language_ar');
  if (choice === 'ug') return $r('app.string.language_ug');
  return $r('app.string.language_system');
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
  /** @Link keeps the displayed theme in sync with the owner when returning from a detail page. */
  @Link theme: string;
  /** 导航页不会跟着首页的 @Link 重建，语言从 AppStorage 取。 */
  @StorageLink('marknote_language') language: string = 'default';
  @StorageLink('marknote_code_theme') codeTheme: string = 'github';
  onOpen: (section: string) => void = (_section: string): void => {};
  onFeedback: () => void = (): void => {};

  @Builder
  private LinkRow(title: ResourceStr, section: string) {
    ListItem({ style: ListItemStyle.CARD }) {
      SettingsListRow({ title: title, showArrow: true })
    }
    .onClick(() => this.onOpen(section))
  }

  build() {
    List({ spaceWidth: $r('sys.float.padding_level6'), scroller: this.scroller }) {
      ListItemGroup({ style: ListItemGroupStyle.CARD }) {
        // 外观行直接绑定当前主题。键若跟着主题变化，ForEach 会拆掉原行再新建。
        // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-rendering-control-foreach
        ListItem({ style: ListItemStyle.CARD }) {
          SettingsListRow({
            title: $r('app.string.settings_appearance'),
            value: themeLabel(this.theme),
            showArrow: true
          })
        }
        .onClick(() => this.onOpen('appearance'))
        // 语言行的右侧文字取决于当前语言。@Builder 默认按值传参，两个及以上参数时状态变化不会刷新函数内的 UI。
        // 所以这一行直接写在 build 里，并用当前语言当键重建。
        // https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-builder
        ForEach([this.language], (choice: string) => {
          ListItem({ style: ListItemStyle.CARD }) {
            SettingsListRow({
              title: $r('app.string.settings_language'),
              value: languageLabel(choice),
              showArrow: true
            })
          }
          .onClick(() => this.onOpen('language'))
        }, (choice: string) => choice)
      }.attributeModifier(this.groupStyle)
      ListItemGroup({ style: ListItemGroupStyle.CARD }) {
        ListItem({ style: ListItemStyle.CARD }) {
          SettingsListRow({ title: $r('app.string.settings_code_theme'), value: codeThemeLabel(this.codeTheme), showArrow: true })
        }
        .onClick(() => this.onOpen('code-theme'))
      }.attributeModifier(this.groupStyle)
      ListItemGroup({ style: ListItemGroupStyle.CARD }) {
        this.LinkRow($r('app.string.settings_help'), 'help')
        ListItem({ style: ListItemStyle.CARD }) {
          SettingsListRow({ title: $r('app.string.settings_feedback'), showArrow: true })
        }.onClick(() => this.onFeedback())
      }.attributeModifier(this.groupStyle)
      ListItemGroup({ style: ListItemGroupStyle.CARD }) {
        this.LinkRow($r('app.string.settings_privacy'), 'privacy')
        this.LinkRow($r('app.string.settings_about'), 'about')
      }.attributeModifier(this.groupStyle)
    }
    .attributeModifier(this.scrollPolicy)
    .width('100%')
    .height('100%')
  }
}
