import { ActionBarButton, ActionBarButtonOptions, ActionBarStyle, BlurStrategy, HdsActionBar } from '@kit.UIDesignKit';
import { FormatRegistry, InsertAction } from '../document/FormatRegistry';

/**
 * HdsActionBar supplies the documented grouped backplane, round action buttons, and adaptive
 * component blur. Keep its native backplane so it remains a floating bar instead of stretching a
 * generic systemMaterial across the titlebar builder's full-width layout slot.
 */
@ComponentV2
export struct FormatBarView {
  @Param formatId: string = '';
  @Param horizontal: boolean = true;
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
      buttons.push(new ActionBarButton(options));
    }
    return buttons;
  }

  @Builder
  private ActionBar() {
    HdsActionBar({
      startButtons: this.actionButtons(),
      actionBarStyle: new ActionBarStyle({ isHorizontal: this.horizontal }),
      blurStrategy: BlurStrategy.ADAPTIVE
    })
      .id('marknote-format-bar')
  }

  build() {
    this.ActionBar()
  }
}
