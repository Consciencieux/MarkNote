import { ComposeListItem } from '@kit.ArkUI';
import { THEME_LABELS, THEME_VALUES } from './SettingsView';

/**
 * 设置的内容页，按 section 渲染四段内容之一：外观、隐私说明、第三方开源许可证、关于。
 *
 * 标题栏和返回键由外层 HdsNavDestination 提供，这里只排内容。设置整体走全屏页面，
 * 见 Index 里 Destination 的说明。
 *
 * 「外观」用带单选框的列表行：每行左侧是选项名，右侧是单选框，点整行和点单选框走同一个回调。
 * 单选框没有 group 参数（官方 Radio 的 group 只对 Radio 组件本身生效），
 * 互斥由 theme 这一个状态决定：isCheck 直接写 this.theme === choice，
 * onChange 只处理选中，不处理取消，避免出现一个都没选中的状态。
 */
@Component
export struct SettingsDetail {
  /** 路由名，同时就是这一页的 section：appearance、privacy、licenses、about。 */
  @Prop section: string = 'about';
  /** 当前主题取值，和设置首页、Index 共用同一份状态。 */
  @Link theme: string;
  @Prop version: string = '';
  @Prop text: string = '';
  onChooseTheme: (choice: string) => void = (_choice: string): void => {};

  @Builder
  private RadioRow(title: string, choice: string) {
    ListItem({ style: ListItemStyle.CARD }) {
      ComposeListItem({
        contentItem: { primaryText: title },
        operateItem: {
          radio: {
            isCheck: this.theme === choice,
            onChange: (isChecked: boolean): void => {
              if (isChecked) this.onChooseTheme(choice);
            }
          }
        }
      })
    }
    .width('100%')
    .onClick(() => this.onChooseTheme(choice))
  }

  @Builder
  private InfoRow(title: string, status: string) {
    ListItem({ style: ListItemStyle.CARD }) {
      ComposeListItem({
        contentItem: { primaryText: title },
        operateItem: { text: status }
      })
    }
  }

  @Builder
  private Paragraph(body: string, mono: boolean = false) {
    Text(body)
      .fontSize(mono ? $r('sys.float.ohos_id_text_size_body2') : $r('sys.float.ohos_id_text_size_body1'))
      .fontColor($r('sys.color.font_primary'))
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
      .copyOption(mono ? CopyOptions.LocalDevice : CopyOptions.None)
  }

  build() {
    Column() {
      if (this.section === 'appearance') {
        List() {
          ListItemGroup({ style: ListItemGroupStyle.CARD }) {
            ForEach(THEME_VALUES, (choice: string) => {
              this.RadioRow(THEME_LABELS[THEME_VALUES.indexOf(choice)], choice)
            }, (choice: string) => choice)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
      } else if (this.section === 'about') {
        List() {
          ListItemGroup({ style: ListItemGroupStyle.CARD }) {
            this.InfoRow('应用名称', 'MarkNote')
            this.InfoRow('版本', this.version.length > 0 ? this.version : '版本信息不可用')
          }
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
      } else {
        Scroll() {
          if (this.section === 'licenses') {
            this.Paragraph(this.text, true)
          } else {
            this.Paragraph('文稿在设备本地编辑。应用没有账号、广告、遥测或联网接口，也不上传文稿。' +
              '文件由系统文件选择器授权，草稿保存在应用私有目录。')
          }
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    // 与设置首页一致：页面底比卡片低一层，结构同 faqs-arkui-28。
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
