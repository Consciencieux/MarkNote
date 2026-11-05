/**
 * Undo and redo for the editor buffer.
 *
 * ArkUI's TextArea exposes no undo interface — TextAreaController only offers caretPosition,
 * setTextSelection and stopEditing — so the history has to be kept here.
 *
 * Snapshots are the whole buffer, so consecutive typing is merged: edits that arrive within
 * MERGE_WINDOW_MS of each other collapse into one step. Without that, a few seconds of typing
 * would produce one snapshot per keystroke.
 *
 * The history is deliberately in memory only. Saving the history would let a reopened document
 * undo past the point where the file was saved, which contradicts the save behaviour.
 */

/** Edits closer together than this collapse into one undo step. */
const MERGE_WINDOW_MS: number = 600;

/** Older steps are dropped beyond this, so a long session cannot grow without bound. */
const MAX_STEPS: number = 200;

/** One undoable state: the buffer plus where the caret was when it was captured. */
export class EditStep {
  text: string;
  caret: number;

  constructor(text: string, caret: number) {
    this.text = text;
    this.caret = caret;
  }
}

export class EditHistory {
  private steps: EditStep[] = [];
  /** Index of the state currently on screen. -1 means the history is empty. */
  private current: number = -1;
  private lastRecorded: number = 0;

  /** Start over for a newly opened document. The opening text becomes the first step. */
  reset(text: string, caret: number): void {
    this.steps = [new EditStep(text, caret)];
    this.current = 0;
    this.lastRecorded = 0;
  }

  /**
   * Record the buffer after an edit. `now` comes from the caller so the merge window is testable.
   * The caret is stored with the snapshot so undo can restore the position, not just the text.
   */
  record(text: string, caret: number, now: number): void {
    // Opening a document can echo the current text back through onChange. An identical buffer
    // is not an edit, and recording it would make undo look available before anything changed.
    if (this.current >= 0 && this.steps[this.current].text === text) {
      this.steps[this.current] = new EditStep(text, caret);
      return;
    }
    // Editing after undoing discards the redo branch, as in any text editor.
    if (this.current < this.steps.length - 1) this.steps.splice(this.current + 1);

    const merging = this.current >= 0 && now - this.lastRecorded < MERGE_WINDOW_MS;
    if (merging) {
      this.steps[this.current] = new EditStep(text, caret);
      this.lastRecorded = now;
      return;
    }

    this.steps.push(new EditStep(text, caret));
    this.current = this.steps.length - 1;
    this.lastRecorded = now;
    if (this.steps.length > MAX_STEPS) {
      this.steps.shift();
      this.current = this.steps.length - 1;
    }
  }

  canUndo(): boolean {
    return this.current > 0;
  }

  canRedo(): boolean {
    return this.current >= 0 && this.current < this.steps.length - 1;
  }

  /** Step back one snapshot. Returns the state to restore, or null when nothing is left. */
  undo(caret: number): EditStep | null {
    if (!this.canUndo()) return null;
    this.steps[this.current] = new EditStep(this.steps[this.current].text, caret);
    this.current--;
    // Merging must not join an edit made after the undo to the step before it.
    this.lastRecorded = 0;
    return this.steps[this.current];
  }

  /** Step forward one snapshot, discarding the current state. */
  redo(caret: number): EditStep | null {
    if (!this.canRedo()) return null;
    this.steps[this.current] = new EditStep(this.steps[this.current].text, caret);
    this.current++;
    this.lastRecorded = 0;
    return this.steps[this.current];
  }
}
