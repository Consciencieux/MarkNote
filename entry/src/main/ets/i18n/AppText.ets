import { common } from '@kit.AbilityKit';

/** Resolves string resources for APIs that accept only a plain string. */
export class AppText {
  private static context: common.Context | null = null;

  static bind(context: common.Context): void {
    AppText.context = context;
  }

  static text(resource: Resource): string {
    const context = AppText.context;
    if (context === null) return '';
    return context.resourceManager.getStringSync(resource.id);
  }

  static format(resource: Resource, first: string, second: string = ''): string {
    const context = AppText.context;
    if (context === null) return '';
    if (second.length === 0) return context.resourceManager.getStringSync(resource.id, first);
    return context.resourceManager.getStringSync(resource.id, first, second);
  }
}
