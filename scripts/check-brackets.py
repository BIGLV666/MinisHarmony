#!/usr/bin/env python3
"""Lightweight bracket-balance scanner for ArkTS files.

Not a compiler: it only catches unbalanced {}, () and [] while correctly
ignoring comments and string literals. Useful in environments without the
HarmonyOS SDK.
"""
import glob
import sys


REGEX_PRECEDERS = set('([{=,:;!&|?+-*%<>~^')


def _is_regex_start(source, index):
    """Heuristic: a '/' starts a regex when the previous token cannot end an expression."""
    cursor = index - 1
    while cursor >= 0 and source[cursor] in ' \t\r\n':
        cursor -= 1
    if cursor < 0:
        return True
    return source[cursor] in REGEX_PRECEDERS


def scan(path):
    source = open(path, encoding='utf-8').read()
    index = 0
    length = len(source)
    stack = []
    line = 1
    state = 'normal'
    in_class = False
    while index < length:
        char = source[index]
        nxt = source[index + 1] if index + 1 < length else ''
        if char == '\n':
            line += 1
        if state == 'normal':
            if char == '/' and nxt == '/':
                state = 'line'
                index += 2
                continue
            if char == '/' and nxt == '*':
                state = 'block'
                index += 2
                continue
            if char == '/' and _is_regex_start(source, index):
                state = 'regex'
                in_class = False
                index += 1
                continue
            if char == "'":
                state = 'single'
            elif char == '"':
                state = 'double'
            elif char == '`':
                state = 'template'
            elif char in '{([':
                stack.append((char, line))
            elif char in '})]':
                pair = {'}': '{', ')': '(', ']': '['}[char]
                if not stack or stack[-1][0] != pair:
                    return f'mismatch {char} at line {line}, stack={stack[-3:]}'
                stack.pop()
        elif state == 'regex':
            if char == '\\':
                index += 2
                continue
            if char == '[':
                in_class = True
            elif char == ']':
                in_class = False
            elif char == '/' and not in_class:
                state = 'normal'
        elif state == 'line':
            if char == '\n':
                state = 'normal'
        elif state == 'block':
            if char == '*' and nxt == '/':
                state = 'normal'
                index += 2
                continue
        elif state in ('single', 'double'):
            if char == '\\':
                index += 2
                continue
            if (state == 'single' and char == "'") or (state == 'double' and char == '"'):
                state = 'normal'
        elif state == 'template':
            if char == '\\':
                index += 2
                continue
            if char == '`':
                state = 'normal'
        index += 1
    if stack:
        return f'unclosed {stack[-5:]}'
    if state not in ('normal', 'line'):
        return f'ended in string/comment state {state}'
    return 'ok'


def main():
    failed = 0
    for path in sorted(glob.glob('entry/src/main/ets/**/*.ets', recursive=True)):
        result = scan(path)
        if result != 'ok':
            failed += 1
            print(f'FAIL {path}: {result}')
    if failed:
        print(f'{failed} file(s) failed')
        return 1
    print('all ArkTS files bracket-balanced')
    return 0


if __name__ == '__main__':
    sys.exit(main())
