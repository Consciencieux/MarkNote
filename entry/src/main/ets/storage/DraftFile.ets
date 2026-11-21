import { fileIo } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { RecoveryData } from '../model/Document';
import { AppText } from '../i18n/AppText';

// JSON strings are escaped and encoded one piece at a time. Splitting a surrogate
// pair is lossless: JSON escapes each unpaired half and join restores the pair.
const PIECE_UNITS = 32 * 1024;

interface DraftHeader {
  version: number;
  info: RecoveryData;
  fields: number[];
  lengths: number[];
}

function invalidDraft(): Error {
  const error = new Error('invalid draft');
  error.name = 'InvalidDraftError';
  return error;
}

function parseLine(line: string): Object {
  try {
    return JSON.parse(line) as Object;
  } catch {
    throw invalidDraft();
  }
}

// JSON Lines keeps each record independently decodable with the platform JSON parser.
// Equal source, baseline and pending-write snapshots share their data on disk.
export async function writeDraftFile(stream: fileIo.WriteStream, draft: RecoveryData): Promise<void> {
  const info = new RecoveryData();
  info.name = draft.name;
  info.uri = draft.uri;
  info.encoding = draft.encoding;
  info.hasBom = draft.hasBom;
  info.newline = draft.newline;
  info.fingerprint = draft.fingerprint;
  info.formatId = draft.formatId;
  info.writable = draft.writable;
  info.persistent = draft.persistent;
  info.writeUncertain = draft.writeUncertain;
  info.pendingWriteUri = draft.pendingWriteUri;
  const bodies: string[] = [];
  const fields: number[] = [];
  for (const field of [draft.text, draft.savedText, draft.pendingWriteText, draft.lineEndings]) {
    let index = bodies.indexOf(field);
    if (index < 0) index = bodies.push(field) - 1;
    fields.push(index);
  }
  const header: DraftHeader = { version: 2, info, fields, lengths: bodies.map((body: string) => body.length) };
  let expectedBytes = 0;
  const append = async (line: string): Promise<void> => {
    expectedBytes += buffer.byteLength(line, 'utf8');
    await new Promise<void>((resolve, reject) => {
      stream.write(line, 'utf-8', (error?: Error): void => {
        if (error) reject(error);
        else resolve();
      });
    });
  };
  await append(JSON.stringify(header) + '\n');
  for (const body of bodies) {
    for (let start = 0; start < body.length; start += PIECE_UNITS) {
      await append(JSON.stringify(body.slice(start, start + PIECE_UNITS)) + '\n');
    }
  }
  if (stream.bytesWritten !== expectedBytes) throw new Error(AppText.text($r('app.string.draft_interrupted')));
}

export async function readDraftFile(path: string): Promise<RecoveryData> {
  const lines = await fileIo.readLines(path);
  const nextLine = (): string => {
    const line = lines.next();
    if (line.done) throw invalidDraft();
    return line.value.trim();
  };
  const first = nextLine();
  // Legacy versions wrote the whole snapshot as one JSON object at this path.
  // Accept formatted legacy JSON too, without reading new-format bodies twice.
  if (!first.endsWith('}')) return parseLine(await fileIo.readText(path)) as RecoveryData;
  const header = parseLine(first) as DraftHeader;
  if (header && header.version === undefined) {
    if (!lines.next().done) throw invalidDraft();
    return header as Object as RecoveryData;
  }
  if (!header || header.version !== 2 || !header.info || typeof header.info !== 'object' ||
    !Array.isArray(header.lengths) || header.lengths.length === 0 || header.lengths.length > 4 ||
    !Array.isArray(header.fields) || header.fields.length !== 4) throw invalidDraft();
  const bodies: string[] = [];
  for (const length of header.lengths) {
    if (!Number.isSafeInteger(length) || length < 0) throw invalidDraft();
    const pieces: string[] = [];
    let used = 0;
    while (used < length) {
      const piece = parseLine(nextLine()) as string;
      if (typeof piece !== 'string' || !piece.length || piece.length > length - used) throw invalidDraft();
      pieces.push(piece);
      used += piece.length;
    }
    bodies.push(pieces.join(''));
  }
  if (!lines.next().done) throw invalidDraft();
  for (const index of header.fields) {
    if (!Number.isInteger(index) || index < 0 || index >= bodies.length) throw invalidDraft();
  }
  const info = header.info;
  info.text = bodies[header.fields[0]];
  info.savedText = bodies[header.fields[1]];
  info.pendingWriteText = bodies[header.fields[2]];
  info.lineEndings = bodies[header.fields[3]];
  return info;
}
