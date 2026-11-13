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
      .textAlign(TextAlign.Start)
      .margin({ top: $r('sys.float.padding_level8'), bottom: $r('sys.float.padding_level4') });
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

/** 设置行中的状态、版本等辅助值属于正文信息，使用正文中号而非副标题角色。 */
export class SettingsValueStyle implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance.fontSize($r('sys.float.Body_M'))
      .fontWeight(FontWeight.Regular)
      .fontColor($r('sys.color.font_secondary'))
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

/** 工具栏符号原先写死 24。Title_M 是系统里与之对应的一档。 */
export class ToolbarIconStyle implements AttributeModifier<SymbolGlyphAttribute> {
  applyNormalAttribute(instance: SymbolGlyphAttribute): void {
    instance.fontSize($r('sys.float.Title_M'))
      .fontColor([$r('sys.color.icon_primary')]);
  }
}

export const bodyText: BodyTextStyle = new BodyTextStyle();
export const sectionTitle: SectionTitleStyle = new SectionTitleStyle();
export const listTitle: ListTitleStyle = new ListTitleStyle();
export const settingsValue: SettingsValueStyle = new SettingsValueStyle();
export const outlineChildTitle: OutlineChildTitleStyle = new OutlineChildTitleStyle();
export const pageTitle: PageTitleStyle = new PageTitleStyle();
export const bodyInput: BodyInputStyle = new BodyInputStyle();
export const toolbarIcon: ToolbarIconStyle = new ToolbarIconStyle();
