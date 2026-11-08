/**
 * Small, dependency-free syntax highlighter for fenced code blocks.
 *
 * The goal is readability, not full grammar support: comments, strings,
 * numbers, keywords and obvious function calls are enough to make a code
 * block scannable on a tablet. Unknown languages render as plain text.
 *
 * Pure functions only so the tokenizer can be tested under Node.
 */

export const TOKEN_PLAIN: string = 'plain';
export const TOKEN_KEYWORD: string = 'keyword';
export const TOKEN_STRING: string = 'string';
export const TOKEN_COMMENT: string = 'comment';
export const TOKEN_NUMBER: string = 'number';
export const TOKEN_FUNCTION: string = 'function';

export interface CodeSegment {
  text: string;
  kind: string;
}

interface LanguageRules {
  family: string;
  lineComments: string[];
  blockComment: boolean;
  keywords: string[];
}

const JS_KEYWORDS: string[] = [
  'const', 'let', 'var', 'function', 'return', 'if', 'else', 'for', 'while',
  'do', 'switch', 'case', 'break', 'continue', 'class', 'extends', 'new',
  'this', 'super', 'import', 'from', 'export', 'default', 'async', 'await',
  'try', 'catch', 'finally', 'throw', 'typeof', 'instanceof', 'in', 'of',
  'interface', 'type', 'enum', 'implements', 'public', 'private', 'protected',
  'static', 'readonly', 'true', 'false', 'null', 'undefined', 'void',
  'yield', 'delete', 'as', 'satisfies', 'namespace', 'declare'
];

const PY_KEYWORDS: string[] = [
  'def', 'class', 'return', 'if', 'elif', 'else', 'for', 'while', 'in',
  'not', 'and', 'or', 'import', 'from', 'as', 'with', 'try', 'except',
  'finally', 'raise', 'pass', 'break', 'continue', 'lambda', 'True',
  'False', 'None', 'is', 'global', 'nonlocal', 'assert', 'yield', 'async',
  'await', 'self', 'print'
];

const SH_KEYWORDS: string[] = [
  'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'do', 'done', 'case',
  'esac', 'function', 'return', 'exit', 'export', 'local', 'readonly',
  'source', 'echo', 'printf', 'cd', 'pwd', 'ls', 'cat', 'grep', 'sed',
  'awk', 'mkdir', 'rm', 'cp', 'mv', 'chmod', 'sudo'
];

const JSON_KEYWORDS: string[] = ['true', 'false', 'null'];

const JVM_KEYWORDS: string[] = [
  'class', 'interface', 'object', 'fun', 'val', 'var', 'return', 'if',
  'else', 'for', 'while', 'when', 'switch', 'case', 'break', 'continue',
  'new', 'this', 'super', 'import', 'package', 'public', 'private',
  'protected', 'static', 'final', 'void', 'int', 'long', 'double', 'float',
  'boolean', 'char', 'string', 'String', 'true', 'false', 'null', 'try',
  'catch', 'finally', 'throw', 'throws', 'extends', 'implements', 'data'
];

const GO_KEYWORDS: string[] = [
  'func', 'package', 'import', 'return', 'if', 'else', 'for', 'range',
  'switch', 'case', 'break', 'continue', 'var', 'const', 'type', 'struct',
  'interface', 'map', 'chan', 'go', 'defer', 'select', 'true', 'false',
  'nil', 'make', 'new', 'string', 'int', 'bool', 'error'
];

const RUST_KEYWORDS: string[] = [
  'fn', 'let', 'mut', 'const', 'struct', 'enum', 'impl', 'trait', 'use',
  'mod', 'pub', 'return', 'if', 'else', 'for', 'while', 'loop', 'match',
  'break', 'continue', 'true', 'false', 'Self', 'self', 'where', 'async',
  'await', 'move', 'ref', 'dyn', 'unsafe'
];

