import { PageScrollPolicy } from './PageScrollPolicy';
import { SettingsGroupStyle, SettingsListRow } from './SettingsListRow';
import { THEME_LABELS, THEME_VALUES } from './SettingsView';

/**
 * 设置的内容页，按 section 渲染外观、隐私说明、许可证、关于或使用帮助。
 *
 * 标题栏和返回键由外层 HdsNavDestination 提供，这里只排内容。设置通过 HdsNavigation 路由展示，
 * 见 Index 里 Destination 的说明。
 *
 * 列表单选参考华为组件体验示例 ListSingleSelection：整行选择、仅在已选行显示系统勾选。
 * 选中状态来自 theme，切换颜色模式重新渲染时仍使用同一状态。
 */
@Component
export struct SettingsDetail {
  scroller: Scroller = new Scroller();
  private scrollPolicy: PageScrollPolicy<ListAttribute> = new PageScrollPolicy<ListAttribute>();
  private groupStyle: SettingsGroupStyle = new SettingsGroupStyle();
  /** 路由名，同时就是这一页的 section。 */
  @Prop section: string = 'about';
  /** 当前主题取值，和设置首页、Index 共用同一份状态。 */
  @Link theme: string;
  @Prop version: string = '';
  @Prop text: string = '';
  onOpen: (section: string) => void = (_section: string): void => {};
  onOpenProject: () => void = (): void => {};
  onChooseTheme: (choice: string) => void = (_choice: string): void => {};

  @Builder
  private RadioRow(title: string, choice: string) {
    ListItem({ style: ListItemStyle.CARD }) {
      SettingsListRow({ title: title, selected: this.theme === choice })
    }
    .onClick(() => this.onChooseTheme(choice))
    .accessibilityGroup(true)
    .accessibilityText(title)
    .accessibilityRole(AccessibilityRoleType.RADIO)
    .accessibilityChecked(this.theme === choice)
  }

  @Builder
  private InfoRow(title: string, status: string) {
    ListItem({ style: ListItemStyle.CARD }) {
      SettingsListRow({ title: title, value: status })
    }
  }

  @Builder
  private LinkRow(title: string, action: () => void) {
    ListItem({ style: ListItemStyle.CARD }) {
      SettingsListRow({ title: title, showArrow: true })
    }
    .onClick(action)
  }

  /**
   * 长正文不适合设置行的列表项结构，交给 ArkUI Text 默认排版。
   */
  @Builder
  private Paragraph(body: string, copyable: boolean = false) {
    Text(body)
      .textAlign(TextAlign.Start)
      .copyOption(copyable ? CopyOptions.LocalDevice : CopyOptions.None)
  }

  @Builder
  private HelpSection(title: string, body: string) {
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
            this.RadioRow(THEME_LABELS[THEME_VALUES.indexOf(choice)], choice)
          }, (choice: string) => choice)
        }.attributeModifier(this.groupStyle)
      } else if (this.section === 'license-list') {
        ListItemGroup({ style: ListItemGroupStyle.CARD }) {
          this.LinkRow('本项目开源许可证', () => this.onOpen('project-license'))
          this.LinkRow('第三方开源许可证', () => this.onOpen('licenses'))
        }.attributeModifier(this.groupStyle)
      } else if (this.section === 'about') {
        ListItemGroup({ style: ListItemGroupStyle.CARD }) {
          this.InfoRow('应用名称', 'MarkNote')
          this.InfoRow('版本', this.version.length > 0 ? this.version : '版本信息不可用')
          this.LinkRow('使用帮助', () => this.onOpen('help'))
          this.LinkRow('GitHub 项目主页', () => this.onOpenProject())
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
                  this.HelpSection('打开与保存', '在首页新建文稿或选择文件，也可以从其他应用打开支持的文件。' +
                    '如果原文件无法写入，保存时可以另存为；另存成功后会继续编辑新文件。' +
                    '文稿页可以分享当前内容，包括未保存的修改。分享的是临时副本，不会保存或覆盖原文件。' +
                    '删除会将原文件移入系统回收站，并提示未保存的修改；授权不足或文件已被其他应用修改时无法删除。')
                  this.HelpSection('编辑与预览', '在文稿底部切换预览、编辑和大纲。Markdown 和 LaTeX 文稿支持大纲；' +
                    '在宽屏设备上可以使用分栏，同时查看预览和编辑内容。' +
                    '宽屏双栏打开文稿时，可用标题栏按钮放大文稿或恢复列表，也可以在文稿菜单中关闭文稿。' +
                    '文稿页的更多菜单提供查找、结果间前后跳转和逐处替换。')
                  this.HelpSection('支持的格式', '支持 Markdown、纯文本、SVG 和 LaTeX 文件。' +
                    'Markdown 可以显示文稿同目录或子目录中、系统允许读取的本地图片；网络图片和未授权的图片只显示占位文字。' +
                    'LaTeX 可以预览常见文稿和数学公式，不编译 PDF；部分命令、引用的图片和 TikZ 图形暂无法显示。')
                  this.HelpSection('草稿与最近文稿', '编辑时会在设备上保存草稿，供异常退出后恢复。' +
                    '最近文稿只显示已获得持久访问授权的文件；更多菜单可以调整排序，长按记录可以移除。' +
                    '文稿页可收藏或取消收藏，首页上方可以切换到收藏列表。' +
                    '尚未保存或无法获得持久访问授权的文件需要先保存或另存为后才能收藏。')
                } else {
                  this.Paragraph('文稿在设备本地编辑。应用没有账号、广告、遥测或联网接口，也不上传文稿。' +
                    '文件由系统文件选择器授权，草稿保存在应用私有目录。')
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
