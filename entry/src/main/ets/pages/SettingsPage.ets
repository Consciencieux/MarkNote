import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { scrollingTitleBar } from './HdsMaterialStyles';
import { SettingsView, settingTitle } from './SettingsView';
import { SettingsDetail } from './SettingsDetail';

/** Each route owns its controller, including while a sibling destination is transitioning. */
@Component
export struct SettingsPage {
  @Prop section: string = 'settings';
  @Link theme: string;
  /** 读一次语言，标题栏在导航页不重建时也会重新设置。 */
  @StorageLink('marknote_language') language: string = 'default';
  @Prop version: string = '';
  @Prop text: string = '';
  private scroller: Scroller = new Scroller();
  onOpen: (section: string) => void = (_section: string): void => {};
  onOpenProject: () => void = (): void => {};
  onFeedback: () => void = (): void => {};
  onBack: () => void = (): void => {};
  onChooseTheme: (choice: string) => void = (_choice: string): void => {};
  onChooseLanguage: (choice: string) => void = (_choice: string): void => {};

  private pageTitle(): Resource {
    if (this.language.length === 0) return $r('app.string.settings');
    return this.section === 'settings' ? $r('app.string.settings') : settingTitle(this.section);
  }

  build() {
    HdsNavDestination() {
      if (this.section === 'settings') {
        SettingsView({
          scroller: this.scroller, theme: $theme,
          onOpen: this.onOpen, onFeedback: this.onFeedback
        })
      } else {
        SettingsDetail({
          scroller: this.scroller, section: this.section, theme: $theme,
          version: this.version, text: this.text,
          onOpen: this.onOpen, onOpenProject: this.onOpenProject,
          onChooseTheme: this.onChooseTheme, onChooseLanguage: this.onChooseLanguage
        })
      }
    }
    .titleBar(scrollingTitleBar({
      title: { mainTitle: this.pageTitle() }
    }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    // 从语言页返回时，被盖住的设置首页可能还停在切换前的选项。重新对上 AppStorage 后再画右侧小字。
    .onShown((): void => {
      const stored = AppStorage.get<string>('marknote_language');
      if (stored !== undefined && stored !== this.language) {
        this.language = stored;
      }
    })
    // HdsNavDestination onBackPressed：返回 true 后由调用方处理页面栈。
    .onBackPressed(() => {
      this.onBack();
      return true;
    })
    .bindToScrollable([this.scroller])
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
