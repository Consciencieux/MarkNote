import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { LaunchRequests } from '../document/LaunchRequests';

// Navigation and Tabs own the safe-area layout. No forced full-screen/window overlays.
// File opens share this singleton ability. The page consumes the request after it exists.
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    LaunchRequests.deliver(want);
    void launchParam;
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    LaunchRequests.deliver(want);
    void launchParam;
  }

  onWindowStageCreate(stage: window.WindowStage): void {
    stage.loadContent('pages/Index');
  }
}
