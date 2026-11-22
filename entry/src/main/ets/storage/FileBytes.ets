import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { userNotice } from '../document/UserNotice';

const WRITE_CHUNK_BYTES: number = 64 * 1024;

/** The open descriptor survives unlink; the OS reclaims it on close or process exit. */
export async function openScratchFile(cacheDir: string): Promise<fileIo.File> {
  const path = `${cacheDir}/marknote-${util.generateRandomUUID()}`;
  const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
  try {
    await fileIo.unlink(path);
    return file;
  } catch (error) {
    await fileIo.close(file);
    throw error as Error;
  }
}

/** Write encoded text to its file, retrying partial writes. */
export async function writeAll(fd: number, bytes: Uint8Array, interrupted: string): Promise<void> {
  let offset = 0;
  while (offset < bytes.length) {
    const length = Math.min(WRITE_CHUNK_BYTES, bytes.length - offset);
    const start = bytes.byteOffset + offset;
    const chunk = start === 0 && length === bytes.buffer.byteLength ?
      bytes.buffer : bytes.buffer.slice(start, start + length);
    const written = await fileIo.write(fd, chunk);
    if (written <= 0 || written > length) throw userNotice(interrupted);
    offset += written;
  }
}
