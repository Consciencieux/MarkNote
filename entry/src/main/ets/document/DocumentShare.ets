import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { DocumentInfo } from '../model/Document';
import { AppText } from '../i18n/AppText';
import { DocumentFiles } from '../storage/DocumentFiles';
import { writeVerifiedText } from '../storage/DocumentStream';

export class SharedFile {
  uri: string = '';
  name: string = '';
}

/** Share a snapshot of the editor through the system panel, without modifying the original file. */
export class DocumentShare {
  private static sequence: number = 0;
  private static readonly CACHE_AGE_MS: number = 7 * 24 * 60 * 60 * 1000;

  private static async cleanExpired(root: string): Promise<void> {
    try {
      const entries = await fileIo.listFile(root);
      for (const entry of entries) {
        if (!/^\d+-\d+$/.test(entry)) continue;
        const created = Number(entry.split('-')[0]);
        if (Date.now() - created < DocumentShare.CACHE_AGE_MS) continue;
        try {
          await fileIo.rmdir(`${root}/${entry}`);
        } catch {
          // Retry on a later share if the file is still in use.
        }
      }
    } catch {
      // The share directory may not exist yet.
    }
  }

  static async show(context: common.UIAbilityContext, name: string, source: string): Promise<void> {
    const filename = DocumentShare.safeName(name);
    const root = `${context.cacheDir}/marknote-share`;
    await DocumentShare.cleanExpired(root);
    const directory = `${root}/${Date.now()}-${DocumentShare.sequence++}`;
    await fileIo.mkdir(directory, true);
    const path = `${directory}/${filename}`;
    let shown = false;
    try {
      await DocumentShare.showFile(context, filename, source, path);
      shown = true;
    } finally {
      if (!shown) await DocumentShare.removeFailedCopy(directory);
    }
  }

  private static async showFile(context: common.UIAbilityContext, filename: string,
    source: string, path: string): Promise<void> {
    // A UTF-8 snapshot also supports new, read-only and unsaved documents.
    const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      await writeVerifiedText(file.fd, source, new DocumentInfo(), AppText.text($r('app.string.share_write_failed')));
    } finally {
      await fileIo.close(file);
    }

    const type = DocumentShare.fileType(filename);
    // Share Kit handles URI grants and adapts the system panel to the device.
    // https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/share-mobilephone-app-share
    const data = new systemShare.SharedData({ utd: type, uri: fileUri.getUriFromPath(path), title: filename });
    const controller = new systemShare.ShareController(data);
    await controller.show(context, { anchor: 'marknote-doc-more' });
    // Keep the cache file available to the receiving app after the panel closes.
  }

  /** Share saved files from the library. The panel receives copies, so the originals stay unchanged. */
  static async showFiles(context: common.UIAbilityContext, files: SharedFile[], anchor: string): Promise<void> {
    if (files.length === 0) return;
    const root = `${context.cacheDir}/marknote-share`;
    await DocumentShare.cleanExpired(root);
    const directory = `${root}/${Date.now()}-${DocumentShare.sequence++}`;
    await fileIo.mkdir(directory, true);
    let shown = false;
    try {
      const data = new systemShare.SharedData(await DocumentShare.snapshot(directory, 0, files[0]));
      for (let index = 1; index < files.length; index++) {
        data.addRecord(await DocumentShare.snapshot(directory, index, files[index]));
      }
      await new systemShare.ShareController(data).show(context, { anchor: anchor });
      shown = true;
    } finally {
      if (!shown) await DocumentShare.removeFailedCopy(directory);
    }
  }

  private static async removeFailedCopy(directory: string): Promise<void> {
    try {
      await fileIo.rmdir(directory);
    } catch {
      // The expired-cache cleanup will retry on a later share.
    }
  }

  private static safeName(name: string): string {
    const safeName = name.replace(/[\/\\\0]/g, '_');
    return safeName.length === 0 || safeName === '.' || safeName === '..' ?
      AppText.text($r('app.string.file_share_fallback')) : safeName;
  }

  private static fileType(filename: string): string {
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
    return type;
  }

  private static async snapshot(directory: string, index: number,
    file: SharedFile): Promise<systemShare.SharedRecord> {
    const filename = DocumentShare.safeName(file.name);
    const path = `${directory}/${index}-${filename}`;
    await DocumentFiles.writeCopy(file.uri, path);
    const record: systemShare.SharedRecord = {
      utd: DocumentShare.fileType(filename),
      uri: fileUri.getUriFromPath(path),
      title: filename
    };
    return record;
  }
}
