/**
 * Small, dependency-free Markdown parser aimed at chat answers:
 * fenced code, headings, lists, quotes, rules, paragraphs and inline
 * bold / italic / code / links. It intentionally does not try to be a full
 * CommonMark implementation.
 */

import { GroupResult, inlineMathSpan, latexToText } from './Latex';

export enum MdBlockKind {
  Paragraph = 'paragraph',
  Heading = 'heading',
  Code = 'code',
  ListItem = 'list',
  Quote = 'quote',
  Divider = 'divider',
  Table = 'table',
  Math = 'math',
  Image = 'image'
}

export interface MdBlock {
  kind: MdBlockKind;
  text: string;
  level: number;
  lang: string;
  ordered: boolean;
  index: number;
  /** Present for `Table` blocks: first row is the header. */
  rows?: string[][];
  /** Present for `Math` blocks: the original LaTeX, for KaTeX rendering. */
  raw?: string;
  /** Present for `Image` blocks: the link target (http(s), minis://, or a
   * workspace-relative path). */
  imageUrl?: string;
  /** Present for `Image` blocks: the alt text, used when the image fails. */
  imageAlt?: string;
}

export interface MdInline {
  text: string;
  bold: boolean;
  italic: boolean;
  code: boolean;
  link: string;
}

/**
 * A whole line holding one image: `![alt](url)` with an optional quoted title.
 * Images inside prose are left as text; chat answers overwhelmingly put them
 * on their own line.
 */
const IMAGE_LINE: RegExp = /^!\[([^\]]*)\]\(\s*([^\s)]+)(?:\s+"[^"]*")?\s*\)$/;

function paragraphBlock(text: string): MdBlock {
  return { kind: MdBlockKind.Paragraph, text: text, level: 0, lang: '', ordered: false, index: 0 };
}

function mathBlock(source: string): MdBlock {
  return {
    kind: MdBlockKind.Math,
    text: latexToText(source),
    level: 0,
    lang: '',
    ordered: false,
    index: 0,
    raw: source.trim()
  };
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

function tableCells(line: string): string[] | null {
  const trimmed: string = line.trim();
  if (trimmed.indexOf('|') < 0) {
    return null;
  }
  let body: string = trimmed;
  if (body.startsWith('|')) {
    body = body.substring(1);
  }
  if (body.endsWith('|')) {
    body = body.substring(0, body.length - 1);
  }
  const raw: string[] = body.split('|');
  const cells: string[] = [];
  for (let i = 0; i < raw.length; i++) {
    cells.push(raw[i].trim());
  }
  return cells;
}

function isTableSeparator(line: string): boolean {
  const trimmed: string = line.trim();
  if (trimmed.indexOf('|') < 0 || trimmed.indexOf('-') < 0) {
    return false;
  }
  for (let i = 0; i < trimmed.length; i++) {
    const ch: string = trimmed.charAt(i);
    if (ch !== '|' && ch !== '-' && ch !== ':' && ch !== ' ') {
      return false;
    }
  }
  return true;
}

function fitCells(cells: string[], columns: number): string[] {
  const fitted: string[] = [];
  for (let i = 0; i < columns; i++) {
    fitted.push(i < cells.length ? cells[i] : '');
  }
  return fitted;
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

    // Standalone image line: ![alt](url).
    const imageMatch: RegExpMatchArray | null = trimmed.match(IMAGE_LINE);
    if (imageMatch !== null) {
      flushParagraph();
      blocks.push({
        kind: MdBlockKind.Image,
        text: imageMatch[1],
        level: 0,
        lang: '',
        ordered: false,
        index: 0,
        imageUrl: imageMatch[2],
        imageAlt: imageMatch[1]
      });
      continue;
    }

    // Display math: `$$...$$` on one line or fenced across several lines.
    if (trimmed.startsWith('$$')) {
      flushParagraph();
      if (trimmed.length > 4 && trimmed.endsWith('$$')) {
        blocks.push(mathBlock(trimmed.substring(2, trimmed.length - 2)));
      } else {
        let body: string = trimmed.substring(2);
        let j: number = i + 1;
        let closed: boolean = false;
        while (j < lines.length) {
          const closeLine: string = lines[j].trim();
          const closeAt: number = closeLine.indexOf('$$');
          if (closeAt >= 0) {
            if (closeAt > 0) {
              body += '\n' + closeLine.substring(0, closeAt);
            }
            closed = true;
            break;
          }
          body += '\n' + lines[j];
          j++;
        }
        if (closed) {
          i = j;
        } else {
          i = lines.length;
        }
        blocks.push(mathBlock(body));
      }
      continue;
    }

    // GFM-style table: a pipe row followed by a `|---|:--:|` separator.
    if (trimmed.indexOf('|') >= 0 && i + 1 < lines.length &&
      isTableSeparator(lines[i + 1])) {
      const header: string[] | null = tableCells(trimmed);
      if (header !== null && header.length > 0) {
        flushParagraph();
        const rows: string[][] = [header];
        let j: number = i + 2;
        while (j < lines.length) {
          const rowLine: string = lines[j].trim();
          if (rowLine.length === 0) {
            break;
          }
          const cells: string[] | null = tableCells(rowLine);
          if (cells === null) {
            break;
          }
          rows.push(fitCells(cells, header.length));
          j++;
        }
        blocks.push({
          kind: MdBlockKind.Table,
          text: '',
          level: 0,
          lang: '',
          ordered: false,
          index: 0,
          rows: rows
        });
        i = j - 1;
        continue;
      }
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

/** Schemes the app is willing to hand to another ability. */
export function isOpenableUrl(url: string): boolean {
  const lower: string = url.trim().toLowerCase();
  return lower.startsWith('http://') || lower.startsWith('https://') ||
    lower.startsWith('mailto:') || lower.startsWith('tel:');
}

function isUrlTerminator(ch: string): boolean {
  return ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r' ||
    ch === '<' || ch === '>' || ch === '"' || ch === '）' || ch === '】' ||
    ch === '」' || ch === '》' || ch === '，' || ch === '。' || ch === '；' ||
    ch === '：' || ch === '！' || ch === '？' || ch === '、' || ch === '“' ||
    ch === '”' || ch === '‘' || ch === '’';
}

function trimUrlTail(url: string): string {
  let end: number = url.length;
  while (end > 0) {
    const ch: string = url.charAt(end - 1);
    if (ch === '.' || ch === ',' || ch === ';' || ch === ':' || ch === '!' ||
      ch === '?') {
      end--;
    } else {
      break;
    }
  }
  return url.substring(0, end);
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

    if (ch === '$') {
      const span: GroupResult | null = inlineMathSpan(input, i);
      if (span !== null) {
        flushPlain();
        output.push({
          text: latexToText(span.text),
          bold: false,
          italic: false,
          code: false,
          link: ''
        });
        i = span.next;
        continue;
      }
    }

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

    // Bare URLs inside prose. Markdown links are handled below; trailing
    // sentence punctuation is left in the paragraph so `见 https://a.b。`
    // keeps its full stop (and does not become part of the target).
    if (input.substring(i, i + 7) === 'http://' ||
      input.substring(i, i + 8) === 'https://') {
      let end: number = i;
      while (end < input.length && !isUrlTerminator(input.charAt(end))) {
        end++;
      }
      const raw: string = trimUrlTail(input.substring(i, end));
      if (raw.length > 8 && isOpenableUrl(raw)) {
        flushPlain();
        output.push({ text: raw, bold: false, italic: false, code: false, link: raw });
        i += raw.length;
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
