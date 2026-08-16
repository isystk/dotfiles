import * as vscode from 'vscode';

const SUPPORTED_LANGUAGES = ['blade'];

const VITE_SINGLE_PATTERN = /@vite\(\s*['"]([^'"]+)['"]\s*\)/gs;
const VITE_ARRAY_PATTERN = /@vite\(\s*\[([^\]]+)\]\s*\)/gs;
const QUOTED_STRING_PATTERN = /['"]([^'"]+)['"]/g;

export function activate(context: vscode.ExtensionContext): void {
    const decorator = vscode.window.createTextEditorDecorationType({
        textDecoration: 'underline',
        cursor: 'pointer',
    });

    const provider = new ViteDefinitionProvider();

    for (const language of SUPPORTED_LANGUAGES) {
        context.subscriptions.push(
            vscode.languages.registerDefinitionProvider(
                { scheme: '*', language },
                provider
            )
        );
    }

    function updateDecorations(editor: vscode.TextEditor): void {
        if (!SUPPORTED_LANGUAGES.includes(editor.document.languageId)) {
            return;
        }

        const text = editor.document.getText();
        const ranges: vscode.Range[] = [];

        for (const pattern of [VITE_SINGLE_PATTERN, VITE_ARRAY_PATTERN]) {
            const regex = new RegExp(pattern.source, pattern.flags);
            let match: RegExpExecArray | null;

            while ((match = regex.exec(text)) !== null) {
                const start = editor.document.positionAt(match.index);
                const end = editor.document.positionAt(match.index + match[0].length);
                ranges.push(new vscode.Range(start, end));
            }
        }

        editor.setDecorations(decorator, ranges);
    }

    if (vscode.window.activeTextEditor) {
        updateDecorations(vscode.window.activeTextEditor);
    }

    context.subscriptions.push(
        decorator,
        vscode.window.onDidChangeActiveTextEditor(editor => {
            if (editor) {
                updateDecorations(editor);
            }
        }),
        vscode.workspace.onDidChangeTextDocument(event => {
            const editor = vscode.window.activeTextEditor;
            if (editor && event.document === editor.document) {
                updateDecorations(editor);
            }
        })
    );
}

export function deactivate(): void {}

class ViteDefinitionProvider implements vscode.DefinitionProvider {
    async provideDefinition(
        document: vscode.TextDocument,
        position: vscode.Position
    ): Promise<vscode.Definition | null> {
        const text = document.getText();
        const offset = document.offsetAt(position);

        const singleResult = this.extractSinglePath(text, offset);
        if (singleResult) {
            return this.resolveLocation(document, singleResult);
        }

        const arrayPaths = this.extractArrayPaths(text, offset);
        if (arrayPaths.length === 1) {
            return this.resolveLocation(document, arrayPaths[0]);
        }

        if (arrayPaths.length > 1) {
            const items = arrayPaths.map(p => ({ label: p, path: p }));
            const selected = await vscode.window.showQuickPick(items, {
                placeHolder: 'Select a file to open',
            });
            if (selected) {
                return this.resolveLocation(document, selected.path);
            }
        }

        return null;
    }

    private extractSinglePath(text: string, offset: number): string | null {
        const regex = new RegExp(VITE_SINGLE_PATTERN.source, VITE_SINGLE_PATTERN.flags);
        let match: RegExpExecArray | null;

        while ((match = regex.exec(text)) !== null) {
            if (offset >= match.index && offset <= match.index + match[0].length) {
                return match[1];
            }
        }

        return null;
    }

    private extractArrayPaths(text: string, offset: number): string[] {
        const regex = new RegExp(VITE_ARRAY_PATTERN.source, VITE_ARRAY_PATTERN.flags);
        let match: RegExpExecArray | null;

        while ((match = regex.exec(text)) !== null) {
            if (offset >= match.index && offset <= match.index + match[0].length) {
                const paths: string[] = [];
                const inner = match[1];
                const strRegex = new RegExp(QUOTED_STRING_PATTERN.source, QUOTED_STRING_PATTERN.flags);
                let strMatch: RegExpExecArray | null;

                while ((strMatch = strRegex.exec(inner)) !== null) {
                    paths.push(strMatch[1]);
                }

                return paths;
            }
        }

        return [];
    }

    private async resolveLocation(
        document: vscode.TextDocument,
        filePath: string
    ): Promise<vscode.Location | null> {
        const workspaceFolder = vscode.workspace.getWorkspaceFolder(document.uri);
        if (!workspaceFolder) {
            return null;
        }

        const fileUri = vscode.Uri.joinPath(workspaceFolder.uri, filePath);

        try {
            await vscode.workspace.fs.stat(fileUri);
            return new vscode.Location(fileUri, new vscode.Position(0, 0));
        } catch {
            vscode.window.showWarningMessage(`File not found: ${filePath}`);
            return null;
        }
    }
}
