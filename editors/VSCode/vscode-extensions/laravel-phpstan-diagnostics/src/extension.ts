import * as vscode from 'vscode';
import { exec } from 'child_process';
import * as path from 'path';

let diagnosticCollection: vscode.DiagnosticCollection;

export function activate(context: vscode.ExtensionContext) {
    diagnosticCollection = vscode.languages.createDiagnosticCollection('phpstan-diagnostics');
    context.subscriptions.push(diagnosticCollection);

    vscode.workspace.onDidSaveTextDocument((document) => {
        if (document.languageId === 'php') {
            runDiagnostics(document);
        }
    }, null, context.subscriptions);
}

function runDiagnostics(document: vscode.TextDocument) {
    diagnosticCollection.delete(document.uri);

    const config = vscode.workspace.getConfiguration('laravelPhpstanDiagnostics');
    const containerName = config.get<string>('containerName', 'app');
    const localWorkspacePath = config.get<string>('localWorkspacePath', '/root/projects/app');
    const containerWorkspacePath = config.get<string>('containerWorkspacePath', '/var/www/html');

    // パス変換
    const localFilePath = document.uri.fsPath;
    if (!localFilePath.startsWith(localWorkspacePath)) {
        return; // Workspace外のファイルは無視
    }

    const relativePath = path.relative(localWorkspacePath, localFilePath);
    const containerFilePath = `${containerWorkspacePath}/${relativePath}`;

    const diagnostics: vscode.Diagnostic[] = [];

    // 1. Syntax Check (php -l)
    const syntaxCmd = `docker exec ${containerName} php -l ${containerFilePath}`;
    exec(syntaxCmd, (error, stdout, stderr) => {
        if (error && stdout.includes('Parse error')) {
            // Parse error: syntax error, unexpected token ... in /var/www/html/app/Foo.php on line 10
            const match = stdout.match(/Parse error: (.+) in .+ on line (\d+)/);
            if (match) {
                const message = match[1];
                const line = parseInt(match[2], 10) - 1;
                const range = document.lineAt(line).range;
                const diagnostic = new vscode.Diagnostic(range, `Syntax: ${message}`, vscode.DiagnosticSeverity.Error);
                diagnostics.push(diagnostic);
                diagnosticCollection.set(document.uri, diagnostics);
            }
        }

        // 2. PHPStan Check
        const phpstanCmd = `docker exec ${containerName} ./vendor/bin/phpstan analyse ${containerFilePath} --error-format=json`;
        exec(phpstanCmd, (stanError, stanStdout, stanStderr) => {
            if (stanStdout) {
                try {
                    // stdoutの最後の中括弧から探す (前段に余計な出力がある場合への対処)
                    const jsonStart = stanStdout.indexOf('{');
                    if (jsonStart !== -1) {
                        const jsonStr = stanStdout.substring(jsonStart);
                        const result = JSON.parse(jsonStr);
                        if (result && result.files) {
                            const fileErrors = result.files[containerFilePath];
                            if (fileErrors && fileErrors.messages) {
                                for (const msg of fileErrors.messages) {
                                    const line = msg.line ? msg.line - 1 : 0;
                                    const range = document.lineAt(line).range;
                                    const diagnostic = new vscode.Diagnostic(range, `PHPStan: ${msg.message}`, vscode.DiagnosticSeverity.Error);
                                    diagnostics.push(diagnostic);
                                }
                            }
                        }
                    }
                } catch (e) {
                    console.error('Failed to parse PHPStan JSON output', e);
                }
            }
            
            diagnosticCollection.set(document.uri, diagnostics);
        });
    });
}

export function deactivate() {
    if (diagnosticCollection) {
        diagnosticCollection.clear();
        diagnosticCollection.dispose();
    }
}
