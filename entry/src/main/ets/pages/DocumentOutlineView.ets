import { LengthMetrics } from '@kit.ArkUI';
import { Heading } from '../model/Document';
import { documentTabClearance } from './DocumentScrollLayer';
import { PageScrollPolicy } from './PageScrollPolicy';
import { listTitle, outlineChildTitle } from './TextRoles';

/** Flat row model used by the documented ArkUI List-based tree pattern. */
class OutlineRow {
  id: string = '';
  heading: Heading = new Heading(1, '', 0);
  depth: number = 0;
  isFolder: boolean = false;
  expanded: boolean = false;
}

// ArkUI invokes the List builder only for the visible and preloaded rows.
// https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-rendering-control-lazyforeach
class OutlineRows implements IDataSource {
  private items: OutlineRow[] = [];
  private listeners: Set<DataChangeListener> = new Set();

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): OutlineRow {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.add(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners.delete(listener);
  }

  replace(items: OutlineRow[]): void {
    this.items = items;
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }
}

@Component
export struct DocumentOutlineView {
  @Consume('documentNavigationInsetAbsent') navigationInsetAbsent: boolean;
  @Prop @Watch('refreshRows') headings: Heading[] = [];
  @Prop @Watch('resetCollapsed') documentRevision: number = 0;
  private collapsedOutline: Set<string> = new Set();
  private rows: OutlineRows = new OutlineRows();
  scroller: Scroller = new Scroller();
  onSelect: (heading: Heading) => void = (_heading: Heading): void => {};

  aboutToAppear(): void {
    this.resetCollapsed();
  }

  private resetCollapsed(): void {
    this.collapsedOutline.clear();
    this.refreshRows();
  }

  private refreshRows(): void {
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
      row.expanded = row.isFolder && !this.collapsedOutline.has(row.id);
      if (ancestors.every((ancestor: OutlineRow) => ancestor.expanded)) rows.push(row);
      if (row.isFolder) ancestors.push(row);
    }
    this.rows.replace(rows);
  }

  private toggleOutline(row: OutlineRow): void {
    if (this.collapsedOutline.has(row.id)) this.collapsedOutline.delete(row.id);
    else this.collapsedOutline.add(row.id);
    this.refreshRows();
  }

  private outlineText(depth: number): AttributeModifier<TextAttribute> {
    if (depth === 0) {
      return listTitle;
    }
    return outlineChildTitle;
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
      .accessibilityText(row.expanded ? $r('app.string.outline_collapse') : $r('app.string.outline_expand'))
      .onClick(() => this.toggleOutline(row))
      // 一级和子级都是标题文字，分别使用列表标题和副标题小号样式。
      Text(row.heading.text)
        .attributeModifier(this.outlineText(row.depth))
        .layoutWeight(1)
        .constraintSize({ minHeight: 40 })
        .onClick(() => this.onSelect(row.heading))
    }
    .width('100%')
  }

  build() {
    List({ scroller: this.scroller }) {
      if (this.headings.length === 0) {
        ListItem() {
          Text($r('app.string.outline_empty'))
        }
      }
      LazyForEach(this.rows, (row: OutlineRow) => {
        ListItem() {
          this.OutlineRowContent(row)
        }
      // Recreate a row when its displayed state or jump target changes.
      }, (row: OutlineRow) => `${row.id}:${row.heading.offset}:${row.depth}:${row.isFolder}:${row.expanded}`)
    }
    .padding({
      start: LengthMetrics.resource($r('sys.float.margin_left')),
      end: LengthMetrics.resource($r('sys.float.margin_right'))
    })
    .attributeModifier(new PageScrollPolicy(false, documentTabClearance(this.navigationInsetAbsent)))
    .scrollBar(BarState.Auto)
    .width('100%')
    .height('100%')
  }
}
