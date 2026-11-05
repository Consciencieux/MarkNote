import { PageScrollPolicy } from './PageScrollPolicy';
import { HdsListItemCard, SuffixRadio, SuffixText } from '@kit.UIDesignKit';
import {
  THEME_LABELS, THEME_VALUES, TOOLBAR_POSITION_LABELS, TOOLBAR_POSITION_VALUES
} from './SettingsView';

/**
 * 设置的内容页，按 section 渲染外观、编辑工具栏位置、隐私说明、本项目开源许可证、第三方开源许可证或关于。
 *
 * 标题栏和返回键由外层 HdsNavDestination 提供，这里只排内容。设置通过 HdsNavigation 路由展示，
 * 见 Index 里 Destination 的说明。
 *
 * 列表行同样用 HdsListItemCard（《设置列表卡片样式》ui-design-set-listitem-style）：
 * 外观右侧是单选框，关于右侧是状态文字。
 * 单选框的颜色不填。互斥由 theme 这一个状态决定：isCheck 直接写 this.theme === choice，
 * onChange 只处理选中，不处理取消，避免出现一个都没选中的状态。
 */
@Component
export struct SettingsDetail {
  scroller: Scroller = new Scroller();
  private scrollPolicy: PageScrollPolicy<ListAttribute> = new PageScrollPolicy<ListAttribute>();
  /** 路由名，同时就是这一页的 section：appearance、privacy、project-license、licenses、about。 */
  @Prop section: string = 'about';
  /** 当前主题取值，和设置首页、Index 共用同一份状态。 */
  @Link theme: string;
  @Prop toolbarPosition: string = 'top';
  @Prop version: string = '';
  @Prop text: string = '';
  onChooseTheme: (choice: string) => void = (_choice: string): void => {};
  onChooseToolbarPosition: (position: string) => void = (_position: string): void => {};

  @Builder
  private RadioRow(title: string, choice: string) {
    ListItem() {
      HdsListItemCard({
        textItem: {
          primaryText: { text: title }
        },
        suffixItem: new SuffixRadio({
          isCheck: this.theme === choice,
          onChange: (isChecked: boolean): void => {
            if (isChecked) this.onChooseTheme(choice);
          }
        }),
        onClick: (): void => this.onChooseTheme(choice)
      })
    }
  }

  @Builder
  private InfoRow(title: string, status: string) {
    ListItem() {
      HdsListItemCard({
        textItem: {
          primaryText: { text: title }
        },
        suffixItem: new SuffixText({ text: status })
      })
    }
  }

  @Builder
  private ToolbarPositionRow(title: string, position: string) {
    ListItem() {
      HdsListItemCard({
        textItem: {
          primaryText: { text: title }
        },
        suffixItem: new SuffixRadio({
          isCheck: this.toolbarPosition === position,
          onChange: (isChecked: boolean): void => {
            if (isChecked) this.onChooseToolbarPosition(position);
          }
        }),
        onClick: (): void => this.onChooseToolbarPosition(position)
      })
    }
  }

  /**
   * 长正文不适合 HdsListItemCard 的列表项结构，交给 ArkUI Text 默认排版。
   */
  @Builder
  private Paragraph(body: string, mono: boolean = false) {
    Text(body)
      .width('100%')
      .copyOption(mono ? CopyOptions.LocalDevice : CopyOptions.None)
  }

  build() {
    // 与设置首页同样的分层：页面底由 HdsNavDestination 根节点提供，
    // 每一行是一张 HdsListItemCard，不另套 ListItemGroup 的卡片内边距。
    List({ space: this.section === 'privacy' || this.section === 'project-license' || this.section === 'licenses' ? 0 : 10,
      scroller: this.scroller }) {
      if (this.section === 'appearance') {
        ForEach(THEME_VALUES, (choice: string) => {
          this.RadioRow(THEME_LABELS[THEME_VALUES.indexOf(choice)], choice)
        }, (choice: string) => choice)
      } else if (this.section === 'toolbar') {
        ForEach(TOOLBAR_POSITION_VALUES, (position: string) => {
          this.ToolbarPositionRow(TOOLBAR_POSITION_LABELS[TOOLBAR_POSITION_VALUES.indexOf(position)], position)
        }, (position: string) => position)
      } else if (this.section === 'about') {
        this.InfoRow('应用名称', 'MarkNote')
        this.InfoRow('版本', this.version.length > 0 ? this.version : '版本信息不可用')
      } else {
        ListItem() {
          if (this.section === 'licenses' || this.section === 'project-license') {
            this.Paragraph(this.text, true)
          } else {
            this.Paragraph('文稿在设备本地编辑。应用没有账号、广告、遥测或联网接口，也不上传文稿。' +
              '文件由系统文件选择器授权，草稿保存在应用私有目录。')
          }
        }
      }
    }
    .attributeModifier(this.scrollPolicy)
    .width('100%')
    .height('100%')
  }
}
