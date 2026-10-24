#!/usr/bin/env python3
"""Check the mockup atlas: folders, READMEs, catalog.json and each mockup's config (static).

    python3 tools/mockups_check.py          # exit 1 on any problem

Checks: every mockup folder (pages/<area>/<id>, modals/<area>/<id>, components/<group>/<id>, flows/<id>, proposals/<id>) holds <id>.html and a README.md of
at most 40 lines (proposals excepted: frozen records); a Mock.mount config names source, spec, states, a11y and reviews (the runtime Mock.lint banner checks the rest); _kit/components matches
Mock.COMPONENTS; catalog.json (when present: {items:[{id,path,mockup,sources}]}) lists every mockup on disk (proposals excepted), sets `mockup` once the file exists and names existing sources. Stdlib only.
"""
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ROOT = REPO / ".agents" / "design" / "mockups"
DEPTH = {"pages": 2, "modals": 2, "components": 2, "flows": 1, "proposals": 1}
REQUIRED = ["source", "spec", "states", "a11y", "reviews", "devices"]
problems = []


def bad(msg):
    problems.append(msg)


def mockup_dirs():
    for kind, depth in DEPTH.items():
        base = ROOT / kind
        if not base.is_dir():
            continue
        level = [base]
        for _ in range(depth):
            level = [d for p in level for d in sorted(p.iterdir()) if d.is_dir() and not d.name.startswith("_")]
        yield from level


def check_config(html_path, kind):
    text = html_path.read_text(encoding="utf-8")
    if "Mock.mount(" not in text:
        if kind != "proposals":
            bad(f"{html_path.relative_to(ROOT)}: no Mock.mount(...) call")
        return
    for key in REQUIRED:
        if not re.search(r"(^|[\s{,])" + key + r"\s*:", text):
            bad(f"{html_path.relative_to(ROOT)}: config is missing `{key}:`")
    if "reviews" in text and not (re.search(r"\bhig\s*:", text) and re.search(r"\bswiftui\s*:", text)):
        bad(f"{html_path.relative_to(ROOT)}: reviews needs hig: and swiftui:")


def main():
    on_disk = {}
    for folder in mockup_dirs():
        kind = folder.relative_to(ROOT).parts[0]
        html = folder / f"{folder.name}.html"
        if not html.exists():
            bad(f"{folder.relative_to(ROOT)}: no {folder.name}.html (folder name must equal the file stem)")
            continue
        on_disk[folder.name] = html
        readme = folder / "README.md"
        if kind == "proposals":
            pass  # owner-review proposals are frozen records (propose-first.md): no README required
        elif not readme.exists():
            bad(f"{folder.relative_to(ROOT)}: no README.md")
        elif len(readme.read_text(encoding="utf-8").splitlines()) > 40:
            bad(f"{readme.relative_to(ROOT)}: longer than 40 lines")
        check_config(html, kind)
    kit = ROOT / "_kit"
    declared = re.search(r"Mock\.COMPONENTS\s*=\s*\[(.*?)\];", (kit / "kit.js").read_text(encoding="utf-8"), re.S)
    names = set(re.findall(r"'([^']+)'", declared.group(1))) if declared else set()
    files = {p.stem for p in (kit / "components").glob("*.js")}
    for missing in sorted(names - files):
        bad(f"_kit/kit.js lists component {missing} but components/{missing}.js does not exist")
    for extra in sorted(files - names):
        bad(f"_kit/components/{extra}.js is not listed in Mock.COMPONENTS (kit.js)")
    catalog = ROOT / "catalog.json"
    if catalog.exists():
        data = json.loads(catalog.read_text(encoding="utf-8"))
        entries = data if isinstance(data, list) else data.get("items", data.get("mockups", []))
        ids = [e.get("id") for e in entries]
        for dup in {i for i in ids if ids.count(i) > 1}:
            bad(f"catalog.json: duplicate id {dup}")
        for entry in entries:
            folder = ROOT / entry.get("path", "?")
            built = entry.get("mockup")
            if built and not (ROOT / built).exists():
                bad(f"catalog.json: {entry['id']} mockup {built} does not exist")
            if not built and (folder / f"{entry['id']}.html").exists():
                bad(f"catalog.json: {entry['id']} has a mockup on disk but `mockup` is null (set it to {entry.get('path')}/{entry['id']}.html)")
            for src in entry.get("sources", []):
                if not (REPO / src).exists():
                    bad(f"catalog.json: {entry['id']} source {src} does not exist")
        listed = set(ids)
        for missing in sorted(n for n, h in on_disk.items() if n not in listed and "proposals" not in h.parts):
            bad(f"catalog.json: mockup {missing} is on disk but not listed")
    print(f"mockups_check: {len(on_disk)} mockups, {len(names)} components, catalog {'present' if catalog.exists() else 'absent'}")
    for p in problems:
        print("  - " + p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
