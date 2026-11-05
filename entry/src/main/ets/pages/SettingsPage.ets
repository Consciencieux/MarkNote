import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { scrollingTitleBar } from './HdsMaterialStyles';
import { SettingsView, settingTitle } from './SettingsView';
import { SettingsDetail } from './SettingsDetail';

/** Each route owns its controller, including while a sibling destination is transitioning. */
@Component
export struct SettingsPage {
  @Prop section: string = 'settings';
  @Link theme: string;
  @Prop toolbarPosition: string = 'top';
  @Prop version: string = '';
  @Prop text: string = '';
  private scroller: Scroller = new Scroller();
  onOpen: (section: string) => void = (_section: string): void => {};
  onOpenProject: () => void = (): void => {};
  onBack: () => void = (): void => {};
  onChooseTheme: (choice: string) => void = (_choice: string): void => {};
  onChooseToolbarPosition: (position: string) => void = (_position: string): void => {};

  build() {
    HdsNavDestination() {
      if (this.section === 'settings') {
        SettingsView({
          scroller: this.scroller, theme: $theme, toolbarPosition: this.toolbarPosition,
          onOpen: this.onOpen
        })
      } else {
        SettingsDetail({
          scroller: this.scroller, section: this.section, theme: $theme,
          toolbarPosition: this.toolbarPosition, version: this.version, text: this.text,
          onOpen: this.onOpen, onOpenProject: this.onOpenProject,
          onChooseTheme: this.onChooseTheme, onChooseToolbarPosition: this.onChooseToolbarPosition
        })
      }
    }
    .titleBar(scrollingTitleBar({
      title: { mainTitle: this.section === 'settings' ? '设置' : settingTitle(this.section) }
    }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    // HdsNavDestination onBackPressed：返回 true 后由调用方处理页面栈。
    .onBackPressed(() => {
      this.onBack();
      return true;
    })
    .bindToScrollable([this.scroller])
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
