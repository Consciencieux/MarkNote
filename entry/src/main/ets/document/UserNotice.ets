import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppText } from '../i18n/AppText';

const LOG_DOMAIN = 0xD001;
const LOG_TAG = 'MarkNote';

/** 应用准备好的说明。系统异常不要用这个名字，避免把错误码或路径显示给用户。 */
export function userNotice(message: string): Error {
  const error = new Error(message);
  error.name = 'UserNotice';
  return error;
}

export function userNoticeMessage(error: Object): string {
  if (error instanceof Error && error.name === 'UserNotice') return error.message;
  return '';
}

/** 已知说明原样返回；其余异常只留下简短提示，并把详情写入调试日志。 */
export function shownDetail(error: Object): string {
  const message = userNoticeMessage(error);
  if (message.length > 0) return message;
  const detail = error instanceof Error ? `${error.name}: ${error.message}` : 'unexpected failure';
  hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', detail);
  return AppText.text($r('app.string.error_retry'));
}
