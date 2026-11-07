/**
 * Small, dependency-free Markdown parser aimed at chat answers:
 * fenced code, headings, lists, quotes, rules, paragraphs and inline
 * bold / italic / code / links. It intentionally does not try to be a full
 * CommonMark implementation.
 */

export enum MdBlockKind {
  Paragraph = 'paragraph',
  Heading = 'heading',
  Code = 'code',
  ListItem = 'list',
  Quote = 'quote',
  Divider = 'divider'
}

export interface MdBlock {
  kind: MdBlockKind;
  text: string;
  level: number;
  lang: string;
  ordered: boolean;
  index: number;
}

export interface MdInline {
  text: string;
  bold: boolean;
  italic: boolean;
  code: boolean;
  link: string;
}

function paragraphBlock(text: string): MdBlock {
  return { kind: MdBlockKind.Paragraph, text: text, level: 0, lang: '', ordered: false, index: 0 };
}

function headingLevel(line: string): number {
  let count: number = 0;
  while (count < line.length && line.charAt(count) === '#') {
    count++;
  }
  if (count >= 1 && count <= 6 && line.length > count && line.charAt(count) === ' ') {
    return count;
  }
  return 0;
}

function orderedIndex(line: string): number {
  let i: number = 0;
  while (i < line.length && line.charAt(i) >= '0' && line.charAt(i) <= '9') {
    i++;
  }
  if (i > 0 && line.substring(i, i + 2) === '. ') {
    return Number.parseInt(line.substring(0, i), 10);
  }
  return -1;
}

export function parseMarkdown(source: string): MdBlock[] {
  const blocks: MdBlock[] = [];
  const lines: string[] = source.split('\n');
  let paragraph: string[] = [];
  let inCode: boolean = false;
  let codeLang: string = '';
  let codeLines: string[] = [];

  const flushParagraph = (): void => {
    if (paragraph.length > 0) {
      blocks.push(paragraphBlock(paragraph.join('\n')));
      paragraph = [];
    }
  };
  const flushCode = (): void => {
    blocks.push({
      kind: MdBlockKind.Code,
      text: codeLines.join('\n'),
      level: 0,
      lang: codeLang,
      ordered: false,
      index: 0
    });
    codeLines = [];
    codeLang = '';
  };

  for (let i = 0; i < lines.length; i++) {
    const line: string = lines[i];
    const trimmed: string = line.trim();

    if (inCode) {
      if (trimmed.startsWith('```')) {
        flushCode();
        inCode = false;
      } else {
        codeLines.push(line);
      }
      continue;
    }

    if (trimmed.startsWith('```')) {
      flushParagraph();
      inCode = true;
      codeLang = trimmed.substring(3).trim();
      continue;
    }

    if (trimmed.length === 0) {
      flushParagraph();
      continue;
    }

    if (trimmed === '---' || trimmed === '***' || trimmed === '___') {
      flushParagraph();
      blocks.push({ kind: MdBlockKind.Divider, text: '', level: 0, lang: '', ordered: false, index: 0 });
      continue;
    }

    const level: number = headingLevel(trimmed);
    if (level > 0) {
      flushParagraph();
      blocks.push({
        kind: MdBlockKind.Heading,
        text: trimmed.substring(level + 1).trim(),
        level: level,
        lang: '',
        ordered: false,
        index: 0
      });
      continue;
    }

    if (trimmed.startsWith('> ')) {
      flushParagraph();
      blocks.push({
        kind: MdBlockKind.Quote,
        text: trimmed.substring(2).trim(),
        level: 0,
        lang: '',
        ordered: false,
        index: 0
      });
      continue;
    }

    const ordered: number = orderedIndex(trimmed);
    if (ordered > 0) {
      flushParagraph();
      blocks.push({
        kind: MdBlockKind.ListItem,
        text: trimmed.substring(trimmed.indexOf('. ') + 2).trim(),
        level: 0,
        lang: '',
        ordered: true,
        index: ordered
      });
      continue;
    }

    if (trimmed.startsWith('- ') || trimmed.startsWith('* ') || trimmed.startsWith('+ ')) {
      flushParagraph();
      blocks.push({
        kind: MdBlockKind.ListItem,
        text: trimmed.substring(2).trim(),
        level: 0,
        lang: '',
        ordered: false,
        index: 0
      });
      continue;
    }

    paragraph.push(line);
  }

  if (inCode) {
    flushCode();
  }
  flushParagraph();
  return blocks;
}

export function parseInline(input: string): MdInline[] {
  const output: MdInline[] = [];
  let plain: string = '';
  let i: number = 0;

  const flushPlain = (): void => {
    if (plain.length > 0) {
      output.push({ text: plain, bold: false, italic: false, code: false, link: '' });
      plain = '';
    }
  };

  while (i < input.length) {
    const ch: string = input.charAt(i);

    if (ch === '`') {
      const end: number = input.indexOf('`', i + 1);
      if (end > i + 1) {
        flushPlain();
        output.push({
          text: input.substring(i + 1, end),
          bold: false,
          italic: false,
          code: true,
          link: ''
        });
        i = end + 1;
        continue;
      }
    }

    if (input.substring(i, i + 2) === '**') {
      const end: number = input.indexOf('**', i + 2);
      if (end > i + 2) {
        flushPlain();
        output.push({
          text: input.substring(i + 2, end),
          bold: true,
          italic: false,
          code: false,
          link: ''
        });
        i = end + 2;
        continue;
      }
    }

    if (ch === '*') {
      const end: number = input.indexOf('*', i + 1);
      if (end > i + 1) {
        flushPlain();
        output.push({
          text: input.substring(i + 1, end),
          bold: false,
          italic: true,
          code: false,
          link: ''
        });
        i = end + 1;
        continue;
      }
    }

    if (ch === '[') {
      const close: number = input.indexOf(']', i + 1);
      if (close > i + 1 && input.substring(close, close + 2) === '](') {
        const end: number = input.indexOf(')', close + 2);
        if (end > close + 2) {
          flushPlain();
          output.push({
            text: input.substring(i + 1, close),
            bold: false,
            italic: false,
            code: false,
            link: input.substring(close + 2, end)
          });
          i = end + 1;
          continue;
        }
      }
    }

    plain += ch;
    i++;
  }

  flushPlain();
  return output;
}
