import { i18n } from '@kit.LocalizationKit';

/**
 * Values stored for the language setting. `default` follows the system language.
 * Resource directories: `zh_Hant`, `bo`, `en_US`, `ja`, `ko`, `ru`, `ar`, `ug`. `zh-Hans` uses `base`.
 * 语言限定词取 ISO 639 的小写字母。藏语是 `bo`，阿拉伯语是 `ar`，维吾尔语是 `ug`。
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/resource-categories-and-access
 */
/** 跟随系统在最前。其余按汉语拼音：阿拉伯文、俄文、繁体中文、韩文、简体中文、日文、维吾尔文、英文、藏文。 */
export const LANGUAGE_VALUES: string[] =
  ['default', 'ar', 'ru', 'zh-Hant', 'ko', 'zh-Hans', 'ja', 'ug', 'en-US', 'bo'];

/** Keep an unknown stored value on Follow system. */
export function normalizeAppLanguage(choice: string): string {
  if (choice === 'zh-Hans' || choice === 'zh-Hant' || choice === 'bo' || choice === 'en-US' ||
    choice === 'ja' || choice === 'ko' || choice === 'ru' || choice === 'ar' || choice === 'ug') {
    return choice;
  }
  return 'default';
}

/**
 * 把设置项解析成资源目录能对上的语言标识。
 * `default` 按当前系统语言解析；没有对应资源时用简体中文（base）。
 */
export function resourceLanguage(choice: string): string {
  const normalized = normalizeAppLanguage(choice);
  if (normalized !== 'default') return normalized;
  let raw = '';
  try {
    raw = i18n.System.getSystemLanguage();
  } catch { /* 下面再试简化语言。 */ }
  let simplified = raw;
  try {
    simplified = raw.length > 0 ? i18n.System.getSimplifiedLanguage(raw) : i18n.System.getSimplifiedLanguage();
  } catch { /* 使用原始系统语言标识。 */ }
  return languageTag(simplified.length > 0 ? simplified : raw);
}

/**
 * 让界面使用设置里选中的语言。
 * 指定语言会立刻切换。官方把 `default` 规定为下次冷启动才跟随系统，
 * 所以跟随系统时改为设置“当前系统语言解析出的语言”，本次就生效。
 * 保存的选择仍是 `default`，下次冷启动会重新按那时的系统语言解析。
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/i18n-preferred-language
 */
/**
 * 导航栈里已经打开的页面收不到首页 `@Link` 的更新。
 * 写入 AppStorage 后，设置页和文稿页用 `@StorageLink` 重建勾选和必须现取的文字。
 */
export function publishAppLanguage(choice: string): void {
  AppStorage.setOrCreate('marknote_language', normalizeAppLanguage(choice));
}

export function applyAppLanguage(choice: string): void {
  const tag = resourceLanguage(choice);
  let current = '';
  try {
    current = i18n.System.getAppPreferredLanguage();
  } catch { /* 读不到时直接设置。 */ }
  if (current.length > 0 && sameLanguage(current, tag)) return;
  i18n.System.setAppPreferredLanguage(tag);
}

function languageTag(value: string): string {
  const kind = languageKind(value);
  if (kind === 'zh-hant') return 'zh-Hant';
  if (kind === 'bo') return 'bo';
  if (kind === 'en') return 'en-US';
  if (kind === 'ja') return 'ja';
  if (kind === 'ko') return 'ko';
  if (kind === 'ru') return 'ru';
  if (kind === 'ar') return 'ar';
  if (kind === 'ug') return 'ug';
  return 'zh-Hans';
}

/** 阿拉伯语和维吾尔语从右向左。跟随系统时不在这里判断，交给 Direction.Auto。 */
export function isRightToLeftLanguage(choice: string): boolean {
  return i18n.isRTL(resourceLanguage(choice));
}

function sameLanguage(left: string, right: string): boolean {
  return left === right || languageKind(left) === languageKind(right);
}

function languageKind(value: string): string {
  const tag = value.replace(/_/g, '-').toLowerCase();
  const parts = tag.split('-');
  const language = parts[0];
  if (language === 'zh') {
    // An explicit script wins over a regional default (e.g. zh-Hans-HK).
    if (parts.includes('hans')) return 'zh-hans';
    if (parts.includes('hant') || parts.includes('tw') || parts.includes('hk') || parts.includes('mo')) {
      return 'zh-hant';
    }
    return 'zh-hans';
  }
  if (language === 'bo' || language === 'en' || language === 'ja' || language === 'ko' ||
    language === 'ru' || language === 'ar' || language === 'ug') return language;
  return tag;
}
