import { PageScrollPolicy } from './PageScrollPolicy';
import { SettingsGroupStyle, SettingsListRow } from './SettingsListRow';
import { LANGUAGE_VALUES, THEME_VALUES, languageLabel, themeLabel } from './SettingsView';

/**
 * 单选行不用 @Builder 传递 selected。官方规定两个及以上参数的 @Builder 不会随状态刷新。
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-builder
 */
@Component
struct SettingsChoiceRow {
  @Prop title: Resource = $r('app.string.settings');
  @Prop selected: boolean = false;
  onSelect: () => void = (): void => {};

  build() {
    ListItem({ style: ListItemStyle.CARD }) {
      SettingsListRow({ title: this.title, selected: this.selected })
    }
    .onClick(() => this.onSelect())
    .accessibilityGroup(true)
    .accessibilityText(this.title)
    .accessibilityRole(AccessibilityRoleType.RADIO)
    .accessibilityChecked(this.selected)
  }
}

/**
 * 设置的内容页，按 section 渲染外观、隐私说明、许可证、关于或使用帮助。
 *
 * 标题栏和返回键由外层 HdsNavDestination 提供，这里只排内容。设置通过 HdsNavigation 路由展示，
 * 见 Index 里 Destination 的说明。
 *
 * 列表单选参考华为组件体验示例 ListSingleSelection：整行选择、仅在已选行显示系统勾选。
 * 选中状态来自主题和语言，返回这一页时仍对应当前选项。
 */
@Component
export struct SettingsDetail {
  scroller: Scroller = new Scroller();
  private scrollPolicy: PageScrollPolicy<ListAttribute> = new PageScrollPolicy<ListAttribute>();
  private groupStyle: SettingsGroupStyle = new SettingsGroupStyle();
  /** 路由名，同时就是这一页的 section。 */
  @Prop section: string = 'about';
  /** 当前主题和语言取值，和设置首页、Index 共用同一份状态。 */
  @Link theme: string;
  /** 导航页不会跟着首页的 @Link 重建，语言从 AppStorage 取。 */
  @StorageLink('marknote_language') language: string = 'default';
  @Prop version: string = '';
  @Prop text: string = '';
  onOpen: (section: string) => void = (_section: string): void => {};
  onOpenProject: () => void = (): void => {};
  onChooseTheme: (choice: string) => void = (_choice: string): void => {};
  onChooseLanguage: (choice: string) => void = (_choice: string): void => {};

  @Builder
  private InfoRow(title: ResourceStr, status: ResourceStr) {
    ListItem({ style: ListItemStyle.CARD }) {
      SettingsListRow({ title: title, value: status })
    }
  }

  @Builder
  private LinkRow(title: ResourceStr, action: () => void) {
    ListItem({ style: ListItemStyle.CARD }) {
      SettingsListRow({ title: title, showArrow: true })
    }
    .onClick(action)
  }

  /**
   * 长正文不适合设置行的列表项结构，交给 ArkUI Text 默认排版。
   */
  @Builder
  private Paragraph(body: string | Resource, copyable: boolean = false) {
    Text(body)
      .textAlign(TextAlign.Start)
      .copyOption(copyable ? CopyOptions.LocalDevice : CopyOptions.None)
  }

  @Builder
  private HelpSection(title: Resource, body: Resource) {
    Text(title)
      .fontSize($r('sys.float.Subtitle_M'))
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_primary'))
      .margin({ top: $r('sys.float.padding_level8'), bottom: $r('sys.float.padding_level4') })
    this.Paragraph(body)
  }

  build() {
    List({ scroller: this.scroller }) {
      if (this.section === 'appearance') {
        ListItemGroup({ style: ListItemGroupStyle.CARD }) {
          ForEach(THEME_VALUES, (choice: string) => {
            SettingsChoiceRow({
              title: themeLabel(choice),
              selected: this.theme === choice,
              onSelect: (): void => this.onChooseTheme(choice)
            })
          }, (choice: string) => `${this.theme}:${choice}`)
        }.attributeModifier(this.groupStyle)
      } else if (this.section === 'language') {
        ListItemGroup({ style: ListItemGroupStyle.CARD }) {
          ForEach(LANGUAGE_VALUES, (choice: string) => {
            SettingsChoiceRow({
              title: languageLabel(choice),
              selected: this.language === choice,
              onSelect: (): void => this.onChooseLanguage(choice)
            })
          }, (choice: string) => `${this.language}:${choice}`)
        }.attributeModifier(this.groupStyle)
      } else if (this.section === 'license-list') {
        ListItemGroup({ style: ListItemGroupStyle.CARD }) {
          this.LinkRow($r('app.string.settings_project_license'), () => this.onOpen('project-license'))
          this.LinkRow($r('app.string.settings_third_party'), () => this.onOpen('licenses'))
        }.attributeModifier(this.groupStyle)
      } else if (this.section === 'about') {
        ListItemGroup({ style: ListItemGroupStyle.CARD }) {
          this.InfoRow($r('app.string.about_name'), $r('app.string.EntryAbility_label'))
          this.InfoRow($r('app.string.about_version'),
            this.version.length > 0 ? this.version : $r('app.string.about_version_unavailable'))
          this.LinkRow($r('app.string.about_github'), () => this.onOpenProject())
          this.LinkRow($r('app.string.settings_licenses'), () => this.onOpen('license-list'))
        }.attributeModifier(this.groupStyle)
      } else {
        ListItem() {
          // 华为《响应式布局》栅格嵌套示例：12 列下按断点居中占 12/10/8 列。
          // 以组件宽度判定断点，使分栏和自由窗口也能适配；基础栅格左右边距为 24vp。
          // https://developer.huawei.com/consumer/cn/doc/doccenter-multi-device/bpta-multi-device-responsive-layout
          GridRow({ columns: 12, breakpoints: { reference: BreakpointsReference.ComponentSize } }) {
            GridCol({
              span: { xs: 12, sm: 12, md: 10, lg: 8 },
              offset: { xs: 0, sm: 0, md: 1, lg: 2 }
            }) {
              Column() {
                if (this.section === 'licenses' || this.section === 'project-license') {
                  this.Paragraph(this.text, true)
                } else if (this.section === 'help') {
                  this.HelpSection($r('app.string.help_open_title'), $r('app.string.help_open_body'))
                  this.HelpSection($r('app.string.help_edit_title'), $r('app.string.help_edit_body'))
                  this.HelpSection($r('app.string.help_format_title'), $r('app.string.help_format_body'))
                  this.HelpSection($r('app.string.help_draft_title'), $r('app.string.help_draft_body'))
                  this.HelpSection($r('app.string.help_feedback_title'), $r('app.string.help_feedback_body'))
                } else {
                  this.Paragraph($r('app.string.privacy_body'))
                }
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
            }
          }
          .width('100%')
          .padding({ left: 24, right: 24 })
        }
      }
    }
    .attributeModifier(this.scrollPolicy)
    .width('100%')
    .height('100%')
  }
}
