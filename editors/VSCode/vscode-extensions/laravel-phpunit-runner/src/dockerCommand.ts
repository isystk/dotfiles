import * as path from 'path';
import { Config } from './config';

function shellQuote(value: string): string {
  return `'${value.replace(/'/g, `'\\''`)}'`;
}

export function toContainerPath(hostFilePath: string, config: Config): string {
  const normalized = hostFilePath.replace(/\\/g, '/');
  const root = config.hostProjectRoot.replace(/\\/g, '/').replace(/\/$/, '');
  const relative = normalized.startsWith(root)
    ? normalized.slice(root.length).replace(/^\//, '')
    : path.basename(normalized);
  return `${config.containerWorkspacePath.replace(/\/$/, '')}/${relative}`;
}

export function buildDockerCommand(
  config: Config,
  testContainerPath?: string,
  filterMethod?: string,
): string {
  const phpunit = `${config.containerWorkspacePath.replace(/\/$/, '')}/vendor/bin/phpunit`;

  const baseArgs = '--stop-on-failure --display-phpunit-deprecations';
  let phpunitArgs = baseArgs;
  if (filterMethod && testContainerPath) {
    phpunitArgs += ` --filter ${shellQuote(filterMethod)} ${shellQuote(testContainerPath)}`;
  } else if (testContainerPath) {
    phpunitArgs += ` ${shellQuote(testContainerPath)}`;
  }

  const phpCmd = `php -d memory_limit=1G ${shellQuote(phpunit)} ${phpunitArgs}`;

  if (config.composePath) {
    const composeFile = `${config.composePath.replace(/\\/g, '/').replace(/\/$/, '')}/docker-compose.yml`;
    return `docker compose -f ${shellQuote(composeFile)} exec ${shellQuote(config.containerName)} ${phpCmd}`;
  }

  return `docker exec ${shellQuote(config.containerName)} ${phpCmd}`;
}
