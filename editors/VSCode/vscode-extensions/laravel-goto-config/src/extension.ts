import * as vscode from 'vscode';

const SUPPORTED_LANGUAGES = ['php', 'blade'];
const CONFIG_PATTERN = /config\(\s*['"]([^'"]+)['"]\s*\)/gs;

export function activate(context: vscode.ExtensionContext): void {
    const decorator = vscode.window.createTextEditorDecorationType({
        textDecoration: 'underline',
        cursor: 'pointer',
    });

    const provider = new LaravelConfigDefinitionProvider();

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
        const regex = new RegExp(CONFIG_PATTERN.source, CONFIG_PATTERN.flags);
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

class LaravelConfigDefinitionProvider implements vscode.DefinitionProvider {
    async provideDefinition(
        document: vscode.TextDocument,
        position: vscode.Position
    ): Promise<vscode.Definition | null> {
        const text = document.getText();
        const offset = document.offsetAt(position);
        const configKey = this.extractConfigKeyAtOffset(text, offset);

        if (!configKey) {
            return null;
        }

        const dotIndex = configKey.indexOf('.');
        if (dotIndex === -1) {
            return this.findConfigFile(document, configKey, []);
        }

        const filename = configKey.substring(0, dotIndex);
        const keys = configKey.substring(dotIndex + 1).split('.');

        return this.findConfigFile(document, filename, keys);
    }

    private extractConfigKeyAtOffset(text: string, offset: number): string | null {
        const regex = new RegExp(CONFIG_PATTERN.source, CONFIG_PATTERN.flags);
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

    private async findConfigFile(
        document: vscode.TextDocument,
        filename: string,
        keys: string[]
    ): Promise<vscode.Location | null> {
        const workspaceFolder = vscode.workspace.getWorkspaceFolder(document.uri);
        if (!workspaceFolder) {
            return null;
        }

        const configUri = vscode.Uri.joinPath(
            workspaceFolder.uri,
            'config',
            `${filename}.php`
        );

        try {
            const configDoc = await vscode.workspace.openTextDocument(configUri);
            const position = this.resolveKeyPosition(configDoc.getText(), keys);
            return new vscode.Location(configUri, position);
        } catch {
            return null;
        }
    }

    private resolveKeyPosition(text: string, keys: string[]): vscode.Position {
        if (keys.length === 0) {
            return new vscode.Position(0, 0);
        }

        const lines = text.split('\n');
        let searchFromLine = 0;
        let foundLine = 0;
        let foundCol = 0;

        for (const key of keys) {
            const pattern = new RegExp(`['"]${this.escapeRegex(key)}['"]\\s*=>`);

            for (let i = searchFromLine; i < lines.length; i++) {
                const match = pattern.exec(lines[i]);
                if (match) {
                    foundLine = i;
                    foundCol = match.index;
                    searchFromLine = i + 1;
                    break;
                }
            }
        }

        return new vscode.Position(foundLine, foundCol);
    }

    private escapeRegex(str: string): string {
        return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    }
}
