import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { openScratchFile } from '../storage/FileBytes';

export interface LocalImageRequest {
  id: number;
  key: string;
  widthPx: number;
  heightPx: number;
}

export interface LocalImageResult {
  file: fileIo.File;
  mime: string;
  intrinsicWidth: number;
  intrinsicHeight: number;
}


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

async function orientationOf(source: image.ImageSource, mime: string): Promise<number> {
  if (mime !== 'image/jpeg' && mime !== 'image/png' && mime !== 'image/webp') return 1;
  try {
    const value = await source.getImageProperty(image.PropertyKey.ORIENTATION);
    const labels = ['Top-left', 'Top-right', 'Bottom-right', 'Bottom-left',
      'Left-top', 'Right-top', 'Right-bottom', 'Left-bottom'];
    const index = labels.indexOf(value);
    if (index >= 0) return index + 1;
    const numeric = Number(value);
    if (Number.isInteger(numeric) && numeric >= 1 && numeric <= 8) return numeric;
  } catch { /* Images without Exif use their stored orientation. */ }
  return 1;
}

async function encodeThumbnail(source: image.ImageSource, size: image.Size, orientation: number,
  mime: string, fd: number): Promise<void> {
  // Image Kit downsamples JPEG and PNG while decoding. Other codecs can decode at full size internally.
  // https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/image-region-and-downsampling
  const pixels = await source.createPixelMap({ desiredSize: size, editable: orientation !== 1 });
  try {
    if (orientation === 2 || orientation === 5 || orientation === 7) await pixels.flip(true, false);
    if (orientation === 4) await pixels.flip(false, true);
    if (orientation === 3) await pixels.rotate(180);
    if (orientation === 5 || orientation === 8) await pixels.rotate(270);
    if (orientation === 6 || orientation === 7) await pixels.rotate(90);
    const packer = image.createImagePacker();
    try {
      await packer.packToFile(pixels, fd, { format: mime, quality: 90 });
    } finally {
      await packer.release();
    }
  } finally {
    await pixels.release();
  }
}

async function openRaster(fd: number, source: image.ImageSource, info: image.ImageInfo,
  mime: string, request: LocalImageRequest, cacheDir: string): Promise<LocalImageResult> {
  const orientation = await orientationOf(source, mime);
  const width = orientation >= 5 ? info.size.height : info.size.width;
  const height = orientation >= 5 ? info.size.width : info.size.height;
  if (width <= 0 || height <= 0) throw new Error('Invalid image dimensions');
  // Match the column; bound the pixel surface of very tall images to a viewport-sized buffer.
  const viewportPixels = request.widthPx * Math.max(request.heightPx, request.widthPx);
  const scale = Math.min(1, request.widthPx / width, Math.sqrt(viewportPixels / (width * height)),
    viewportPixels / Math.max(width, height));
  if (scale === 1 || ((mime === 'image/gif' || mime === 'image/webp') && await source.getFrameCount() > 1)) {
    // Let ArkWeb decode animation over time, without expanding every frame into PixelMaps.
    fileIo.lseek(fd, 0);
    return { file: fileIo.dup(fd), mime, intrinsicWidth: 0, intrinsicHeight: 0 };
  }
  const size: image.Size = {
    width: Math.max(1, Math.floor(info.size.width * scale)),
    height: Math.max(1, Math.floor(info.size.height * scale))
  };
  const outputMime = mime === 'image/jpeg' ? 'image/jpeg' : 'image/png';
  const thumbnail = await openScratchFile(cacheDir);
  try {
    await encodeThumbnail(source, size, orientation, outputMime, thumbnail.fd);
    fileIo.lseek(thumbnail.fd, 0);
    return { file: thumbnail, mime: outputMime, intrinsicWidth: width, intrinsicHeight: height };
  } catch (error) {
    await fileIo.close(thumbnail);
    throw error as Error;
  }
}

/** Read only the referenced file under the document directory, with the system's actual URI grants. */
export async function openLocalImage(documentUri: string, cacheDir: string, request: LocalImageRequest):
  Promise<LocalImageResult | null> {
  const relative = relativeImagePath(request.key);
  if (!documentUri || !relative) return null;
  const uri = imageUri(documentUri, relative);
  if (!uri) return null;
  const opened = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.NOFOLLOW);
  try {
    const stat = await fileIo.stat(opened.fd);
    if (!stat.isFile() || !Number.isSafeInteger(stat.size) || stat.size <= 0) return null;
    let source: image.ImageSource | undefined;
    try {
      let info: image.ImageInfo | undefined;
      try {
        source = image.createImageSource(opened.fd);
        info = await source.getImageInfo();
      } catch (error) {
        // ArkWeb can decode SVG image subresources even when the platform image codec cannot inspect them.
        if (extensionOf(relative) !== 'svg') throw error as Error;
      }
      if (info && source) {
        const mime = info.mimeType === 'image/x-ms-bmp' ? 'image/bmp' : info.mimeType;
        if (['image/png', 'image/jpeg', 'image/webp', 'image/gif', 'image/bmp'].includes(mime)) {
          return await openRaster(opened.fd, source, info, mime, request, cacheDir);
        }
      }
    } finally {
      if (source) await source.release();
    }
    if (extensionOf(relative) !== 'svg') return null;
    // Keep vector images in the isolated browser image context, including their intrinsic sizing.
    fileIo.lseek(opened.fd, 0);
    return { file: fileIo.dup(opened.fd), mime: 'image/svg+xml', intrinsicWidth: 0, intrinsicHeight: 0 };
  } finally {
    await fileIo.close(opened.fd);
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

/** The page reports its column width and native viewport height in physical pixels. */
export function sourcesFromPage(raw: string): LocalImageRequest[] | null {
  try {
    const text = jsonText(raw.trim());
    if (text === 'null') return null;
    const parsed = JSON.parse(text) as LocalImageRequest[];
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((item: LocalImageRequest): boolean => item !== null && typeof item === 'object' &&
      Number.isSafeInteger(item.id) && item.id > 0 && typeof item.key === 'string' && item.key.length > 0 &&
      Number.isSafeInteger(item.widthPx) && item.widthPx > 0 &&
      Number.isSafeInteger(item.heightPx) && item.heightPx > 0);
  } catch {
    return [];
  }
}
