/**
 * Lightweight LaTeX-to-Unicode conversion for chat answers.
 *
 * This is deliberately not a typesetting engine: there is no font metrics,
 * line breaking or real superscript layout. Common inline formulas become
 * readable Unicode text (fractions, roots, Greek letters, operators and
 * sub/superscripts); unknown commands are dropped rather than rendered raw.
 * Display math keeps its own block so it can be shown in a monospace card.
 */

export interface GroupResult {
  text: string;
  next: number;
}

const SUPER_SOURCE: string = '0123456789+-=()ni';
const SUPER_TARGET: string = '⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ⁿⁱ';
const SUB_SOURCE: string = '0123456789+-=()aehijklmnoprstuvx';
const SUB_TARGET: string = '₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓ';

function scripted(value: string, supers: boolean): string {
  const source: string = supers ? SUPER_SOURCE : SUB_SOURCE;
  const target: string = supers ? SUPER_TARGET : SUB_TARGET;
  let out: string = '';
  for (let i = 0; i < value.length; i++) {
    const at: number = source.indexOf(value.charAt(i));
    if (at < 0) {
      return (supers ? '^(' : '_(') + value + ')';
    }
    // Superscript and subscript targets are both one UTF-16 code unit here.
    out += target.substring(at, at + 1);
  }
  return out;
}

/** Read a balanced `{...}` group starting at `start` (which must be `{`). */
function readGroup(source: string, start: number): GroupResult {
  if (source.charAt(start) !== '{') {
    return { text: '', next: start };
  }
  let depth: number = 0;
  let i: number = start;
  while (i < source.length) {
    const ch: string = source.charAt(i);
    if (ch === '\\') {
      i += 2;
      continue;
    }
    if (ch === '{') {
      depth++;
    } else if (ch === '}') {
      depth--;
      if (depth === 0) {
        return { text: source.substring(start + 1, i), next: i + 1 };
      }
    }
    i++;
  }
  return { text: source.substring(start + 1), next: source.length };
}

/** A single character or a braced group, used after ^ _ and by \frac. */
function readAtom(source: string, start: number): GroupResult {
  if (start >= source.length) {
    return { text: '', next: start };
  }
  if (source.charAt(start) === '{') {
    return readGroup(source, start);
  }
  if (source.charAt(start) === '\\') {
    // Keep a command intact, e.g. \frac without braces (rare but harmless).
    let end: number = start + 1;
    while (end < source.length) {
      const ch: string = source.charAt(end);
      const lower: string = ch.toLowerCase();
      if (lower < 'a' || lower > 'z') {
        break;
      }
      end++;
    }
    return { text: source.substring(start, end), next: end };
  }
  return { text: source.charAt(start), next: start + 1 };
}

function wrap(part: string): string {
  if (part.length === 0) {
    return part;
  }
  if (part.indexOf(' ') >= 0 || part.indexOf('+') >= 0 ||
    part.indexOf('-') >= 0 || part.indexOf('=') >= 0 ||
    part.indexOf('×') >= 0 || part.indexOf('·') >= 0) {
    return '(' + part + ')';
  }
  return part;
}

