import { fileIo, fileUri } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

/** 单张图片的读取上限。超过后保留占位，不阻止文稿打开。 */
const MAX_IMAGE_BYTES: number = 32 * 1024 * 1024;
/** 控制编码后缓存的内存，不限制文稿中的图片数量。 */
const MAX_CACHE_BYTES: number = 8 * 1024 * 1024;

export class PreviewImage {
  key: string = '';
  dataUrl: string = '';

  constructor(key: string, dataUrl: string) {
    this.key = key;
    this.dataUrl = dataUrl;
  }
}

class CachedImage {
  stamp: string = '';
  dataUrl: string = '';
}

const cache: Map<string, CachedImage> = new Map<string, CachedImage>();
const cacheOrder: string[] = [];
let cacheBytes: number = 0;

function isImageExtension(extension: string): boolean {
  return extension === 'png' || extension === 'jpg' || extension === 'jpeg' ||
    extension === 'gif' || extension === 'webp' || extension === 'bmp' || extension === 'svg';
}

function hasScheme(value: string): boolean {
  const slash = value.indexOf('/');
  const head = slash >= 0 ? value.substring(0, slash) : value;
  return head.indexOf(':') > 0;
}

/**
 * 只接受相对文稿目录的图片路径。绝对地址、网络地址和逃出目录的 `..` 都不读。
 * 返回的路径使用 `/`，并已去掉 `.` 与可折回的 `..`。
 */
function relativeImagePath(src: string): string {
  const trimmed = src.trim();
  const hash = trimmed.indexOf('#');
  const value = hash >= 0 ? trimmed.substring(0, hash) : trimmed;
  if (value.length === 0 || value.indexOf('?') >= 0 || value.startsWith('/') || value.startsWith('//')) return '';
  if (hasScheme(value)) return '';
  let decoded = '';
  try {
    decoded = decodeURIComponent(value);
  } catch {
    return '';
  }
  decoded = decoded.split('\\').join('/');
  if (decoded.length === 0 || decoded.indexOf('\0') >= 0 || decoded.indexOf('?') >= 0 ||
    decoded.indexOf('#') >= 0 || decoded.startsWith('/') || hasScheme(decoded)) return '';
  const raw = decoded.split('/');
  const parts: string[] = [];
  for (let index = 0; index < raw.length; index++) {
    const part = raw[index];
    if (part.length === 0 || part === '.') continue;
    if (part === '..') {
      if (parts.length === 0) return '';
      parts.pop();
      continue;
    }
    parts.push(part);
  }
  if (parts.length === 0) return '';
  const name = parts[parts.length - 1];
  const dot = name.lastIndexOf('.');
  if (dot <= 0 || dot === name.length - 1) return '';
  if (!isImageExtension(name.substring(dot + 1).toLowerCase())) return '';
  return parts.join('/');
}

