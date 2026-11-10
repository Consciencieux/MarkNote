import { i18n } from '@kit.LocalizationKit';

/** Values stored for the language setting. `default` follows the system language. */
export const LANGUAGE_VALUES: string[] = ['default', 'zh-Hans', 'en-US'];

/**
 * Apply the language chosen in Settings.
 * 《应用偏好语言》：指定语言后界面使用该语言；`default` 清除偏好，下次冷启动跟随系统。
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/i18n-preferred-language
 */
export function applyAppLanguage(choice: string): void {
  const language = choice === 'zh-Hans' || choice === 'en-US' ? choice : 'default';
  i18n.System.setAppPreferredLanguage(language);
}
