import * as vscode from 'vscode';

const TERMINAL_NAME = 'PHPUnit';

export function getOrCreateTerminal(): vscode.Terminal {
  const existing = vscode.window.terminals.find(t => t.name === TERMINAL_NAME);
  if (existing) {
    return existing;
  }
  return vscode.window.createTerminal({ name: TERMINAL_NAME });
}

export function sendToTerminal(command: string): void {
  const terminal = getOrCreateTerminal();
  terminal.show(true);
  terminal.sendText(command);
}
