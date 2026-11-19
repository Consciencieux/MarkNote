import { Heading, documentOutline } from '../model/Document';
import { TextSearch } from './TextSearch';

const IDLE_MS: number = 120;
const DEADLINE_MS: number = 500;

export class AnalysisRequest {
  sessionId: number = 0;
  revision: number = 0;
  source: string = '';
  formatId: string = '';
  query: string = '';
  needOutline: boolean = false;
  needCount: boolean = false;
}

export class AnalysisResult {
  sessionId: number = 0;
  revision: number = 0;
  query: string = '';
  headings: Heading[] | null = null;
  matchCount: number | null = null;
}

/**
 * Merges outline and search-count work.
 * Typing updates the editor immediately; this class keeps one running pass and one latest request.
 */
export class DocumentAnalysis {
  private onResult: (result: AnalysisResult) => void;
  private pending: AnalysisRequest | null = null;
  private queued: AnalysisRequest | null = null;
  private running: boolean = false;
  private lastKey: string = '';
  private idleTimer: number = -1;
  private deadlineTimer: number = -1;
  private generation: number = 0;

  constructor(onResult: (result: AnalysisResult) => void) {
    this.onResult = onResult;
  }

  schedule(request: AnalysisRequest): void {
    if (!request.needOutline && !request.needCount) {
      this.pending = null;
      this.disarm();
      return;
    }
    const key = this.keyOf(request);
    if (key === this.lastKey && this.pending === null && this.queued === null && !this.running) return;
    this.pending = request;
    if (this.idleTimer >= 0) clearTimeout(this.idleTimer);
    this.idleTimer = setTimeout((): void => this.kick(), IDLE_MS);
    if (this.deadlineTimer < 0) this.deadlineTimer = setTimeout((): void => this.kick(), DEADLINE_MS);
  }

  flush(request: AnalysisRequest): Promise<AnalysisResult> {
    this.pending = null;
    this.queued = null;
    this.disarm();
    const result = this.compute(request);
    return Promise.resolve(result);
  }

  cancel(): void {
    this.generation++;
    this.pending = null;
    this.queued = null;
    this.disarm();
  }

  private keyOf(request: AnalysisRequest): string {
    return `${request.sessionId}|${request.revision}|${request.formatId}|${request.query}|${request.needOutline}|${request.needCount}`;
  }

  private disarm(): void {
    if (this.idleTimer >= 0) clearTimeout(this.idleTimer);
    if (this.deadlineTimer >= 0) clearTimeout(this.deadlineTimer);
    this.idleTimer = -1;
    this.deadlineTimer = -1;
  }

  private kick(): void {
    this.disarm();
    const request = this.pending;
    this.pending = null;
    if (request === null) return;
    if (this.running) {
      this.queued = request;
      return;
    }
    this.running = true;
    const ticket = this.generation;
    const result = this.compute(request);
    this.running = false;
    if (ticket === this.generation) this.onResult(result);
    if (this.queued !== null) {
      const next = this.queued;
      this.queued = null;
      this.pending = next;
      this.kick();
    }
  }

  private compute(request: AnalysisRequest): AnalysisResult {
    const result = new AnalysisResult();
    result.sessionId = request.sessionId;
    result.revision = request.revision;
    result.query = request.query;
    if (request.needOutline && request.formatId === 'markdown') result.headings = documentOutline(request.source);
    if (request.needCount && request.query.length > 0) {
      result.matchCount = TextSearch.count(request.source, request.query);
    }
    this.lastKey = this.keyOf(request);
    return result;
  }
}
