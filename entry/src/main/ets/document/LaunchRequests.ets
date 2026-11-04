import { Want, wantConstant } from '@kit.AbilityKit';

/** One file the system asked EntryAbility to open. Held until the page can show it. */
export class OpenRequest {
  uri: string = '';
  declaredType: string = '';
  readGranted: boolean = false;
  writeGranted: boolean = false;
}

function textFromStream(stream: Object): string {
  if (typeof stream === 'string') return stream;
  if (!Array.isArray(stream) || stream.length === 0) return '';
  const first = stream[0] as Object;
  return typeof first === 'string' ? first : '';
}

export class LaunchRequests {
  private static pending: OpenRequest | null = null;
  private static handler: ((request: OpenRequest) => void) | null = null;

  static deliver(want: Want): void {
    const request = LaunchRequests.parse(want);
    if (request === null) return;
    const handler = LaunchRequests.handler;
    if (handler) handler(request);
    else LaunchRequests.pending = request;
  }

  static bind(handler: (request: OpenRequest) => void): void {
    LaunchRequests.handler = handler;
    const waiting = LaunchRequests.pending;
    LaunchRequests.pending = null;
    if (waiting !== null) handler(waiting);
  }

  static unbind(): void {
    LaunchRequests.handler = null;
  }

  /** Desktop launches have no file URI and stay on the library page. */
  static parse(want: Want): OpenRequest | null {
    let uri = want.uri !== undefined ? want.uri : '';
    const parameters = want.parameters;
    if (uri.length === 0 && parameters !== undefined) {
      const stream = parameters[wantConstant.Params.PARAMS_STREAM];
      if (stream !== undefined && stream !== null) uri = textFromStream(stream);
    }
    if (uri.length === 0) return null;
    const action = want.action !== undefined ? want.action : '';
    if (action.length > 0 && action !== 'ohos.want.action.viewData') return null;
    const request = new OpenRequest();
    request.uri = uri;
    request.declaredType = want.type !== undefined ? want.type : '';
    const flags = want.flags !== undefined ? want.flags : 0;
    request.readGranted = (flags & wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION) !== 0;
    request.writeGranted = (flags & wantConstant.Flags.FLAG_AUTH_WRITE_URI_PERMISSION) !== 0;
    return request;
  }
}
