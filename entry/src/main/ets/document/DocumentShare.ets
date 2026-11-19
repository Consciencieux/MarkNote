import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { DocumentInfo } from '../model/Document';
import { TextEncoding } from './TextEncoding';
import { AppText } from '../i18n/AppText';
import { userNotice } from './UserNotice';

/** Share a snapshot of the editor through the system panel, without modifying the original file. */
export class DocumentShare {
  private static sequence: number = 0;

  static async show(context: common.UIAbilityContext, name: string, source: string): Promise<void> {
    const safeName = name.replace(/[\/\\\0]/g, '_');
    const filename = safeName.length === 0 || safeName === '.' || safeName === '..' ?
      AppText.text($r('app.string.file_share_fallback')) : safeName;
    const directory = `${context.cacheDir}/marknote-share/${Date.now()}-${DocumentShare.sequence++}`;
    await fileIo.mkdir(directory, true);
    const path = `${directory}/${filename}`;
    // A UTF-8 snapshot also supports new, read-only and unsaved documents.
    const bytes = TextEncoding.encode(source, new DocumentInfo()).bytes;
    const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
    try {
      let offset = 0;
      while (offset < bytes.length) {
        const length = Math.min(64 * 1024, bytes.length - offset);
        const chunk = new ArrayBuffer(length);
        new Uint8Array(chunk).set(bytes.subarray(offset, offset + length));
        const written = await fileIo.write(file.fd, chunk);
        if (written <= 0) throw userNotice(AppText.text($r('app.string.share_write_failed')));
        offset += written;
      }
    } finally {
      await fileIo.close(file);
    }

    let type: string = uniformTypeDescriptor.UniformDataType.FILE;
    const dot = filename.lastIndexOf('.');
    if (dot >= 0) {
      try {
        type = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(
          filename.substring(dot).toLowerCase(), uniformTypeDescriptor.UniformDataType.FILE) || type;
      } catch {
        // Unknown extensions are shared as generic files.
      }
    }
    // Share Kit handles URI grants and adapts the system panel to the device.
    // https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/share-mobilephone-app-share
    const data = new systemShare.SharedData({ utd: type, uri: fileUri.getUriFromPath(path), title: filename });
    const controller = new systemShare.ShareController(data);
    await controller.show(context, { anchor: 'marknote-doc-more' });
    // Keep the cache file available to the receiving app after the panel closes.
  }
}
