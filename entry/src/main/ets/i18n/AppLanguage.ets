import { i18n } from '@kit.LocalizationKit';

/**
 * Values stored for the language setting. `default` follows the system language.
 * Resource directories: `zh_Hant`, `en_US`, `ja`, `ko`, `ru`. `zh-Hans` uses `base`.
 */
export const LANGUAGE_VALUES: string[] = ['default', 'zh-Hans', 'zh-Hant', 'en-US', 'ja', 'ko', 'ru'];

/** Keep an unknown stored value on Follow system. */
export function normalizeAppLanguage(choice: string): string {
  if (choice === 'zh-Hans' || choice === 'zh-Hant' || choice === 'en-US' ||
    choice === 'ja' || choice === 'ko' || choice === 'ru') {
    return choice;
  }
  return 'default';
}

/**
 * Apply the language chosen in Settings.
 * 《应用偏好语言》：指定语言后界面使用该语言；`default` 清除偏好，下次冷启动跟随系统。
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/i18n-preferred-language
 */
export function applyAppLanguage(choice: string): void {
  i18n.System.setAppPreferredLanguage(normalizeAppLanguage(choice));
}

/**
 * 网页 `lang` 使用当前界面语言。
 * `getAppPreferredLanguage` 的返回值文档只写“应用偏好语言”，没有写会返回 `default`；
 * 跟随系统时改读系统语言。单选项仍以本地记录为准，避免把已解析的系统语言误当成用户指定语言。
 */
export function previewLanguageTag(): string {
  try {
    const preferred = i18n.System.getAppPreferredLanguage();
    if (preferred.length > 0 && preferred !== 'default') return preferred;
  } catch { /* 读取失败时继续使用系统语言。 */ }
  try {
    const system = i18n.System.getSystemLanguage();
    if (system.length > 0) return system;
  } catch { /* 下面使用与 base 资源一致的简体中文。 */ }
  return 'zh-Hans';
}
