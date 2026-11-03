import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

// Navigation and Tabs own the safe-area layout. No forced full-screen/window overlays.
export default class EntryAbility extends UIAbility {
  onWindowStageCreate(stage: window.WindowStage): void {
    stage.loadContent('pages/Index');
  }
}
