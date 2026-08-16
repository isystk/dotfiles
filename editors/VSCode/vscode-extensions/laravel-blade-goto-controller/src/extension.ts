import * as vscode from 'vscode';

const VIEW_PATTERNS = [
    /view\(\s*['"]([^'"]+)['"]/g,
    /View::make\(\s*['"]([^'"]+)['"]/g,
    /view\(\)\s*->\s*make\(\s*['"]([^'"]+)['"]/g,
];

export function activate(context: vscode.ExtensionContext): void {
    context.subscriptions.push(
        vscode.languages.registerCodeLensProvider(
            { scheme: '*', language: 'blade' },
            new BladeControllerCodeLensProvider()
        ),
        vscode.commands.registerCommand(
            'laravel-blade-goto-controller.goto',
            gotoController
        )
    );
}

export function deactivate(): void {}

async function gotoController(uri?: vscode.Uri): Promise<void> {
    const targetUri = uri ?? vscode.window.activeTextEditor?.document.uri;
    if (!targetUri) {
        return;
    }

    const workspaceFolder = vscode.workspace.getWorkspaceFolder(targetUri);
    if (!workspaceFolder) {
        return;
    }

    const viewName = resolveViewName(targetUri, workspaceFolder.uri);
    if (!viewName) {
        vscode.window.showWarningMessage('This file is not inside resources/views/.');
        return;
    }

    await vscode.window.withProgress(
        { location: vscode.ProgressLocation.Notification, title: `Searching controller for: ${viewName}` },
        async () => {
            const locations = await findControllerLocations(workspaceFolder, viewName);

            if (locations.length === 0) {
                vscode.window.showInformationMessage(`No controller found for view: ${viewName}`);
                return;
            }

            if (locations.length === 1) {
                await openLocation(locations[0]);
                return;
            }

            const items = locations.map(loc => ({
                label: `$(file-code) ${vscode.workspace.asRelativePath(loc.uri)}`,
                description: `Line ${loc.range.start.line + 1}`,
                location: loc,
            }));

            const selected = await vscode.window.showQuickPick(items, {
                placeHolder: `${locations.length} controllers found for view: ${viewName}`,
            });

            if (selected) {
                await openLocation(selected.location);
            }
        }
    );
}

function resolveViewName(fileUri: vscode.Uri, workspaceUri: vscode.Uri): string | null {
    const filePath = fileUri.path;
    const viewsPath = workspaceUri.path + '/resources/views/';

    if (!filePath.startsWith(viewsPath)) {
        return null;
    }

    return filePath
        .substring(viewsPath.length)
        .replace(/\.blade\.php$/, '')
        .replace(/\//g, '.');
}

async function findControllerLocations(
    workspaceFolder: vscode.WorkspaceFolder,
    viewName: string
): Promise<vscode.Location[]> {
    const phpFiles = await vscode.workspace.findFiles(
        new vscode.RelativePattern(workspaceFolder, 'app/**/*.php')
    );

    const viewNameSlash = viewName.replace(/\./g, '/');
    const targets = new Set([viewName, viewNameSlash]);
    const locations: vscode.Location[] = [];

    await Promise.all(
        phpFiles.map(async fileUri => {
            const found = await searchViewInFile(fileUri, targets);
            locations.push(...found);
        })
    );

    return locations;
}

async function searchViewInFile(
    fileUri: vscode.Uri,
    targets: Set<string>
): Promise<vscode.Location[]> {
    try {
        const doc = await vscode.workspace.openTextDocument(fileUri);
        const text = doc.getText();
        const locations: vscode.Location[] = [];

        for (const basePattern of VIEW_PATTERNS) {
            const regex = new RegExp(basePattern.source, basePattern.flags);
            let match: RegExpExecArray | null;

            while ((match = regex.exec(text)) !== null) {
                if (targets.has(match[1])) {
                    locations.push(new vscode.Location(fileUri, doc.positionAt(match.index)));
                }
            }
        }

        return locations;
    } catch {
        return [];
    }
}

async function openLocation(location: vscode.Location): Promise<void> {
    const doc = await vscode.workspace.openTextDocument(location.uri);
    const editor = await vscode.window.showTextDocument(doc);
    editor.selection = new vscode.Selection(location.range.start, location.range.start);
    editor.revealRange(
        new vscode.Range(location.range.start, location.range.start),
        vscode.TextEditorRevealType.InCenter
    );
}

class BladeControllerCodeLensProvider implements vscode.CodeLensProvider {
    provideCodeLenses(document: vscode.TextDocument): vscode.CodeLens[] {
        return [
            new vscode.CodeLens(new vscode.Range(0, 0, 0, 0), {
                title: '$(go-to-file) Go to Controller',
                command: 'laravel-blade-goto-controller.goto',
                arguments: [document.uri],
            }),
        ];
    }
}
