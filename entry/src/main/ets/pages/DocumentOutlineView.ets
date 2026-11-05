import { Heading } from '../model/Document';
import { DocumentScrollLayer } from './DocumentScrollLayer';

/** Flat row model used by the documented ArkUI List-based tree pattern. */
class OutlineRow {
  id: number = 0;
  heading: Heading = new Heading(1, '', 0, 0);
  depth: number = 0;
  isFolder: boolean = false;
  expanded: boolean = false;
}

@Component
export struct DocumentOutlineView {
  @Prop @Watch('resetExpanded') headings: Heading[] = [];
  @State private expandedOutline: number[] = [];
  scroller: Scroller = new Scroller();
  onSelect: (heading: Heading) => void = (_heading: Heading): void => {};

  aboutToAppear(): void {
    this.resetExpanded();
  }

  private resetExpanded(): void {
    const expanded: number[] = [];
    for (let index = 0; index + 1 < this.headings.length; index++) {
      if (this.headings[index + 1].level > this.headings[index].level) expanded.push(index + 1);
    }
    this.expandedOutline = expanded;
  }

  private visibleOutlineRows(): OutlineRow[] {
    const rows: OutlineRow[] = [];
    const ancestors: OutlineRow[] = [];
    for (let index = 0; index < this.headings.length; index++) {
      const heading = this.headings[index];
      while (ancestors.length > 0 && ancestors[ancestors.length - 1].heading.level >= heading.level) {
        ancestors.pop();
      }
      const nextHeading = index + 1 < this.headings.length ? this.headings[index + 1] : undefined;
      const row = new OutlineRow();
      row.id = index + 1;
      row.heading = heading;
      row.depth = ancestors.length;
      row.isFolder = nextHeading !== undefined && nextHeading.level > heading.level;
      row.expanded = row.isFolder && this.expandedOutline.indexOf(row.id) >= 0;
      if (ancestors.every((ancestor: OutlineRow) => ancestor.expanded)) rows.push(row);
      if (row.isFolder) ancestors.push(row);
    }
    return rows;
  }

  private toggleOutline(row: OutlineRow): void {
    const expanded = this.expandedOutline.slice();
    const index = expanded.indexOf(row.id);
    if (index >= 0) expanded.splice(index, 1);
    else expanded.push(row.id);
    this.expandedOutline = expanded;
  }

  @Builder
  private OutlineRowContent(row: OutlineRow) {
    Row() {
      // Indentation uses the system spacing resource; no row dimensions or colors are invented.
      if (row.depth > 0) Blank().width($r('sys.float.padding_level4'))
      if (row.depth > 1) Blank().width($r('sys.float.padding_level4'))
      if (row.depth > 2) Blank().width($r('sys.float.padding_level4'))
      if (row.depth > 3) Blank().width($r('sys.float.padding_level4'))
      if (row.depth > 4) Blank().width($r('sys.float.padding_level4'))
      if (row.depth > 5) Blank().width($r('sys.float.padding_level4'))
      if (row.isFolder) {
        SymbolGlyph(row.expanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .onClick(() => this.toggleOutline(row))
      }
      Text(row.heading.text)
        .layoutWeight(1)
        .onClick(() => this.onSelect(row.heading))
    }
    .width('100%')
  }

  /** The unbounded List contributes rows; the shared parent Scroll owns page movement. */
  build() {
    DocumentScrollLayer({ scroller: this.scroller }) {
      List({ initialIndex: 0 }) {
        ForEach(this.visibleOutlineRows(), (row: OutlineRow) => {
          ListItem() {
            this.OutlineRowContent(row)
          }
        }, (row: OutlineRow) => `${row.id}`)
      }
      // FAQ faqs-arkui-295: an unbounded List inside Scroll expands with its rows and lets the
      // outer Scroll move the layout. ForEach already eagerly builds this outline's rows.
      .width('100%')
      .edgeEffect(EdgeEffect.None)
      .scrollBar(BarState.Off)
    }
  }
}
