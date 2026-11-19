/** Blocks document replacement until the existing recovery slot was checked successfully. */
export class StartupRecovery {
  private ready: boolean = false;
  private pending: Promise<boolean> | null = null;
  private attempt: () => Promise<boolean>;
  private onError: (error: Error) => void;

  constructor(attempt: () => Promise<boolean>, onError: (error: Error) => void) {
    this.attempt = attempt;
    this.onError = onError;
  }

  ensure(): Promise<boolean> {
    if (this.ready) return Promise.resolve(true);
    if (this.pending !== null) return this.pending;
    this.pending = this.run();
    return this.pending;
  }

  private async run(): Promise<boolean> {
    try {
      const ready = await this.attempt();
      if (ready) this.ready = true;
      return ready;
    } catch (error) {
      this.onError(error instanceof Error ? error : new Error('draft recovery failed'));
      return false;
    } finally {
      this.pending = null;
    }
  }
}