function commandSymbol(name: string): string {
  if (name === 'alpha') {
    return 'α';
  }
  if (name === 'beta') {
    return 'β';
  }
  if (name === 'gamma') {
    return 'γ';
  }
  if (name === 'Gamma') {
    return 'Γ';
  }
  if (name === 'delta') {
    return 'δ';
  }
  if (name === 'Delta') {
    return 'Δ';
  }
  if (name === 'epsilon' || name === 'varepsilon') {
    return 'ε';
  }
  if (name === 'zeta') {
    return 'ζ';
  }
  if (name === 'eta') {
    return 'η';
  }
  if (name === 'theta') {
    return 'θ';
  }
  if (name === 'Theta') {
    return 'Θ';
  }
  if (name === 'iota') {
    return 'ι';
  }
  if (name === 'kappa') {
    return 'κ';
  }
  if (name === 'lambda') {
    return 'λ';
  }
  if (name === 'Lambda') {
    return 'Λ';
  }
  if (name === 'mu') {
    return 'μ';
  }
  if (name === 'nu') {
    return 'ν';
  }
  if (name === 'xi') {
    return 'ξ';
  }
  if (name === 'pi') {
    return 'π';
  }
  if (name === 'Pi') {
    return 'Π';
  }
  if (name === 'rho') {
    return 'ρ';
  }
  if (name === 'sigma') {
    return 'σ';
  }
  if (name === 'Sigma' || name === 'sum') {
    return 'Σ';
  }
  if (name === 'tau') {
    return 'τ';
  }
  if (name === 'upsilon') {
    return 'υ';
  }
  if (name === 'phi' || name === 'varphi') {
    return 'φ';
  }
  if (name === 'Phi') {
    return 'Φ';
  }
  if (name === 'chi') {
    return 'χ';
  }
  if (name === 'psi') {
    return 'ψ';
  }
  if (name === 'Psi') {
    return 'Ψ';
  }
  if (name === 'omega') {
    return 'ω';
  }
  if (name === 'Omega') {
    return 'Ω';
  }
  if (name === 'times') {
    return '×';
  }
  if (name === 'cdot') {
    return '·';
  }
  if (name === 'div') {
    return '÷';
  }
  if (name === 'pm') {
    return '±';
  }
  if (name === 'mp') {
    return '∓';
  }
  if (name === 'le' || name === 'leq') {
    return '≤';
  }
  if (name === 'ge' || name === 'geq') {
    return '≥';
  }
  if (name === 'ne' || name === 'neq') {
    return '≠';
  }
  if (name === 'approx') {
    return '≈';
  }
  if (name === 'equiv') {
    return '≡';
  }
  if (name === 'infty') {
    return '∞';
  }
  if (name === 'partial') {
    return '∂';
  }
  if (name === 'nabla') {
    return '∇';
  }
  if (name === 'int') {
    return '∫';
  }
  if (name === 'prod') {
    return 'Π';
  }
  if (name === 'rightarrow' || name === 'to') {
    return '→';
  }
  if (name === 'leftarrow') {
    return '←';
  }
  if (name === 'Rightarrow') {
    return '⇒';
  }
  if (name === 'Leftarrow') {
    return '⇐';
  }
  if (name === 'leftrightarrow') {
    return '↔';
  }
  if (name === 'in') {
    return '∈';
  }
  if (name === 'notin') {
    return '∉';
  }
  if (name === 'subset') {
    return '⊂';
  }
  if (name === 'subseteq') {
    return '⊆';
  }
  if (name === 'cup') {
    return '∪';
  }
  if (name === 'cap') {
    return '∩';
  }
  if (name === 'forall') {
    return '∀';
  }
  if (name === 'exists') {
    return '∃';
  }
  if (name === 'emptyset') {
    return '∅';
  }
  if (name === 'angle') {
    return '∠';
  }
  if (name === 'degree') {
    return '°';
  }
  if (name === 'sin' || name === 'cos' || name === 'tan' ||
    name === 'log' || name === 'ln' || name === 'exp' ||
    name === 'lim' || name === 'max' || name === 'min' ||
    name === 'det' || name === 'gcd') {
    return name;
  }
  return '';
}

