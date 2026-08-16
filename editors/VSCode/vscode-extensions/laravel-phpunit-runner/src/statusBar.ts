import * as vscode from 'vscode';

const IDLE_TEXT = '$(beaker) PHPUnit';
const RUNNING_TEXT = '$(sync~spin) PHPUnit';
const RUNNING_TIMEOUT_MS = 30_000;

export class StatusBarManager implements vscode.Disposable {
  private readonly item: vscode.StatusBarItem;
  private resetTimer?: ReturnType<typeof setTimeout>;

  constructor() {
    this.item = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
    this.item.command = 'laravelPhpunitRunner.runFileTests';
    this.item.tooltip = 'Run PHPUnit tests for current file';
    this.item.text = IDLE_TEXT;
  }

  startRunning(): void {
    if (this.resetTimer) {
      clearTimeout(this.resetTimer);
    }
    this.item.text = RUNNING_TEXT;
    this.item.tooltip = 'PHPUnit is running…';
    this.resetTimer = setTimeout(() => this.resetIdle(), RUNNING_TIMEOUT_MS);
  }

  private resetIdle(): void {
    this.item.text = IDLE_TEXT;
    this.item.tooltip = 'Run PHPUnit tests for current file';
    this.resetTimer = undefined;
  }

  updateForEditor(editor: vscode.TextEditor | undefined): void {
    if (editor?.document.languageId === 'php') {
      this.item.show();
    } else {
      this.item.hide();
    }
  }

  dispose(): void {
    if (this.resetTimer) {
      clearTimeout(this.resetTimer);
    }
    this.item.dispose();
  }
}
