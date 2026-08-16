import * as vscode from 'vscode';

const SUPPORTED_LANGUAGES = ['php', 'blade'];

const ROUTE_CALL_PATTERN = /route\(\s*['"]([^'"]+)['"]\s*[,)]/gs;

export function activate(context: vscode.ExtensionContext): void {
    const decorator = vscode.window.createTextEditorDecorationType({
        textDecoration: 'underline',
        cursor: 'pointer',
    });

    const provider = new LaravelRouteDefinitionProvider();

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
        const regex = new RegExp(ROUTE_CALL_PATTERN.source, ROUTE_CALL_PATTERN.flags);
        let match: RegExpExecArray | null;

        while ((match = regex.exec(text)) !== null) {
            const start = editor.document.positionAt(match.index);
            const end = editor.document.positionAt(match.index + match[0].length);
            ranges.push(new vscode.Range(start, end));
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

class LaravelRouteDefinitionProvider implements vscode.DefinitionProvider {
    async provideDefinition(
        document: vscode.TextDocument,
        position: vscode.Position
    ): Promise<vscode.Definition | null> {
        const text = document.getText();
        const offset = document.offsetAt(position);
        const routeName = this.extractRouteNameAtOffset(text, offset);

        if (!routeName) {
            return null;
        }

        return this.findRouteDefinition(document, routeName);
    }

    private extractRouteNameAtOffset(text: string, offset: number): string | null {
        const regex = new RegExp(ROUTE_CALL_PATTERN.source, ROUTE_CALL_PATTERN.flags);
        let match: RegExpExecArray | null;

        while ((match = regex.exec(text)) !== null) {
            const start = match.index;
            const end = match.index + match[0].length;
            if (offset >= start && offset <= end) {
                return match[1];
            }
        }

        return null;
    }

    private async findRouteDefinition(
        document: vscode.TextDocument,
        routeName: string
    ): Promise<vscode.Location | null> {
        const workspaceFolder = vscode.workspace.getWorkspaceFolder(document.uri);
        if (!workspaceFolder) {
            return null;
        }

        const routeFiles = await vscode.workspace.findFiles(
            new vscode.RelativePattern(workspaceFolder, 'routes/**/*.php')
        );

        for (const fileUri of routeFiles) {
            const location = await this.searchInRouteFile(fileUri, routeName);
            if (location) {
                return location;
            }
        }

        return null;
    }

    private async searchInRouteFile(
        fileUri: vscode.Uri,
        routeName: string
    ): Promise<vscode.Location | null> {
        try {
            const doc = await vscode.workspace.openTextDocument(fileUri);
            const text = doc.getText();

            const exactLocation = this.findExactName(doc, text, routeName);
            if (exactLocation) {
                return exactLocation;
            }

            return this.findByGroupPrefix(doc, text, routeName);
        } catch {
            return null;
        }
    }

    private findExactName(
        doc: vscode.TextDocument,
        text: string,
        routeName: string
    ): vscode.Location | null {
        const pattern = new RegExp(
            `->name\\(\\s*['"]${this.escapeRegex(routeName)}['"]\\s*\\)`,
            'g'
        );
        const match = pattern.exec(text);
        if (!match) {
            return null;
        }
        return new vscode.Location(doc.uri, doc.positionAt(match.index));
    }

    private findByGroupPrefix(
        doc: vscode.TextDocument,
        text: string,
        routeName: string
    ): vscode.Location | null {
        const lines = text.split('\n');
        const prefixStack: string[] = [];
        let currentPrefix = '';

        for (let lineIndex = 0; lineIndex < lines.length; lineIndex++) {
            const line = lines[lineIndex];

            const openBraces = (line.match(/\{/g) ?? []).length;
            const closeBraces = (line.match(/\}/g) ?? []).length;

            const nameGroupMatch = /->name\(\s*['"]([^'"]+)['"]\s*\).*group\s*\(/.exec(line);
            if (nameGroupMatch) {
                prefixStack.push(currentPrefix);
                currentPrefix = currentPrefix + nameGroupMatch[1];
            } else if (openBraces > closeBraces) {
                prefixStack.push(currentPrefix);
            } else if (closeBraces > openBraces && prefixStack.length > 0) {
                currentPrefix = prefixStack.pop() ?? '';
            }

            const nameMatch = /->name\(\s*['"]([^'"]+)['"]\s*\)/.exec(line);
            if (nameMatch) {
                const fullName = currentPrefix + nameMatch[1];
                if (fullName === routeName) {
                    const col = line.indexOf('->name(');
                    return new vscode.Location(
                        doc.uri,
                        new vscode.Position(lineIndex, col < 0 ? 0 : col)
                    );
                }
            }
        }

        return null;
    }

    private escapeRegex(str: string): string {
        return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    }
}
