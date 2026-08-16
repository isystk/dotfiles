import * as vscode from 'vscode';
import { getConfig, validateConfig } from './config';
import { buildDockerCommand, toContainerPath } from './dockerCommand';
import { parsePhp, findMethodAtLine } from './phpParser';
import { isTestFilePath, resolveTestFile } from './testFileResolver';
import { sendToTerminal } from './terminal';
import { StatusBarManager } from './statusBar';
import { PhpUnitCodeLensProvider } from './codeLensProvider';

let statusBar: StatusBarManager;

export function activate(context: vscode.ExtensionContext): void {
  statusBar = new StatusBarManager();
  context.subscriptions.push(statusBar);

  context.subscriptions.push(
    vscode.window.onDidChangeActiveTextEditor(editor => {
      statusBar.updateForEditor(editor);
    }),
  );
  statusBar.updateForEditor(vscode.window.activeTextEditor);

  const codeLensProvider = new PhpUnitCodeLensProvider();
  context.subscriptions.push(
    vscode.languages.registerCodeLensProvider({ language: 'php' }, codeLensProvider),
  );

  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration(e => {
      if (e.affectsConfiguration('laravelPhpunitRunner')) {
        codeLensProvider.refresh();
      }
    }),
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('laravelPhpunitRunner.runAllTests', () => {
      handleRunAllTests();
    }),
    vscode.commands.registerCommand(
      'laravelPhpunitRunner.runFileTests',
      (uri?: vscode.Uri) => {
        handleRunFileTests(uri);
      },
    ),
    vscode.commands.registerCommand(
      'laravelPhpunitRunner.runMethodTest',
      (uri?: vscode.Uri, methodName?: string) => {
        handleRunMethodTest(uri, methodName);
      },
    ),
    vscode.commands.registerCommand(
      'laravelPhpunitRunner.goToTestFile',
      (uri?: vscode.Uri) => {
        handleGoToTestFile(uri);
      },
    ),
  );
}

function guardConfig(): ReturnType<typeof getConfig> | null {
  const config = getConfig();
  const error = validateConfig(config);
  if (error) {
    vscode.window.showErrorMessage(error);
    return null;
  }
  return config;
}

function handleRunAllTests(): void {
  const config = guardConfig();
  if (!config) {
    return;
  }
  statusBar.startRunning();
  sendToTerminal(buildDockerCommand(config));
}

async function handleRunFileTests(uri?: vscode.Uri): Promise<void> {
  const config = guardConfig();
  if (!config) {
    return;
  }

  const sourceUri = uri ?? vscode.window.activeTextEditor?.document.uri;
  if (!sourceUri) {
    vscode.window.showWarningMessage('No active PHP file.');
    return;
  }

  const testUri = await resolveTestFile(sourceUri.fsPath);
  if (!testUri) {
    vscode.window.showWarningMessage(
      `No test file found for: ${sourceUri.fsPath}`,
    );
    return;
  }

  const containerPath = toContainerPath(testUri.fsPath, config);
  statusBar.startRunning();
  sendToTerminal(buildDockerCommand(config, containerPath));
}

async function handleRunMethodTest(uri?: vscode.Uri, methodName?: string): Promise<void> {
  const config = guardConfig();
  if (!config) {
    return;
  }

  const editor = vscode.window.activeTextEditor;
  const sourceUri = uri ?? editor?.document.uri;
  if (!sourceUri) {
    vscode.window.showWarningMessage('No active PHP file.');
    return;
  }

  let method = methodName;
  if (!method) {
    if (!editor) {
      vscode.window.showWarningMessage('No active editor.');
      return;
    }
    const filePath = editor.document.uri.fsPath;
    if (!isTestFilePath(filePath)) {
      const { isTestFile } = parsePhp(editor.document.getText());
      if (!isTestFile) {
        vscode.window.showWarningMessage(
          'Cursor-method mode requires an open test file. Use "Run Current File Tests" instead.',
        );
        return;
      }
    }
    const { methods } = parsePhp(editor.document.getText());
    const cursorLine = editor.selection.active.line;
    const found = findMethodAtLine(methods, cursorLine);
    if (!found) {
      vscode.window.showWarningMessage('No test method found at cursor position.');
      return;
    }
    method = found.name;
  }

  const testUri = await resolveTestFile(sourceUri.fsPath);
  if (!testUri) {
    vscode.window.showWarningMessage(
      `No test file found for: ${sourceUri.fsPath}`,
    );
    return;
  }

  const containerPath = toContainerPath(testUri.fsPath, config);
  statusBar.startRunning();
  sendToTerminal(buildDockerCommand(config, containerPath, method));
}

async function handleGoToTestFile(uri?: vscode.Uri): Promise<void> {
  const sourceUri = uri ?? vscode.window.activeTextEditor?.document.uri;
  if (!sourceUri) {
    vscode.window.showWarningMessage('No active PHP file.');
    return;
  }

  const testUri = await resolveTestFile(sourceUri.fsPath);
  if (!testUri) {
    vscode.window.showWarningMessage(
      `No test file found for: ${sourceUri.fsPath}`,
    );
    return;
  }

  await vscode.window.showTextDocument(testUri);
}

export function deactivate(): void {}
