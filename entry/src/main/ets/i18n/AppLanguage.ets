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
