/**
 * 字号、字重和颜色按角色取系统资源，页面不再各自写数字。
 * 长文用正文大号；小节标题比正文大一档。行高不另写，由系统按字号计算。
 * https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/typography-0000002622688363
 * 资源名来自当前 SDK 的 sys.float：Body_L、Body_M、Subtitle_L、Subtitle_M、Subtitle_S、Title_M。
 */

export class BodyTextStyle implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance.fontSize($r('sys.float.Body_L'))
      .fontWeight(FontWeight.Regular)
      .fontColor($r('sys.color.font_primary'))
      .textAlign(TextAlign.Start);
  }
}

export class SectionTitleStyle implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance.fontSize($r('sys.float.Subtitle_L'))
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_primary'))
      .textAlign(TextAlign.Start);
  }
}

export class ListTitleStyle implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance.fontSize($r('sys.float.Subtitle_M'))
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_primary'))
      .textAlign(TextAlign.Start);
  }
}

/** 大纲的子级仍是标题文字，使用副标题小号；层级通过字号区分，颜色保持主文字色。 */
export class OutlineChildTitleStyle implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance.fontSize($r('sys.float.Subtitle_S'))
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_primary'))
      .textAlign(TextAlign.Start);
  }
}

export class PageTitleStyle implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance.fontSize($r('sys.float.Title_M'))
      .fontWeight(FontWeight.Bold)
      .fontColor($r('sys.color.font_primary'))
      .textAlign(TextAlign.Start);
  }
}

export class BodyInputStyle implements AttributeModifier<TextAreaAttribute> {
  applyNormalAttribute(instance: TextAreaAttribute): void {
    instance.fontSize($r('sys.float.Body_L'))
      .fontWeight(FontWeight.Regular)
      .fontColor($r('sys.color.font_primary'));
  }
}

/** 工具栏图标使用系统图标尺寸。 */
export class ToolbarIconStyle implements AttributeModifier<SymbolGlyphAttribute> {
  applyNormalAttribute(instance: SymbolGlyphAttribute): void {
    instance.fontSize($r('sys.float.ohos_id_toolbar_item_icon_size'))
      .fontColor([$r('sys.color.icon_primary')]);
  }
}

export const bodyText: BodyTextStyle = new BodyTextStyle();
export const sectionTitle: SectionTitleStyle = new SectionTitleStyle();
export const listTitle: ListTitleStyle = new ListTitleStyle();
export const outlineChildTitle: OutlineChildTitleStyle = new OutlineChildTitleStyle();
export const pageTitle: PageTitleStyle = new PageTitleStyle();
export const bodyInput: BodyInputStyle = new BodyInputStyle();
export const toolbarIcon: ToolbarIconStyle = new ToolbarIconStyle();
