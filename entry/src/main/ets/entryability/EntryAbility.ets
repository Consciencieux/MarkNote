import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { KeyboardAvoidMode, window } from '@kit.ArkUI';
import { LaunchRequests } from '../document/LaunchRequests';
import { applyAppLanguage } from '../i18n/AppLanguage';
import { AppText } from '../i18n/AppText';
import { LocalState } from '../storage/LocalState';

// The title bar keeps its own safe area. The caret stays visible when the keyboard opens.
// File opens share this singleton ability. The page consumes the request after it exists.
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppText.bind(this.context);
    // 页面创建前先按已保存的选择加载资源，避免首帧还是上一种语言。
    try {
      applyAppLanguage(LocalState.readLanguageSync(this.context));
    } catch { /* 设置失败时继续使用系统当前的应用语言。 */ }
    LaunchRequests.deliver(want);
    void launchParam;
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    LaunchRequests.deliver(want);
    void launchParam;
  }

  onWindowStageCreate(stage: window.WindowStage): void {
    try {
      stage.getMainWindowSync().getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE_WITH_CARET);
    } catch {
      // Editing still starts if the window context is not ready for keyboard avoidance.
    }
    try {
      stage.loadContent('pages/Index');
    } catch {
      // The ability has no alternate page if the main content fails to load.
    }
  }
}
