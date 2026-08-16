export type TestMethod = {
  name: string;
  lineStart: number;
};

export type ParseResult = {
  isTestFile: boolean;
  className?: string;
  methods: TestMethod[];
};

const METHOD_NAME_PATTERN = '[a-zA-Z_-￿][a-zA-Z0-9_-￿]*';

export function parsePhp(content: string): ParseResult {
  const lines = content.split('\n');
  let className: string | undefined;
  let isTestFile = false;
  const methods: TestMethod[] = [];

  let inDocBlock = false;
  let hasTestAnnotation = false;

  for (let i = 0; i < lines.length; i++) {
    const trimmed = lines[i].trim();

    const classMatch = trimmed.match(
      /^(?:(?:abstract|final)\s+)?class\s+([a-zA-Z_-￿][a-zA-Z0-9_-￿]*)(?:\s+extends\s+([a-zA-Z_\\][a-zA-Z0-9_\\]*))?/,
    );
    if (classMatch) {
      className = classMatch[1];
      const extendsName = classMatch[2] ?? '';
      isTestFile =
        className.endsWith('Test') ||
        extendsName.endsWith('TestCase');
    }

    if (/\/\*\*/.test(trimmed)) {
      inDocBlock = true;
      hasTestAnnotation = false;
    }
    if (inDocBlock && /@test\b/.test(trimmed)) {
      hasTestAnnotation = true;
    }
    if (/\*\//.test(trimmed)) {
      inDocBlock = false;
    }

    const testPrefixMatch = trimmed.match(
      new RegExp(`^(?:public\\s+)?function\\s+(test${METHOD_NAME_PATTERN})\\s*\\(`),
    );
    if (testPrefixMatch) {
      methods.push({ name: testPrefixMatch[1], lineStart: i });
      hasTestAnnotation = false;
      continue;
    }

    if (hasTestAnnotation) {
      const annotatedMatch = trimmed.match(
        new RegExp(`^(?:public\\s+)?function\\s+(${METHOD_NAME_PATTERN})\\s*\\(`),
      );
      if (annotatedMatch) {
        methods.push({ name: annotatedMatch[1], lineStart: i });
        hasTestAnnotation = false;
      }
    }
  }

  return { isTestFile, className, methods };
}

export function findMethodAtLine(methods: TestMethod[], line: number): TestMethod | undefined {
  let found: TestMethod | undefined;
  for (const method of methods) {
    if (method.lineStart <= line) {
      found = method;
    }
  }
  return found;
}

export function findClassLine(lines: string[]): number | undefined {
  for (let i = 0; i < lines.length; i++) {
    if (/^(?:(?:abstract|final)\s+)?class\s+\w/.test(lines[i].trim())) {
      return i;
    }
  }
  return undefined;
}
