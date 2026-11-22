import { LengthMetrics } from '@kit.ArkUI';
import { AppText } from '../i18n/AppText';
import { searchFieldMaterial } from './ImmersiveMaterials';
import { toolbarIcon } from './TextRoles';

const findButtonSize = 40;

/**
 * 查找栏只负责自己的外观和测量。查询、匹配和替换仍由文稿页持有。
 * 标题栏用 @Builder 创建本组件，语言直接订阅 AppStorage，避免按值传入后不刷新。
 */
@Component
export struct DocumentFindBar {
  @Prop query: string = '';
  @Prop replacement: string = '';
  @Prop matchCount: number = 0;
  @Prop matchOrdinal: number = 0;
  @StorageLink('marknote_language') language: string = 'default';
  onQueryChange: (value: string) => void = (_value: string): void => {};
  onReplacementChange: (value: string) => void = (_value: string): void => {};
  onNext: () => void = (): void => {};
  onPrevious: () => void = (): void => {};
  onReplace: () => void = (): void => {};
  onClose: () => void = (): void => {};
  onHeightChange: (height: number) => void = (_height: number): void => {};
  @State private controlsWidth: number = 2 * findButtonSize;
  private material = searchFieldMaterial();

  private format(resource: Resource, first: string, second: string = ''): string {
    if (this.language.length === 0) return '';
    return AppText.format(resource, first, second);
  }

  @Builder
  private MatchButton(icon: Resource, label: Resource, action: () => void) {
    Button({ stateEffect: false }) {
      SymbolGlyph(icon).attributeModifier(toolbarIcon)
    }
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .width(findButtonSize)
    .height(findButtonSize)
    .stateStyles({
      normal: { .opacity(1) },
      pressed: { .opacity($r('sys.float.alpha_secondary')) }
    })
    .accessibilityText(label)
    .enabled(this.matchCount > 0)
    .onClick(() => action())
  }

  build() {
    Column() {
      Row() {
        Stack({ alignContent: Alignment.End }) {
          Search({ value: this.query, placeholder: $r('app.string.find_placeholder') })
            .onSubmit(() => this.onNext())
            .onChange((value: string) => this.onQueryChange(value))
            .width('100%')
            .cancelButton({
              style: this.query.length > 0 ? CancelButtonStyle.CONSTANT : CancelButtonStyle.INVISIBLE
            })
            // Search already reserves space for its native clear button.
            .padding({ end: LengthMetrics.vp(this.query.length > 0 ?
              this.controlsWidth + LengthMetrics.resource($r('sys.float.padding_level2')).value : 0) })
            .systemMaterial(this.material)
          if (this.query.length > 0) {
            Row() {
              Text(this.matchOrdinal > 0 ? `${this.matchOrdinal}/${this.matchCount}` :
                String(this.matchCount))
                .maxLines(1)
                .fontColor($r('sys.color.font_secondary'))
                .accessibilityText(this.matchOrdinal > 0 ?
                  this.format($r('app.string.match_position'), String(this.matchOrdinal), String(this.matchCount)) :
                  this.format($r('app.string.match_total'), String(this.matchCount)))
              this.MatchButton($r('sys.symbol.chevron_up'), $r('app.string.find_previous'), this.onPrevious)
              this.MatchButton($r('sys.symbol.chevron_down'), $r('app.string.find_next'), this.onNext)
            }
            .margin({ end: LengthMetrics.vp(findButtonSize) })
            .onAreaChange((_oldArea: Area, newArea: Area) => {
              const width = parseFloat(String(newArea.width)) || 0;
              if (width > 0 && width !== this.controlsWidth) this.controlsWidth = width;
            })
          }
        }
        .layoutWeight(1)
        .margin({ end: LengthMetrics.resource($r('sys.float.padding_level4')) })
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .attributeModifier(toolbarIcon)
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .width(findButtonSize)
        .height(findButtonSize)
        .accessibilityText($r('app.string.find_close'))
        .onClick(() => this.onClose())
      }
      .width('100%')
      Row() {
        Row() {
          TextInput({ text: this.replacement, placeholder: $r('app.string.replace_placeholder') })
            .onChange((value: string) => this.onReplacementChange(value))
            .layoutWeight(1)
            .margin({ end: LengthMetrics.resource($r('sys.float.padding_level4')) })
            .systemMaterial(this.material)
          Button($r('app.string.replace_action'))
            .onClick(() => this.onReplace())
        }
        .layoutWeight(1)
        .margin({ end: LengthMetrics.resource($r('sys.float.padding_level4')) })
        Blank().width(findButtonSize)
      }
      .width('100%')
      .margin({ top: $r('sys.float.padding_level4') })
      Blank()
        .height($r('sys.float.padding_level4'))
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          const bottom = Number(newArea.position.y) + Number(newArea.height);
          if (bottom > 0) this.onHeightChange(bottom);
        })
    }
    .padding({
      start: LengthMetrics.resource($r('sys.float.margin_left')),
      end: LengthMetrics.resource($r('sys.float.margin_right')),
      top: LengthMetrics.resource($r('sys.float.padding_level4'))
    })
    .width('100%')
  }
}
