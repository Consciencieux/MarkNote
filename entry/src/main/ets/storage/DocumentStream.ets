import { fileIo } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer } from '@kit.ArkTS';
import { DecodedText, DocumentDecoder, ENCODING_SAMPLE_BYTES, TextEncoding } from '../document/TextEncoding';
import { AppText } from '../i18n/AppText';
import { userNotice } from '../document/UserNotice';
import { DocumentInfo } from '../model/Document';
import { writeAll } from './FileBytes';

const READ_BYTES: number = 64 * 1024;

export class InspectedDocument {
  decoded: DecodedText;
  fingerprint: string;

  constructor(decoded: DecodedText, fingerprint: string) {
    this.decoded = decoded;
    this.fingerprint = fingerprint;
  }
}

async function digestHex(md: cryptoFramework.Md): Promise<string> {
  return buffer.from((await md.digest()).data).toString('hex');
}

async function readBlock(fd: number, buffer: ArrayBuffer, length: number): Promise<number> {
  const got = await fileIo.read(fd, buffer, { length: length });
  if (got <= 0 || got > length) throw userNotice(AppText.text($r('app.string.read_incomplete')));
  return got;
}

async function readPrefix(fd: number, size: number): Promise<Uint8Array> {
  const buffer = new ArrayBuffer(Math.min(size, ENCODING_SAMPLE_BYTES));
  const bytes = new Uint8Array(buffer);
  if (bytes.length === 0) return bytes;
  let count = await readBlock(fd, buffer, bytes.length);
  while (count < bytes.length) {
    const rest = new ArrayBuffer(bytes.length - count);
    const got = await readBlock(fd, rest, rest.byteLength);
    bytes.set(new Uint8Array(rest, 0, got), count);
    count += got;
  }
  return bytes;
}

/** Consume each borrowed buffer before the next read. False stops a failed decoding attempt. */
async function readChunks(fd: number, start: number, size: number,
  consume: (bytes: Uint8Array, last: boolean) => Promise<boolean>): Promise<boolean> {
  const buffer = new ArrayBuffer(Math.min(READ_BYTES, size - start));
  const view = new Uint8Array(buffer);
  let scratch: ArrayBuffer | null = null;
  let position = start;
  while (position < size) {
    const length = Math.min(buffer.byteLength, size - position);
    let filled = await readBlock(fd, buffer, length);
    // Fragmented providers still yield one decoded string per block, even for one-byte reads.
    while (filled < length) {
      if (scratch === null) scratch = new ArrayBuffer(buffer.byteLength);
      const got = await readBlock(fd, scratch, length - filled);
      view.set(new Uint8Array(scratch, 0, got), filled);
      filled += got;
    }
    position += filled;
    if (!await consume(view.subarray(0, filled), position === size)) return false;
  }
  if (Number((await fileIo.stat(fd)).size) !== size) throw userNotice(AppText.text($r('app.string.read_incomplete')));
  return true;
}

export async function fileDigest(fd: number): Promise<string> {
  const size = Number((await fileIo.stat(fd)).size);
  const md = cryptoFramework.createMd('SHA256');
  await readChunks(fd, 0, size, async (chunk: Uint8Array): Promise<boolean> => {
    await md.update({ data: chunk });
    return true;
  });
  return digestHex(md);
}

/** Reopen the provider only if strict decoding requires a different candidate. */
export async function inspectDocument(fd: number, restart: () => Promise<number>, expected: string | null):
  Promise<InspectedDocument> {
  const size = Number((await fileIo.stat(fd)).size);
  const sample = await readPrefix(fd, size);
  const probe = TextEncoding.probe(sample, size);
  for (let attempt = 0; attempt < probe.encodings.length; attempt++) {
    if (attempt > 0) {
      fd = await restart();
      const next = await readPrefix(fd, size);
      for (let index = 0; index < sample.length; index++) {
        if (next[index] !== sample[index]) throw userNotice(AppText.text($r('app.string.read_incomplete')));
      }
    }
    const encoding = probe.encodings[attempt];
    const decoder = new DocumentDecoder(encoding, expected);
    if (!decoder.push(sample.subarray(probe.bomLength), sample.length === size)) continue;
    const md = cryptoFramework.createMd('SHA256');
    if (sample.length > 0) await md.update({ data: sample });
    const valid = await readChunks(fd, sample.length, size, async (chunk: Uint8Array, last: boolean): Promise<boolean> => {
      if (!decoder.push(chunk, last)) return false;
      await md.update({ data: chunk });
      return true;
    });
    if (valid) return new InspectedDocument(decoder.finish(encoding, probe.bomLength > 0), await digestHex(md));
  }
  throw userNotice(AppText.text($r('app.string.encoding_unknown')));
}

/** The private file starts empty. Verify with the same detection and normalization used when reopening a URI. */
export async function writeVerifiedText(fd: number, text: string, info: DocumentInfo, interrupted: string):
  Promise<InspectedDocument> {
  await TextEncoding.encode(text, info, (bytes: Uint8Array): Promise<void> => writeAll(fd, bytes, interrupted));
  fileIo.lseek(fd, 0);
  return inspectDocument(fd, async (): Promise<number> => {
    fileIo.lseek(fd, 0);
    return fd;
  }, text);
}
