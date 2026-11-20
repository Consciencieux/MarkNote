import { fileIo } from '@kit.CoreFileKit';
import { userNotice } from '../document/UserNotice';

const WRITE_CHUNK_BYTES: number = 64 * 1024;

/**
 * Write every byte, advancing by the count the provider actually accepted.
 * Callers still choose create, truncate, fsync, rename and verification.
 */
export async function writeAll(fd: number, bytes: Uint8Array, interrupted: string): Promise<void> {
  let offset = 0;
  while (offset < bytes.length) {
    const length = Math.min(WRITE_CHUNK_BYTES, bytes.length - offset);
    const chunk = new ArrayBuffer(length);
    new Uint8Array(chunk).set(bytes.subarray(offset, offset + length));
    const written = await fileIo.write(fd, chunk);
    if (written <= 0) throw userNotice(interrupted);
    offset += written;
  }
}
