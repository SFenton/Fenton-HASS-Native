#!/usr/bin/env python3
"""Inline the mockup kit into one self-contained HTML file (stdout).

    python3 tools/mockups_inline.py .agents/design/mockups/pages/home/home/home.html > /tmp/home-export.html

Replaces the page's <link rel=stylesheet href=".../_kit/kit.css"> with a <style> block and its <script src=".../_kit/kit.js"> with one <script>
holding kit.js, lib/*.js and components/*.js (in the order kit.js declares), after setting window.__MOCK_INLINED so kit.js skips its loader.
The result opens offline from anywhere: the propose-first export format (.agents/workflow/propose-first.md). Stdlib only.
"""
import re
import sys
from pathlib import Path

LINK = re.compile(r'<link[^>]*href="([^"]*_kit/kit\.css)"[^>]*>', re.I)
SCRIPT = re.compile(r'<script[^>]*src="([^"]*_kit/kit\.js)"[^>]*>\s*</script>', re.I)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def js_list(kit_js: str, name: str) -> list:
    match = re.search(r"Mock\." + name + r"\s*=\s*\[(.*?)\];", kit_js, re.S)
    if not match:
        sys.exit(f"mockups_inline: Mock.{name} not found in kit.js")
    return re.findall(r"'([^']+)'", match.group(1))


def safe(code: str) -> str:
    """A literal </script inside inlined code would end the tag early."""
    return re.sub(r"</(script)", r"<\\/\1", code, flags=re.I)


def inline(page: Path) -> str:
    html = read(page)
    css_match, js_match = LINK.search(html), SCRIPT.search(html)
    if not css_match or not js_match:
        sys.exit("mockups_inline: the page does not link _kit/kit.css and _kit/kit.js")
    kit = (page.parent / js_match.group(1)).resolve().parent
    kit_js = read(kit / "kit.js")
    parts = [kit_js]
    parts += [read(kit / "lib" / f"{n}.js") for n in js_list(kit_js, "LIB")]
    parts += [read(kit / "components" / f"{n}.js") for n in js_list(kit_js, "COMPONENTS")]
    bundle = "window.__MOCK_INLINED = true;\n" + "\n".join(parts)
    html = LINK.sub(lambda _: "<style>\n" + read(kit / "kit.css") + "\n</style>", html, count=1)
    return SCRIPT.sub(lambda _: "<script>\n" + safe(bundle) + "\n</script>", html, count=1)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.stdout.write(inline(Path(sys.argv[1]).resolve()))