function renderMath(source: string): string {
  let out: string = '';
  let i: number = 0;
  while (i < source.length) {
    const ch: string = source.charAt(i);
    if (ch === '\\') {
      let end: number = i + 1;
      while (end < source.length) {
        const next: string = source.charAt(end);
        const lower: string = next.toLowerCase();
        if (lower < 'a' || lower > 'z') {
          break;
        }
        end++;
      }
      const name: string = source.substring(i + 1, end);
      if (name.length === 0) {
        const escaped: string = end < source.length ? source.charAt(end) : '';
        if (escaped === '\\') {
          out += '\n';
          i = end + 1;
        } else if (escaped === ',' || escaped === ';' || escaped === ':' ||
          escaped === ' ') {
          out += ' ';
          i = end + 1;
        } else if (escaped === '{' || escaped === '}' || escaped === '_' ||
          escaped === '&' || escaped === '%' || escaped === '#') {
          out += escaped;
          i = end + 1;
        } else {
          i = end;
        }
        continue;
      }
      if (name === 'frac' || name === 'dfrac' || name === 'tfrac') {
        const numerator: GroupResult = readAtom(source, end);
        const denominator: GroupResult = readAtom(source, numerator.next);
        out += wrap(renderMath(numerator.text)) + '/' + wrap(renderMath(denominator.text));
        i = denominator.next;
        continue;
      }
      if (name === 'sqrt') {
        let root: string = '';
        let next: number = end;
        if (source.charAt(next) === '[') {
          const close: number = source.indexOf(']', next + 1);
          if (close > next) {
            root = renderMath(source.substring(next + 1, close));
            next = close + 1;
          }
        }
        const atom: GroupResult = readAtom(source, next);
        out += (root.length > 0 ? scripted(root, true) : '') +
          '√(' + renderMath(atom.text) + ')';
        i = atom.next;
        continue;
      }
      if (name === 'text' || name === 'mathrm' || name === 'operatorname' ||
        name === 'textbf' || name === 'textit') {
        const group: GroupResult = readAtom(source, end);
        out += group.text;
        i = group.next;
        continue;
      }
      if (name === 'left' || name === 'right') {
        let next: number = end;
        if (source.charAt(next) === '\\') {
          next++;
        }
        if (next < source.length) {
          const delimiter: string = source.charAt(next);
          if (delimiter !== '.' && delimiter !== '\\') {
            out += delimiter;
          }
          next++;
        }
        i = next;
        continue;
      }
      if (name === 'begin' || name === 'end') {
        const group: GroupResult = readGroup(source, end);
        const env: string = group.text.trim();
        if (name === 'begin' && (env === 'matrix' || env === 'pmatrix' ||
          env === 'bmatrix' || env === 'cases' || env === 'aligned')) {
          out += '\n';
        }
        i = group.next;
        continue;
      }
      if (name === 'quad' || name === 'qquad') {
        out += '  ';
        i = end;
        continue;
      }
      if (name === 'limits' || name === 'displaystyle' || name === 'nolimits') {
        i = end;
        continue;
      }
      out += commandSymbol(name);
      i = end;
      continue;
    }
    if (ch === '{') {
      const group: GroupResult = readGroup(source, i);
      out += renderMath(group.text);
      i = group.next;
      continue;
    }
    if (ch === '}') {
      i++;
      continue;
    }
    if (ch === '^' || ch === '_') {
      const atom: GroupResult = readAtom(source, i + 1);
      const value: string = renderMath(atom.text);
      out += scripted(value, ch === '^');
      i = atom.next;
      continue;
    }
    if (ch === '&') {
      out += '  ';
      i++;
      continue;
    }
    out += ch;
    i++;
  }
  return out;
}

/** Convert a formula's inner text (without surrounding `$`) to Unicode. */
export function latexToText(source: string): string {
  const trimmed: string = source.trim();
  if (trimmed.length === 0) {
    return '';
  }
  return renderMath(trimmed).trim();
}

/**
 * Inline math heuristic. `$` must be followed by a non-space and the closing
 * `$` must be preceded by a non-space; a leading digit is treated as currency
 * (`$5`), so plain money never becomes math.
 */
export function inlineMathSpan(source: string, start: number): GroupResult | null {
  if (source.charAt(start) !== '$' || source.charAt(start + 1) === '$') {
    return null;
  }
  const first: string = source.charAt(start + 1);
  if (first.length === 0 || first === ' ' || first === '\n' ||
    (first >= '0' && first <= '9')) {
    return null;
  }
  let i: number = start + 2;
  while (i < source.length) {
    const ch: string = source.charAt(i);
    if (ch === '\n') {
      return null;
    }
    if (ch === '$') {
      const previous: string = source.charAt(i - 1);
      if (previous === ' ' || i === start + 1) {
        return null;
      }
      return { text: source.substring(start + 1, i), next: i + 1 };
    }
    i++;
  }
  return null;
}
