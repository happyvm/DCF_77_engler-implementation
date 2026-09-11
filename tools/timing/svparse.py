"""Lightweight SystemVerilog ANSI port-list parser.

The blocks in this repository use a consistent ANSI style::

    module foo #(
        parameter int W = 8
    ) (
        input  logic clk,
        input  logic [W-1:0] data,
        output logic signed [2*W:0] result
    );

``parse_module_ports`` extracts direction, packed-dimension text and name for
every port.  The packed dimension is kept **verbatim** (e.g. ``[SAMPLE_BITS-1:0]``
or ``[(2*STATE_BITS)+2:0]``) so the timing-wrapper generator can re-emit it
without evaluating any parameter expression.  Ports are never re-ordered and
the parser does not modify the DUT.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

_DIRECTIONS = ("input", "output", "inout")
_QUALIFIERS = {
    "wire", "reg", "logic", "bit", "signed", "unsigned", "var", "tri",
    "tri0", "tri1", "wand", "wor", "integer", "byte", "shortint", "longint",
}


@dataclass(frozen=True)
class Port:
    name: str
    direction: str          # "input" | "output" | "inout"
    dim: str                # verbatim packed dimension text, "" when 1-bit
    raw: str
    signed: bool = False

    @property
    def decl(self) -> str:
        sign = "signed " if self.signed else ""
        return f"{sign}{self.dim} {self.name}".strip()


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    return text


def preprocess(text: str, defines: tuple[str, ...] = ()) -> str:
    """Evaluate ``ifdef``/``ifndef``/``else``/``endif`` for port extraction.

    Only the parser uses this; Yosys still reads the original files (it has its
    own preprocessor).  With the default ``defines=()`` the ``ifdef FORMAL``
    observation ports added by ``pm_minute_sync`` / ``minute_candidate_search``
    are dropped, exactly as Yosys does when ``FORMAL`` is undefined.
    """
    defs = set(defines)
    out: list[str] = []
    stack: list[list[bool]] = []  # [active, taken]

    def active() -> bool:
        return all(f[0] for f in stack)

    for line in text.splitlines():
        s = line.strip()
        m = re.match(r"`(\w+)\s*(.*)$", s)
        if m:
            d, arg = m.group(1), m.group(2).strip()
            if d in ("ifdef", "ifndef"):
                val = active() and (arg in defs if d == "ifdef" else arg not in defs)
                stack.append([val, val])
                continue
            if d in ("elsif", "else"):
                if stack:
                    parent = all(f[0] for f in stack[:-1])
                    taken = stack[-1][1]
                    val = parent and not taken and (arg in defs if d == "elsif" else True)
                    stack[-1] = [val, taken or val]
                continue
            if d == "endif":
                if stack:
                    stack.pop()
                continue
            if d in ("define", "undef", "include", "line"):
                continue
            if active():
                out.append(line)
            continue
        if active():
            out.append(line)
    return "\n".join(out)


def _find_balanced(text: str, start: int, open_ch: str = "(", close_ch: str = ")") -> int:
    depth = 0
    i = start
    while i < len(text):
        c = text[i]
        if c == open_ch:
            depth += 1
        elif c == close_ch:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError("unbalanced parentheses in port/parameter list")


def _skip_ws(text: str, i: int) -> int:
    while i < len(text) and text[i].isspace():
        i += 1
    return i


def _split_top_level(s: str) -> list[str]:
    out: list[str] = []
    depth = 0
    cur: list[str] = []
    for c in s:
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        if c == "," and depth == 0:
            out.append("".join(cur))
            cur = []
        else:
            cur.append(c)
    tail = "".join(cur)
    if tail.strip():
        out.append(tail)
    return out


def _parse_port(entry: str) -> Port:
    tokens = entry.split()
    direction = None
    signed = False
    rest: list[str] = []
    for tok in tokens:
        low = tok.lower()
        if low in _DIRECTIONS and direction is None:
            direction = low
        elif low == "signed":
            signed = True
        elif low in _QUALIFIERS:
            continue
        else:
            rest.append(tok)
    if direction is None:
        raise ValueError(f"port entry has no direction keyword: {entry!r}")
    if not rest:
        raise ValueError(f"port entry has no name: {entry!r}")
    name = rest[-1]
    dim = " ".join(rest[:-1]).strip()
    return Port(name=name, direction=direction, dim=dim, raw=entry.strip(), signed=signed)


def parse_module_ports(text: str, module: str) -> list[Port]:
    t = preprocess(strip_comments(text))
    m = re.search(r"\bmodule\s+" + re.escape(module) + r"\b", t)
    if not m:
        raise ValueError(f"module {module!r} not found in source")
    i = _skip_ws(t, m.end())
    # Optional parameter block:  #( ... )
    if i < len(t) and t[i] == "#":
        i = _skip_ws(t, i + 1)
        if i >= len(t) or t[i] != "(":
            raise ValueError(f"expected '(' after '#' in module {module!r}")
        i = _find_balanced(t, i) + 1
        i = _skip_ws(t, i)
    if i >= len(t) or t[i] != "(":
        return []
    j = _find_balanced(t, i)
    body = t[i + 1:j]
    ports: list[Port] = []
    for entry in _split_top_level(body):
        entry = entry.strip()
        if entry:
            ports.append(_parse_port(entry))
    return ports


def get_parameter_text(text: str, module: str) -> str:
    """Return the verbatim text inside a module's ``#( ... )`` block, or ''.

    Re-emitting the parameter block lets the timing wrapper reuse the DUT's
    parameter names inside its own port dimensions without evaluating them.
    """
    t = preprocess(strip_comments(text))
    m = re.search(r"\bmodule\s+" + re.escape(module) + r"\b", t)
    if not m:
        raise ValueError(f"module {module!r} not found in source")
    i = _skip_ws(t, m.end())
    if i >= len(t) or t[i] != "#":
        return ""
    i = _skip_ws(t, i + 1)
    if i >= len(t) or t[i] != "(":
        raise ValueError(f"expected '(' after '#' in module {module!r}")
    j = _find_balanced(t, i)
    return t[i + 1:j].strip()


def load_module_ports(rtl_path: str, module: str) -> list[Port]:
    with open(rtl_path, "r", encoding="utf-8") as fh:
        return parse_module_ports(fh.read(), module)
