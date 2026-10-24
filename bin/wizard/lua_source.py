"""Small, non-executing Lua source scanner shared by wizard documentation/audits.

This is deliberately not a Lua interpreter. Balanced calls, tables and blocks are
understood; runtime branches are retained as alternatives. Strings and comments
cannot manufacture calls. Source offsets remain available for diagnostics.
"""
from dataclasses import dataclass
import json
from pathlib import Path
import re


TOKEN = re.compile(r'''--\[(=*)\[.*?\]\1\]|--[^\n]*|\[(=*)\[.*?\]\2\]|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[A-Za-z_]\w*|\d+(?:\.\d+)?|\.\.|==|~=|<=|>=|<<|>>|\S''', re.S)


@dataclass(frozen=True)
class Token:
    value: str
    offset: int = 0
    line: int = 0


def tokens(source):
    result, line, previous = [], 1, 0
    for match in TOKEN.finditer(source):
        line += source.count('\n', previous, match.start())
        if not match[0].startswith('--'):
            result.append(Token(match[0], match.start(), line))
        previous = match.start()
    return result


def literal(ts):
    if len(ts) != 1:
        return None
    value = ts[0].value
    if value[:1] in ('"', "'"):
        # Lua's common string escapes, without Python's unicode_escape mojibake.
        return re.sub(r'\\(\d{1,3}|.)', lambda m: chr(int(m[1])) if m[1].isdigit()
                      else {'n': '\n', 'r': '\r', 't': '\t', 'a': '\a', 'b': '\b',
                            'f': '\f', 'v': '\v'}.get(m[1], m[1]), value[1:-1])
    return None


def expression(ts):
    return ' '.join(t.value for t in ts)


class Lua:
    def __init__(self, source):
        self.tokens = tokens(source) if isinstance(source, str) else list(source)
        self.pairs = {}
        groups, blocks = [], []
        for i, t in enumerate(self.tokens):
            v = t.value
            if v in ('(', '[', '{'):
                groups.append(i)
            elif v in (')', ']', '}'):
                assert groups, f'Unmatched {v} at line {t.line}'
                start = groups.pop()
                assert self.tokens[start].value == {')': '(', ']': '[', '}': '{'}[v]
                self.pairs[start] = i
            elif v in ('function', 'if', 'for', 'while', 'repeat'):
                blocks.append([i, v, v in ('for', 'while')])
            elif v == 'do':
                if blocks and blocks[-1][2]:
                    blocks[-1][2] = False
                else:
                    blocks.append([i, v, False])
            elif v in ('end', 'until'):
                assert blocks, f'Unmatched {v} at line {t.line}'
                start, _, _ = blocks.pop()
                self.pairs[start] = i
        assert not groups and not blocks, 'Unclosed Lua group/block'

    def split(self, start, end, separator=','):
        parts, begin, i = [], start, start
        while i < end:
            if self.tokens[i].value == separator:
                parts.append(self.tokens[begin:i]); begin = i + 1
            i = self.pairs.get(i, i) + 1
        if begin < end:
            parts.append(self.tokens[begin:end])
        return parts

    def calls(self, methods=None):
        ts = self.tokens
        for i in range(len(ts) - 3):
            if ts[i].value not in ('w', 'self') or ts[i+1].value != ':' or ts[i+3].value != '(':
                continue
            if i and ts[i-1].value == 'function':
                continue
            name = ts[i+2].value
            if methods is None or name in methods:
                end = self.pairs[i+3]
                yield i, end+1, name, self.split(i+4, end)

    def fields(self, start):
        result = {}
        for part in self.split(start+1, self.pairs[start]):
            if len(part) >= 3 and part[1].value == '=':
                result[part[0].value] = part[2:]
        return result

    def functions(self):
        ts = self.tokens
        for i, t in enumerate(ts):
            if t.value != 'function':
                continue
            j = i+1
            while ts[j].value != '(':
                j += 1
            name = expression(ts[i+1:j]).replace(' ', '')
            params = [expression(p) for p in self.split(j+1, self.pairs[j])]
            yield i, self.pairs[i]+1, name, params, ts[self.pairs[j]+1:self.pairs[i]]


def load_mapping(root=Path('.')):
    return json.loads((root / 'bin/wizard/source-map.json').read_text(encoding='utf-8'))


def i18n_keys(source, prefix):
    return re.findall(r'@i18n\((' + re.escape(prefix) + r'\w+)\)@', source)


def string_calls(source, receiver):
    """First literal arguments, used by the audit's contract inventory."""
    parsed = Lua(source)
    ts = parsed.tokens
    return [literal(parsed.split(i+2, parsed.pairs[i+1])[0])
            for i in range(len(ts)-2)
            if ts[i].value == receiver and ts[i+1].value == '('
            and (i == 0 or ts[i-1].value != 'function')
            and parsed.split(i+2, parsed.pairs[i+1])]
