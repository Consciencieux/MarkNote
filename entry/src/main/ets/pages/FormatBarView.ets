import { ActionBarButton, HdsActionBar } from '@kit.UIDesignKit';
import { FormatRegistry, InsertAction } from '../document/FormatRegistry';

/** HdsActionBar (ui-design-hdsactionbar); the no-primary-button setup follows
 * ui-design-actionbar-without-master-button. Its button appearance stays at the API defaults. */
@ComponentV2
export struct FormatBarView {
  @Param visible: boolean = false;
  @Param formatId: string = '';
  @Param onInsert: (action: InsertAction) => void = (_action: InsertAction): void => {};

  private actionButtons(): ActionBarButton[] {
    const actions = FormatRegistry.byId(this.formatId).inserts;
    const buttons: ActionBarButton[] = [];
    for (let index = 0; index < actions.length; index++) {
      const action = actions[index];
      buttons.push(new ActionBarButton({
        baseIcon: action.symbol,
        accessibilityText: action.label,
        hoverTips: action.label,
        onClick: (): void => this.onInsert(action)
      }));
    }
    return buttons;
  }

  build() {
    if (this.visible) {
      // The no-primary-button guide puts actions in startButtons.
      HdsActionBar({ startButtons: this.actionButtons() })
        .id('marknote-format-bar')
    }
  }
}
