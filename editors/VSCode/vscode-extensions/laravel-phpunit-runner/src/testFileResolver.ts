import * as vscode from 'vscode';
import * as path from 'path';

export function isTestFilePath(filePath: string): boolean {
  return path.basename(filePath, '.php').endsWith('Test');
}

export async function resolveTestFile(filePath: string): Promise<vscode.Uri | undefined> {
  if (isTestFilePath(filePath)) {
    return vscode.Uri.file(filePath);
  }

  const baseName = path.basename(filePath, '.php');
  const pattern = new vscode.RelativePattern(
    vscode.workspace.workspaceFolders?.[0] ?? '',
    `**/${baseName}Test.php`,
  );

  const files = await vscode.workspace.findFiles(
    pattern,
    '{**/vendor/**,**/node_modules/**}',
  );

  return files[0];
}