function extensionOf(relativePath: string): string {
  const slash = relativePath.lastIndexOf('/');
  const name = slash >= 0 ? relativePath.substring(slash + 1) : relativePath;
  const dot = name.lastIndexOf('.');
  return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/** FileUri.getFullDirectoryUri 返回文件所在目录的 URI。拼出来的文件 URI 不保证能打开。 */
function imageUri(documentUri: string, relativePath: string): string {
  let directory = '';
  try {
    directory = new fileUri.FileUri(documentUri).getFullDirectoryUri();
  } catch {
    return '';
  }
  if (directory.length === 0) return '';
  const prefix = directory.endsWith('/') ? directory : directory + '/';
  const segments = relativePath.split('/');
  let encoded = '';
  for (let index = 0; index < segments.length; index++) {
    if (index > 0) encoded += '/';
    encoded += encodeURIComponent(segments[index]);
  }
  return prefix + encoded;
}

function remember(key: string, stamp: string, dataUrl: string): void {
  const existing = cacheOrder.indexOf(key);
  if (existing >= 0) cacheOrder.splice(existing, 1);
  const previous = cache.get(key);
  if (previous !== undefined) cacheBytes -= previous.dataUrl.length * 2;
  cache.delete(key);
  const size = dataUrl.length * 2;
  if (size > MAX_CACHE_BYTES) return;
  cacheOrder.push(key);
  const entry = new CachedImage();
  entry.stamp = stamp;
  entry.dataUrl = dataUrl;
  cache.set(key, entry);
  cacheBytes += size;
  while (cacheBytes > MAX_CACHE_BYTES) {
    const removed = cacheOrder.shift();
    if (removed !== undefined) {
      const old = cache.get(removed);
      if (old !== undefined) cacheBytes -= old.dataUrl.length * 2;
      cache.delete(removed);
    }
  }
}

function startsWith(bytes: Uint8Array, values: number[]): boolean {
  if (bytes.length < values.length) return false;
  for (let index = 0; index < values.length; index++) {
    if (bytes[index] !== values[index]) return false;
  }
  return true;
}

function svgAllowed(bytes: Uint8Array): boolean {
  let text = '';
  try {
    const decoder = util.TextDecoder.create('utf-8', { fatal: true, ignoreBOM: true });
    const decoded = decoder.decodeToString(bytes);
    text = decoded === undefined ? '' : decoded.toLowerCase();
  } catch {
    return false;
  }
  if (text.indexOf('<svg') < 0) return false;
  if (text.indexOf('<script') >= 0 || text.indexOf('foreignobject') >= 0 || text.indexOf('javascript:') >= 0) {
    return false;
  }
  const plain = text.split('http://www.w3.org/2000/svg').join('').split('http://www.w3.org/1999/xlink').join('');
  return plain.indexOf('http://') < 0 && plain.indexOf('https://') < 0;
}

function mimeOf(bytes: Uint8Array, extension: string): string {
  if (startsWith(bytes, [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (startsWith(bytes, [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (startsWith(bytes, [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (bytes.length >= 12 && startsWith(bytes, [0x52, 0x49, 0x46, 0x46]) &&
    bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) return 'image/webp';
  if (startsWith(bytes, [0x42, 0x4D])) return 'image/bmp';
  if (extension === 'svg' && svgAllowed(bytes)) return 'image/svg+xml';
  return '';
}

async function readImage(uri: string, extension: string): Promise<string> {
  let opened: fileIo.File | null = null;
  try {
    opened = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.NOFOLLOW);
    const info = await fileIo.stat(opened.fd);
    if (!info.isFile() || !Number.isInteger(info.size) || info.size <= 0 || info.size > MAX_IMAGE_BYTES) return '';
    const stamp = info.size.toString() + ':' + info.mtime.toString();
    const cached = cache.get(uri);
    if (cached !== undefined && cached.stamp === stamp) {
      remember(uri, stamp, cached.dataUrl);
      return cached.dataUrl;
    }
    const buffer = new ArrayBuffer(info.size);
    const count = await fileIo.read(opened.fd, buffer, { length: info.size });
    if (count !== info.size) return '';
    const bytes = new Uint8Array(buffer);
    const mime = mimeOf(bytes, extension);
    if (mime.length === 0) return '';
    const dataUrl = 'data:' + mime + ';base64,' + new util.Base64Helper().encodeToStringSync(bytes);
    remember(uri, stamp, dataUrl);
    return dataUrl;
  } catch {
    return '';
  } finally {
    if (opened !== null) {
      try {
        await fileIo.close(opened.fd);
      } catch {
        // 文件可能已经关闭。
      }
    }
  }
}

function jsonText(value: string): string {
  if (!value.startsWith('"')) return value;
  try {
    const parsed = JSON.parse(value) as string;
    return typeof parsed === 'string' ? parsed : value;
  } catch {
    return value;
  }
}

/** 解析网页返回的图片地址列表。地址来自 markdown-it，还没经过授权判断。 */
export function sourcesFromPage(raw: string): string[] {
  const text = jsonText(raw.trim());
  if (text.length === 0 || text === 'null' || text === 'undefined') return [];
  try {
    const parsed = JSON.parse(text) as string[];
    if (!Array.isArray(parsed)) return [];
    const sources: string[] = [];
    for (let index = 0; index < parsed.length; index++) {
      const item = parsed[index];
      if (typeof item === 'string' && item.length > 0 && sources.indexOf(item) < 0) sources.push(item);
    }
    return sources;
  } catch {
    return [];
  }
}

/**
 * 按系统授权逐张读取。文稿 URI 不代表目录可读；某一张打不开时跳过，调用方仍显示文稿。
 * 网络图片和绝对路径在这里被丢掉，不会发起访问。
 */
export async function loadLocalImages(documentUri: string, sources: string[]): Promise<PreviewImage[]> {
  const images: PreviewImage[] = [];
  if (documentUri.length === 0) return images;
  for (let index = 0; index < sources.length; index++) {
    const key = sources[index];
    const relative = relativeImagePath(key);
    if (relative.length === 0) continue;
    const uri = imageUri(documentUri, relative);
    if (uri.length === 0) continue;
    const dataUrl = await readImage(uri, extensionOf(relative));
    if (dataUrl.length === 0) continue;
    images.push(new PreviewImage(key, dataUrl));
  }
  return images;
}
