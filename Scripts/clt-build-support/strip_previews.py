#!/usr/bin/env python3
"""Removes `#Preview { ... }` blocks from Swift sources.

The #Preview macro's implementation lives in the PreviewsMacros compiler
plugin, which ships with Xcode but not with the Command Line Tools. This
strips the blocks so CLT-only builds succeed. Previews are irrelevant to
release builds, and files without #Preview pass through unchanged.
"""

import sys
from pathlib import Path


def find_block_end(text: str, start: int) -> int | None:
    """Returns the index just past the closing brace of the block that
    starts at `start`, where `start` is the offset of `#Preview`."""
    depth = 0
    started = False
    i = start
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == '"':
            # skip string literal (ignores escapes like \" for simplicity,
            # which is fine for the simple preview bodies we strip)
            i += 1
            while i < n and text[i] != '"':
                if text[i] == "\\":
                    i += 1
                i += 1
        elif ch == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
        elif ch == "{":
            depth += 1
            started = True
        elif ch == "}":
            depth -= 1
            if started and depth == 0:
                return i + 1
        i += 1
    return None


def strip_previews(text: str) -> str:
    out = []
    pos = 0
    changed = False
    while True:
        idx = text.find("#Preview", pos)
        if idx == -1:
            out.append(text[pos:])
            break
        # only strip when it starts the line (declaration position)
        line_start = text.rfind("\n", 0, idx) + 1
        if text[line_start:idx].strip() != "":
            out.append(text[pos:idx + len("#Preview")])
            pos = idx + len("#Preview")
            continue
        end = find_block_end(text, idx)
        if end is None:
            out.append(text[pos:])
            break
        out.append(text[pos:line_start])
        # drop a trailing blank line left behind
        while end < len(text) and text[end] == "\n":
            end += 1
            if end < len(text) and text[end] != "\n":
                break
        pos = end
        changed = True
    return "".join(out)


def main() -> None:
    for arg in sys.argv[1:]:
        path = Path(arg)
        text = path.read_text()
        stripped = strip_previews(text)
        if stripped != text:
            path.write_text(stripped)
            print(f"stripped previews: {path}")


if __name__ == "__main__":
    main()
