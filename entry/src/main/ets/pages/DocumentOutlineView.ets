import { Heading } from '../model/Document';
import { DocumentScrollLayer } from './DocumentScrollLayer';

/** Flat row model used by the documented ArkUI List-based tree pattern. */
class OutlineRow {
  id: string = '';
  heading: Heading = new Heading(1, '', 0);
  depth: number = 0;
  isFolder: boolean = false;
  expanded: boolean = false;
}

@Component
export struct DocumentOutlineView {
  @Prop headings: Heading[] = [];
  @Prop @Watch('resetCollapsed') documentRevision: number = 0;
  @State private collapsedOutline: string[] = [];
  scroller: Scroller = new Scroller();
  onSelect: (heading: Heading) => void = (_heading: Heading): void => {};

  aboutToAppear(): void {
    this.resetCollapsed();
  }

  private resetCollapsed(): void {
    this.collapsedOutline = [];
  }

  private outlineRows(): OutlineRow[] {
    const rows: OutlineRow[] = [];
    const ancestors: OutlineRow[] = [];
    const occurrences: Map<string, number> = new Map();
    for (let index = 0; index < this.headings.length; index++) {
      const heading = this.headings[index];
      while (ancestors.length > 0 && ancestors[ancestors.length - 1].heading.level >= heading.level) {
        ancestors.pop();
      }
      const nextHeading = index + 1 < this.headings.length ? this.headings[index + 1] : undefined;
      const row = new OutlineRow();
      // Use the heading and duplicate occurrence instead of an index, so edits before a
      // heading do not change the key of a collapsed branch.
      const identity = JSON.stringify([heading.level, heading.text]);
      const occurrence = occurrences.get(identity) ?? 0;
      occurrences.set(identity, occurrence + 1);
      row.id = JSON.stringify([identity, occurrence]);
      row.heading = heading;
      row.depth = ancestors.length;
      row.isFolder = nextHeading !== undefined && nextHeading.level > heading.level;
      row.expanded = row.isFolder && this.collapsedOutline.indexOf(row.id) < 0;
      if (ancestors.every((ancestor: OutlineRow) => ancestor.expanded)) rows.push(row);
      if (row.isFolder) ancestors.push(row);
    }
    return rows;
  }

  private toggleOutline(row: OutlineRow): void {
    const collapsed = this.collapsedOutline.slice();
    const index = collapsed.indexOf(row.id);
    if (index >= 0) collapsed.splice(index, 1);
    else collapsed.push(row.id);
    this.collapsedOutline = collapsed;
  }

  @Builder
  private OutlineRowContent(row: OutlineRow) {
    Row() {
      // Indentation uses the system spacing resource; no row dimensions or colors are invented.
      if (row.depth > 0) Row().width($r('sys.float.padding_level8'))
      if (row.depth > 1) Row().width($r('sys.float.padding_level8'))
      if (row.depth > 2) Row().width($r('sys.float.padding_level8'))
      if (row.depth > 3) Row().width($r('sys.float.padding_level8'))
      if (row.depth > 4) Row().width($r('sys.float.padding_level8'))
      // A separate arrow target keeps expansion independent of selecting the heading.
      // Leaves retain the same slot so titles at the same depth align.
      Row() {
        SymbolGlyph(row.expanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize($r('sys.float.Subtitle_S'))
          .fontColor([$r('sys.color.font_primary')])
      }
      .justifyContent(FlexAlign.Center)
      // The compact outline uses the 40 vp minimum in Huawei's touch-target-size rule.
      .width(40)
      .height(40)
      .opacity(row.isFolder ? 1 : 0)
      .enabled(row.isFolder)
      .accessibilityRole(AccessibilityRoleType.BUTTON)
      .accessibilityText(row.expanded ? '收起' : '展开')
      .onClick(() => this.toggleOutline(row))
      // Reuse the system subtitle resources used by the app's settings rows.
      Text(row.heading.text)
        .fontSize(row.depth === 0 ? $r('sys.float.Subtitle_M') : $r('sys.float.Subtitle_S'))
        .fontWeight(row.depth === 0 ? FontWeight.Medium : FontWeight.Regular)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
        .constraintSize({ minHeight: 40 })
        .onClick(() => this.onSelect(row.heading))
    }
    .width('100%')
    .padding({
      left: $r('sys.float.padding_level4'),
      right: $r('sys.float.padding_level4')
    })
  }

  /** The unbounded List contributes rows; the shared parent Scroll owns page movement. */
  build() {
    DocumentScrollLayer({ scroller: this.scroller }) {
      List({ initialIndex: 0 }) {
        if (this.headings.length === 0) {
          ListItem() { Text('暂无大纲') }
        }
        ForEach(this.outlineRows(), (row: OutlineRow) => {
          ListItem() {
            this.OutlineRowContent(row)
          }
        // ForEach reuses a node for the same key, including its click handler. Refresh it
        // when a heading moves or changes depth; collapse state remains keyed by row.id.
        }, (row: OutlineRow) => `${row.id}:${row.heading.offset}:${row.depth}:${row.isFolder}:${row.expanded}`)
      }
      // FAQ faqs-arkui-295: an unbounded List inside Scroll expands with its rows and lets the
      // outer Scroll move the layout. ForEach already eagerly builds this outline's rows.
      .width('100%')
      .edgeEffect(EdgeEffect.None)
      .scrollBar(BarState.Off)
    }
  }
}
