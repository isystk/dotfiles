import * as vscode from 'vscode';

export type Config = {
  containerName: string;
  hostProjectRoot: string;
  containerWorkspacePath: string;
  composePath: string;
  enableCodeLens: boolean;
};

export function getConfig(): Config {
  const cfg = vscode.workspace.getConfiguration('laravelPhpunitRunner');
  return {
    containerName: cfg.get<string>('containerName', ''),
    hostProjectRoot: cfg.get<string>('hostProjectRoot', ''),
    containerWorkspacePath: cfg.get<string>('containerWorkspacePath', '/var/www/html'),
    composePath: cfg.get<string>('composePath', ''),
    enableCodeLens: cfg.get<boolean>('enableCodeLens', true),
  };
}

export function validateConfig(config: Config): string | null {
  if (!config.containerName) {
    return 'laravelPhpunitRunner.containerName is not configured. Please set it in settings.';
  }
  if (!config.hostProjectRoot) {
    return 'laravelPhpunitRunner.hostProjectRoot is not configured. Please set it in settings.';
  }
  return null;
}