function rulesFor(lang: string): LanguageRules | null {
  const lower: string = lang.toLowerCase().replace(/^\./, '');
  if (lower === 'js' || lower === 'javascript' || lower === 'jsx' ||
    lower === 'ts' || lower === 'typescript' || lower === 'tsx' ||
    lower === 'ets' || lower === 'arkts' || lower === 'dart') {
    return {
      family: 'js',
      lineComments: ['//'],
      blockComment: true,
      keywords: JS_KEYWORDS
    };
  }
  if (lower === 'py' || lower === 'python') {
    return { family: 'py', lineComments: ['#'], blockComment: false, keywords: PY_KEYWORDS };
  }
  if (lower === 'sh' || lower === 'bash' || lower === 'shell' ||
    lower === 'zsh' || lower === 'console' || lower === 'shellscript') {
    return { family: 'sh', lineComments: ['#'], blockComment: false, keywords: SH_KEYWORDS };
  }
  if (lower === 'json' || lower === 'json5') {
    return { family: 'json', lineComments: [], blockComment: false, keywords: JSON_KEYWORDS };
  }
  if (lower === 'kt' || lower === 'kotlin' || lower === 'java' ||
    lower === 'swift' || lower === 'c' || lower === 'cpp' ||
    lower === 'c++' || lower === 'cs' || lower === 'csharp') {
    return {
      family: 'jvm',
      lineComments: ['//'],
      blockComment: true,
      keywords: JVM_KEYWORDS
    };
  }
  if (lower === 'go' || lower === 'golang') {
    return { family: 'go', lineComments: ['//'], blockComment: true, keywords: GO_KEYWORDS };
  }
  if (lower === 'rs' || lower === 'rust') {
    return { family: 'rust', lineComments: ['//'], blockComment: true, keywords: RUST_KEYWORDS };
  }
  return null;
}

function isIdentifierStart(code: number): boolean {
  return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) ||
    code === 95 || code === 36;
}

function isIdentifierPart(code: number): boolean {
  return isIdentifierStart(code) || (code >= 48 && code <= 57);
}

function isDigit(code: number): boolean {
  return code >= 48 && code <= 57;
}

export function highlightCode(source: string, lang: string): CodeSegment[] {
  const rules: LanguageRules | null = rulesFor(lang);
  if (rules === null || source.length === 0 || source.length > 20000) {
    return [{ text: source, kind: TOKEN_PLAIN }];
  }
  const segments: CodeSegment[] = [];
  let buffer: string = '';
  let bufferKind: string = TOKEN_PLAIN;
  let inBlockComment: boolean = false;

  const flush = (): void => {
    if (buffer.length > 0) {
      segments.push({ text: buffer, kind: bufferKind });
      buffer = '';
    }
  };
  const emit = (text: string, kind: string): void => {
    if (text.length === 0) {
      return;
    }
    if (kind !== bufferKind) {
      flush();
      bufferKind = kind;
    }
    buffer += text;
  };

  let i: number = 0;
  while (i < source.length) {
    const code: number = source.charCodeAt(i);
    if (inBlockComment) {
      const end: number = source.indexOf('*/', i);
      if (end < 0) {
        emit(source.substring(i), TOKEN_COMMENT);
        i = source.length;
      } else {
        emit(source.substring(i, end + 2), TOKEN_COMMENT);
        i = end + 2;
        inBlockComment = false;
      }
      continue;
    }
    if (rules.blockComment && source.charAt(i) === '/' && source.charAt(i + 1) === '*') {
      inBlockComment = true;
      flush();
      bufferKind = TOKEN_COMMENT;
      continue;
    }
    let matchedComment: boolean = false;
    for (let c = 0; c < rules.lineComments.length; c++) {
      const marker: string = rules.lineComments[c];
      if (source.substr(i, marker.length) === marker) {
        const newline: number = source.indexOf('\n', i);
        const end: number = newline < 0 ? source.length : newline;
        emit(source.substring(i, end), TOKEN_COMMENT);
        i = end;
        matchedComment = true;
        break;
      }
    }
    if (matchedComment) {
      continue;
    }
    if (code === 34 || code === 39 || code === 96) {
      const quote: string = source.charAt(i);
      let j: number = i + 1;
      while (j < source.length) {
        const current: string = source.charAt(j);
        if (current === '\\') {
          j += 2;
          continue;
        }
        if (current === quote) {
          j++;
          break;
        }
        j++;
      }
      emit(source.substring(i, j), TOKEN_STRING);
      i = j;
      continue;
    }
    if (isDigit(code)) {
      let j: number = i + 1;
      while (j < source.length) {
        const c: number = source.charCodeAt(j);
        const ch: string = source.charAt(j);
        if (isIdentifierPart(c) || ch === '.') {
          j++;
        } else {
          break;
        }
      }
      emit(source.substring(i, j), TOKEN_NUMBER);
      i = j;
      continue;
    }
    if (isIdentifierStart(code)) {
      let j: number = i + 1;
      while (j < source.length && isIdentifierPart(source.charCodeAt(j))) {
        j++;
      }
      const word: string = source.substring(i, j);
      if (rules.keywords.indexOf(word) >= 0) {
        emit(word, TOKEN_KEYWORD);
      } else {
        let k: number = j;
        while (k < source.length && source.charAt(k) === ' ') {
          k++;
        }
        if (k < source.length && source.charAt(k) === '(') {
          emit(word, TOKEN_FUNCTION);
        } else {
          emit(word, TOKEN_PLAIN);
        }
      }
      i = j;
      continue;
    }
    emit(source.charAt(i), TOKEN_PLAIN);
    i++;
  }
  flush();
  return segments;
}
