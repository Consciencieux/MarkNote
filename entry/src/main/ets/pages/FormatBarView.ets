import { ButtonModifier, uiMaterial } from '@kit.ArkUI';
import { ActionBarButton, ActionBarButtonOptions, ActionBarStyle, HdsActionBar } from '@kit.UIDesignKit';
import { FormatRegistry, InsertAction } from '../document/FormatRegistry';

/**
 * HdsActionBar (ui-design-hdsactionbar), with actions in startButtons per
 * ui-design-actionbar-without-master-button. The top placement is hosted in the HDS titlebar's
 * bottomBuilder. Its round buttons use API 26 systemMaterial there; the side placement uses the
 * ActionBar's documented component blur because immersive material is not effective in page content.
 */
@ComponentV2
export struct FormatBarView {
  @Param visible: boolean = false;
  @Param formatId: string = '';
  @Param horizontal: boolean = true;
  @Param immersive: boolean = false;
  @Param onInsert: (action: InsertAction) => void = (_action: InsertAction): void => {};

  private actionButtons(): ActionBarButton[] {
    const actions = FormatRegistry.byId(this.formatId).inserts;
    const buttons: ActionBarButton[] = [];
    for (let index = 0; index < actions.length; index++) {
      const action = actions[index];
      const options: ActionBarButtonOptions = {
        baseIcon: action.symbol,
        accessibilityText: action.label,
        hoverTips: action.label,
        onClick: (): void => this.onInsert(action)
      };
      if (this.immersive) {
        const modifier = new ButtonModifier();
        // API 26 recommends ULTRA_THIN for floating buttons. The top placement is hosted in the
        // HDS titlebar bottomBuilder; the right-side body is outside the documented effect region.
        modifier.systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN
        }));
        options.buttonModifier = modifier;
      }
      buttons.push(new ActionBarButton(options));
    }
    return buttons;
  }

  @Builder
  private ActionBar() {
    HdsActionBar({
      startButtons: this.actionButtons(),
      actionBarStyle: new ActionBarStyle({ isHorizontal: this.horizontal })
    })
      .id('marknote-format-bar')
  }

  build() {
    if (this.visible) {
      this.ActionBar()
    }
  }
}
