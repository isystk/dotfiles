import * as vscode from 'vscode';
import { getConfig } from './config';
import { parsePhp, findClassLine } from './phpParser';
import { isTestFilePath, resolveTestFile } from './testFileResolver';

export class PhpUnitCodeLensProvider implements vscode.CodeLensProvider {
  private readonly _onDidChangeCodeLenses = new vscode.EventEmitter<void>();
  readonly onDidChangeCodeLenses: vscode.Event<void> = this._onDidChangeCodeLenses.event;

  refresh(): void {
    this._onDidChangeCodeLenses.fire();
  }

  async provideCodeLenses(document: vscode.TextDocument): Promise<vscode.CodeLens[]> {
    if (!getConfig().enableCodeLens) {
      return [];
    }

    const content = document.getText();
    const lines = content.split('\n');
    const { isTestFile, methods } = parsePhp(content);
    const lenses: vscode.CodeLens[] = [];

    if (isTestFile || isTestFilePath(document.uri.fsPath)) {
      const classLine = findClassLine(lines);
      if (classLine !== undefined) {
        lenses.push(
          new vscode.CodeLens(new vscode.Range(classLine, 0, classLine, 0), {
            title: 'Run Class',
            command: 'laravelPhpunitRunner.runFileTests',
            arguments: [document.uri],
          }),
        );
      }

      for (const method of methods) {
        lenses.push(
          new vscode.CodeLens(new vscode.Range(method.lineStart, 0, method.lineStart, 0), {
            title: 'Run',
            command: 'laravelPhpunitRunner.runMethodTest',
            arguments: [document.uri, method.name],
          }),
        );
      }

      return lenses;
    }

    const testUri = await resolveTestFile(document.uri.fsPath);
    if (testUri) {
      const range = new vscode.Range(0, 0, 0, 0);
      lenses.push(
        new vscode.CodeLens(range, {
          title: 'Run tests for this file',
          command: 'laravelPhpunitRunner.runFileTests',
          arguments: [document.uri],
        }),
        new vscode.CodeLens(range, {
          title: 'Go to test file',
          command: 'laravelPhpunitRunner.goToTestFile',
          arguments: [document.uri],
        }),
      );
    }

    return lenses;
  }
}
