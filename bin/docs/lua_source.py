"""A small, non-executing reader for Lua source, shared by the documentation generators.

This is deliberately not a Lua interpreter. Balanced calls, tables and blocks are
understood; nothing is evaluated, and runtime branches are not followed. Strings and
comments cannot manufacture a token. Source offsets and line numbers stay available, so
a generator can name the line it could not read.

A generator in another directory loads this file by its path, the way
`bin/i18n/check_translations.py` loads the i18n precompiler:

    spec = importlib.util.spec_from_file_location("lua_source", ROOT / "bin/docs/lua_source.py")

A source the reader cannot balance raises `LuaSourceError` rather than an `assert`, so the
failure survives `python -O` and a malformed file is never read as an empty one.
"""
from dataclasses import dataclass
import re


TOKEN = re.compile(r'''--\[(=*)\[.*?\]\1\]|--[^\n]*|\[(=*)\[.*?\]\2\]|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[A-Za-z_]\w*|\d+(?:\.\d+)?|\.\.|==|~=|<=|>=|<<|>>|\S''', re.S)

CLOSERS = {')': '(', ']': '[', '}': '{'}


class LuaSourceError(ValueError):
    """The source does not balance, so nothing read from it can be trusted."""


@dataclass(frozen=True)
class Token:
    value: str
    offset: int = 0
    line: int = 0


def tokens(source):
    """The source's tokens, comments dropped, each with its offset and line."""
    result, line, previous = [], 1, 0
    for match in TOKEN.finditer(source):
        line += source.count('\n', previous, match.start())
        if not match[0].startswith('--'):
            result.append(Token(match[0], match.start(), line))
        previous = match.start()
    return result


def literal(ts):
    """The value of a single quoted-string token, or None for anything else."""
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
    """The tokens as source text, one space between each."""
    return ' '.join(t.value for t in ts)


class Lua:
    """A token list with every bracket and block paired to its end.

    `pairs[i]` is the index of the token that closes the bracket, `function`, `if`,
    `for`, `while`, `repeat` or `do` at index `i`.
    """

    def __init__(self, source):
        self.tokens = tokens(source) if isinstance(source, str) else list(source)
        self.pairs = {}
        groups, blocks = [], []
        for i, t in enumerate(self.tokens):
            v = t.value
            if v in ('(', '[', '{'):
                groups.append(i)
            elif v in CLOSERS:
                if not groups:
                    raise LuaSourceError(f'unmatched {v} at line {t.line}')
                start = groups.pop()
                if self.tokens[start].value != CLOSERS[v]:
                    raise LuaSourceError(
                        f'{v} at line {t.line} closes {self.tokens[start].value} '
                        f'from line {self.tokens[start].line}')
                self.pairs[start] = i
            elif v in ('function', 'if', 'for', 'while', 'repeat'):
                blocks.append([i, v, v in ('for', 'while')])
            elif v == 'do':
                if blocks and blocks[-1][2]:
                    blocks[-1][2] = False
                else:
                    blocks.append([i, v, False])
            elif v in ('end', 'until'):
                if not blocks:
                    raise LuaSourceError(f'unmatched {v} at line {t.line}')
                start, _, _ = blocks.pop()
                self.pairs[start] = i
        if groups or blocks:
            first = self.tokens[(groups or [blocks[0][0]])[0]]
            raise LuaSourceError(f'{first.value} at line {first.line} is never closed')

    def split(self, start, end, separator=','):
        """The token runs between `start` and `end`, cut at top-level separators."""
        parts, begin, i = [], start, start
        while i < end:
            if self.tokens[i].value == separator:
                parts.append(self.tokens[begin:i])
                begin = i + 1
            i = self.pairs.get(i, i) + 1
        if begin < end:
            parts.append(self.tokens[begin:end])
        return parts

    def calls(self, methods=None):
        """Method calls on `w` or `self`: (start, end, name, [argument tokens])."""
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
        """The `name = value` members of the table constructor opening at `start`."""
        result = {}
        for part in self.split(start+1, self.pairs[start]):
            if len(part) >= 3 and part[1].value == '=':
                result[part[0].value] = part[2:]
        return result

    def functions(self):
        """Every function: (start, end, name, [parameters], body tokens)."""
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
