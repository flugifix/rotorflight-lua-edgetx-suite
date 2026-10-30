#!/usr/bin/env python3
"""Write the menu structure of the configuration tool into the documentation.

`docs/reference/menu-structure.md` is generated from two files, read without running
any Lua:

  * `src/rfsuite/app/manifest.lua` -- the sections, the menus and their entries, in the
    order the tool shows them, and the conditions each entry carries;
  * `src/rfsuite/app/pages/init.lua` -- which menu id opens which page file.

Titles written as `@i18n(key)@` are resolved to English with the same loader the
packager uses (`.vscode/scripts/resolve_i18n_tags.py`, reading `src/rfsuite/i18n/en.lua`),
so the page names an entry the way the radio does.

Every key an entry carries is listed as written, except the ones that identify or place
it: `id`, `title`, `menuId`, `icon`, `row` and `col`. A key that is added to the manifest
later therefore appears on the page without a change here. Nothing is interpreted: the
page says what the manifest says, and `docs/reference/README.md` is where the meaning of
a condition belongs.

The documentation file of a page follows the rule in `CONTRIBUTING.md` (under
*Documentation*) and `docs/pages/README.md`: the page `setup/power/smartfuel/page.lua` is
documented in `docs/pages/setup/power/smartfuel.md`. A page whose file does not exist is
marked as such, so adding or removing a file under `docs/pages/` changes this page too.

The same tree is drawn above the tables as Mermaid flowcharts -- an overview of the
sections and menus, then one chart per menu of a section -- coloured by whether an entry
is a menu, a documented page or a page without documentation. They are generated from the
same reading, so the charts and the tables cannot disagree.

A source this cannot read -- an unbalanced table, a missing `sections` or `menus`, an
entry without an `id` or a `menuId`, a title key with no English text -- stops it with
the line it stopped at, and nothing is written.

    python3 bin/docs/menu_structure.py              # write the page
    python3 bin/docs/menu_structure.py --check      # print a diff and exit 1 if it is stale
    python3 bin/docs/menu_structure.py --self-test  # prove both of the above can go red
"""

import argparse
import difflib
import importlib.util
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

MANIFEST = "src/rfsuite/app/manifest.lua"
REGISTRY = "src/rfsuite/app/pages/init.lua"
TRANSLATIONS = "src/rfsuite/i18n/en.lua"
RESOLVER = ".vscode/scripts/resolve_i18n_tags.py"
OUTPUT = "docs/reference/menu-structure.md"

DOCS_PAGES_DIR = "docs/pages/"

#: The keys that identify an entry or place its tile. Every other key is a condition.
STRUCTURAL_KEYS = ("id", "title", "menuId", "icon", "row", "col")
#: The keys of a menu table that are not a condition of the menu.
MENU_KEYS = ("title", "pages")

I18N_TAG = re.compile(r"@i18n\(([^)]+)\)@")


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


lua_source = load_module("lua_source", Path(__file__).with_name("lua_source.py"))
Lua = lua_source.Lua
LuaSourceError = lua_source.LuaSourceError


class SourceError(Exception):
    """The sources do not describe a menu tree this can write down."""


# --------------------------------------------------------------------------- reading


class Reader:
    """One Lua file, with the helpers to read its table constructors as data."""

    def __init__(self, name, text):
        self.name = name
        try:
            self.lua = Lua(text)
        except LuaSourceError as err:
            raise SourceError(f"{name}: {err}") from None
        self.index = {t.offset: i for i, t in enumerate(self.lua.tokens)}

    def fail(self, ts, what):
        line = ts[0].line if ts else "?"
        raise SourceError(f"{self.name}:{line}: {what}")

    def local_table(self, name):
        """The index of the `{` in `local <name> = {`; exactly one must exist."""
        ts = self.lua.tokens
        found = [i + 3 for i in range(len(ts) - 3)
                 if ts[i].value == "local" and ts[i + 1].value == name
                 and ts[i + 2].value == "=" and ts[i + 3].value == "{"]
        if len(found) != 1:
            raise SourceError(f"{self.name}: expected one `local {name} = {{`, found {len(found)}")
        return found[0]

    def table_start(self, ts, what):
        if not ts or ts[0].value != "{" or self.lua.pairs.get(self.index[ts[0].offset]) is None:
            self.fail(ts, f"{what} is not a table")
        start = self.index[ts[0].offset]
        if self.index[ts[-1].offset] != self.lua.pairs[start]:
            self.fail(ts, f"{what} is more than one table")
        return start

    def fields(self, ts, what):
        return self.lua.fields(self.table_start(ts, what))

    def items(self, ts, what):
        start = self.table_start(ts, what)
        return [part for part in self.lua.split(start + 1, self.lua.pairs[start]) if part]

    def string(self, ts, what):
        value = lua_source.literal(ts)
        if value is None:
            value = assembled(ts)
        if value is None:
            self.fail(ts, f"{what} is not a string literal")
        return value

    def render(self, ts):
        """A value as source text: `true`, `"fblConnected"`, `{ 12, 0, 9 }`."""
        if ts and ts[0].value == "{" and self.index[ts[-1].offset] == self.lua.pairs.get(
                self.index[ts[0].offset]):
            inner = self.items(ts, "value")
            return "{ " + ", ".join(self.render(p) for p in inner) + " }" if inner else "{}"
        return lua_source.expression(ts)


def assembled(ts):
    """The string Lua builds from a `..` chain of string and integer literals, such as
    `1 .. ". " .. "@i18n(key)@"`, or None when any part is not a literal."""
    parts, current = [], []
    for t in ts:
        if t.value == "..":
            parts.append(current)
            current = []
        else:
            current.append(t)
    parts.append(current)
    if len(parts) < 2:
        return None
    text = []
    for part in parts:
        value = lua_source.literal(part)
        if value is None and len(part) == 1 and re.fullmatch(r"\d+", part[0].value):
            value = part[0].value
        if value is None:
            return None
        text.append(value)
    return "".join(text)


def read_manifest(text):
    """(sections, menus) from the manifest source, in source order."""
    r = Reader(MANIFEST, text)
    top = r.lua.fields(r.local_table("manifest"))
    for key in ("sections", "menus"):
        if key not in top:
            raise SourceError(f"{MANIFEST}: the manifest has no `{key}` table")

    def entry(ts, where):
        fields = r.fields(ts, f"an entry of {where}")
        for key in ("id", "title", "menuId"):
            if key not in fields:
                r.fail(ts, f"an entry of {where} has no `{key}`")
        return {
            "id": r.string(fields["id"], "`id`"),
            "title": r.string(fields["title"], "`title`"),
            "menuId": r.string(fields["menuId"], "`menuId`"),
            "conditions": [(k, r.render(v)) for k, v in fields.items() if k not in STRUCTURAL_KEYS],
            "line": ts[0].line,
        }

    sections = []
    for ts in r.items(top["sections"], "`sections`"):
        fields = r.fields(ts, "a section")
        for key in ("id", "title", "pages"):
            if key not in fields:
                r.fail(ts, f"a section has no `{key}`")
        sid = r.string(fields["id"], "a section's `id`")
        sections.append({
            "id": sid,
            "title": r.string(fields["title"], "a section's `title`"),
            "entries": [entry(p, f"section `{sid}`") for p in r.items(fields["pages"], "`pages`")],
        })

    menus = {}
    for name, ts in r.fields(top["menus"], "`menus`").items():
        fields = r.fields(ts, f"menu `{name}`")
        for key in MENU_KEYS:
            if key not in fields:
                r.fail(ts, f"menu `{name}` has no `{key}`")
        menus[name] = {
            "title": r.string(fields["title"], f"the `title` of menu `{name}`"),
            "entries": [entry(p, f"menu `{name}`") for p in r.items(fields["pages"], f"`{name}.pages`")],
            "conditions": [(k, r.render(v)) for k, v in fields.items() if k not in MENU_KEYS],
        }
    if not sections or not menus:
        raise SourceError(f"{MANIFEST}: no sections or no menus were read")
    return sections, menus


def read_registry(text):
    """{menu id: page directory under app/pages/} from `pages/init.lua`, in source order."""
    r = Reader(REGISTRY, text)
    pages = {}
    for name, ts in r.lua.fields(r.local_table("entries")).items():
        if len(ts) != 4 or ts[0].value != "definePage" or ts[1].value != "(" or ts[3].value != ")":
            r.fail(ts, f"`{name}` is not `definePage(\"<path>\")`")
        pages[name] = r.string(ts[2:3], f"the path of `{name}`")
    if not pages:
        raise SourceError(f"{REGISTRY}: no page entries were read")
    return pages


class Titles:
    """English titles, through the packager's own translation loader."""

    def __init__(self, root):
        resolver = load_module("resolve_i18n_tags", root / RESOLVER)
        self.tree = resolver.load_translations(root / TRANSLATIONS)
        self.resolve_key = resolver.resolve_key

    def __call__(self, title, where):
        def one(match):
            found = self.resolve_key(self.tree, match.group(1))
            if not found:
                raise SourceError(f"{where}: `{match.group(1)}` has no text in {TRANSLATIONS}")
            return found[0]
        return I18N_TAG.sub(one, title)


# --------------------------------------------------------------------------- writing


def doc_file(page_dir):
    return DOCS_PAGES_DIR + page_dir + ".md"


def cell(text):
    return text.replace("|", "\\|")


#: Node styles of the diagrams. Only the border is coloured: the fill and the text keep
#: the colours of the page's light or dark scheme, so a node stays readable in both.
DIAGRAM_CLASSES = (
    "classDef section stroke:#78909c,stroke-width:3px,font-weight:bold",
    "classDef menu stroke:#1e88e5,stroke-width:2px",
    "classDef documented stroke:#43a047,stroke-width:2px",
    "classDef undocumented stroke:#fb8c00,stroke-width:2px,stroke-dasharray:5 4",
    "classDef empty stroke:#9e9e9e,stroke-width:2px,stroke-dasharray:2 3",
)


def node_label(text):
    """A title as a quoted Mermaid label; `"`, `&`, `<` and `>` as entity codes."""
    for char, code in (("&", "#amp;"), ('"', "#quot;"), ("<", "#lt;"), (">", "#gt;")):
        text = text.replace(char, code)
    return f'["{text}"]'


def build_diagrams(sections, menus, pages, docs_exist, title_of, titles):
    """The menu tree as Mermaid flowcharts: one overview of the sections and every menu,
    then one chart per menu of a section with every entry below it. Returns the lines."""

    def submenu(entry):
        menu = menus.get(entry["menuId"])
        return menu["entries"] if menu and menu["entries"] else []

    def style(entry):
        menu_id = entry["menuId"]
        if menu_id in pages:
            return "documented" if docs_exist(doc_file(pages[menu_id])) else "undocumented"
        return "menu" if submenu(entry) else "empty"

    def chart(roots, keep):
        """One flowchart; `roots` are (label, class, entries) and `keep(entry)` says
        whether an entry below a root is drawn."""
        lines, counter = ["```mermaid", "flowchart LR"], [0]

        def node(label, cls):
            name = f"n{counter[0]}"
            counter[0] += 1
            lines.append(f"  {name}{node_label(label)}:::{cls}")
            return name

        def walk(parent, entries, stack):
            for entry in entries:
                if not keep(entry):
                    continue
                child = node(title_of(entry, entry["id"]), style(entry))
                lines.append(f"  {parent} --> {child}")
                if entry["menuId"] in stack:
                    raise SourceError(f"{MANIFEST}:{entry['line']}: menu `{entry['menuId']}` contains itself")
                walk(child, submenu(entry), stack + [entry["menuId"]])

        for label, cls, entries, stack in roots:
            walk(node(label, cls), entries, stack)
        return lines + ["  " + c for c in DIAGRAM_CLASSES] + ["```", ""]

    overview = [(titles(s["title"], f"{MANIFEST} (section `{s['id']}`)"), "section", s["entries"], [])
                for s in sections]
    top_level = {id(e) for s in sections for e in s["entries"]}
    lines = [
        "## Diagrams",
        "",
        "The same tree drawn as charts, generated with the tables below. The border says what",
        "an entry is: blue a menu, green a page that is documented, orange and dashed a page",
        "with no documentation yet, grey and dotted an entry that opens neither a page file",
        "nor a menu with entries. A page that also opens a menu is drawn as a page.",
        "",
        "### Overview",
        "",
        "The sections and every menu in them; the pages of each menu are in the charts that",
        "follow.",
        "",
    ] + chart(overview, lambda e: id(e) in top_level or bool(submenu(e)))

    for section in sections:
        for entry in section["entries"]:
            if not submenu(entry):
                continue
            name = title_of(entry, entry["id"])
            lines += [f"### {name}", ""] + chart(
                [(name, "menu", submenu(entry), [entry["menuId"]])], lambda e: True)
    return lines


def build(root, manifest_text, registry_text, docs_exist, titles):
    """The page as text. `docs_exist(path)` answers whether a documentation file exists."""
    sections, menus = read_manifest(manifest_text)
    pages = read_registry(registry_text)

    def title_of(entry, where):
        return titles(entry["title"], f"{MANIFEST}:{entry['line']} ({where})")

    for name, menu in menus.items():
        menu["title_en"] = titles(menu["title"], f"{MANIFEST} (menu `{name}`)")

    reached = set()
    counts = {"entries": 0, "pages": 0, "documented": 0}

    def opens(menu_id):
        parts = []
        if menu_id in pages:
            parts.append(f"`{pages[menu_id]}`")
        menu = menus.get(menu_id)
        if menu and menu["entries"]:
            count = len(menu["entries"])
            parts.append(f"menu, {count} entr{'y' if count == 1 else 'ies'}")
        if menu_id not in pages and menu_id not in menus:
            raise SourceError(f"{MANIFEST}: `{menu_id}` is neither a menu nor a page in {REGISTRY}")
        return " + ".join(parts) or "no page file and no entries"

    def documentation(menu_id):
        if menu_id not in pages:
            return "&mdash;"
        path = doc_file(pages[menu_id])
        if docs_exist(path):
            return f"[{pages[menu_id]}.md](../pages/{pages[menu_id]}.md)"
        return "**none**"

    def conditions(entry):
        found = [f"`{k} = {v}`" for k, v in entry["conditions"]]
        menu = menus.get(entry["menuId"])
        if menu:
            found += [f"menu: `{k} = {v}`" for k, v in menu["conditions"]]
        return ", ".join(found) or "&mdash;"

    def walk(entries, trail, stack, rows):
        for entry in entries:
            menu_id = entry["menuId"]
            name = title_of(entry, entry["id"])
            path = trail + [name]
            counts["entries"] += 1
            if menu_id in pages:
                counts["pages"] += 1
                if docs_exist(doc_file(pages[menu_id])):
                    counts["documented"] += 1
            reached.add(menu_id)
            rows.append("| %s | `%s` | `%s` | %s | %s | %s |" % (
                cell(" &rsaquo; ".join(path)), entry["id"], menu_id, opens(menu_id),
                documentation(menu_id), cell(conditions(entry))))
            menu = menus.get(menu_id)
            if menu and menu["entries"]:
                if menu_id in stack:
                    raise SourceError(f"{MANIFEST}:{entry['line']}: menu `{menu_id}` contains itself")
                walk(menu["entries"], path, stack + [menu_id], rows)

    body = []
    for section in sections:
        rows = []
        walk(section["entries"], [], [], rows)
        heading = titles(section["title"], f"{MANIFEST} (section `{section['id']}`)")
        body += [
            f"## {heading}",
            "",
            f"Section `{section['id']}`.",
            "",
            "| Menu path | Entry id | Menu id | Opens | Documentation | Conditions |",
            "| --- | --- | --- | --- | --- | --- |",
        ] + rows + [""]

    diagrams = build_diagrams(sections, menus, pages, docs_exist, title_of, titles)

    loose = []
    for menu_id in list(menus) + [p for p in pages if p not in menus]:
        if menu_id in reached:
            continue
        title = menus[menu_id]["title_en"] if menu_id in menus else "&mdash;"
        where = "manifest" + (" + page registry" if menu_id in pages else "") if menu_id in menus \
            else "page registry"
        loose.append("| `%s` | %s | %s | %s | %s |" % (
            menu_id, cell(title), where,
            f"`{pages[menu_id]}`" if menu_id in pages else "&mdash;", documentation(menu_id)))

    head = [
        "---",
        "title: Menu structure",
        "sidebar_label: Menu structure",
        "---",
        "",
        "<!-- Generated by bin/docs/menu_structure.py from src/rfsuite/app/manifest.lua and",
        "     src/rfsuite/app/pages/init.lua. Do not edit by hand: run",
        "     `python3 bin/docs/menu_structure.py` and commit the result. -->",
        "",
        "# Menu structure",
        "",
        "Every entry of the configuration tool's menus, in the order the tool shows them, with",
        "the page it opens, the documentation of that page and the conditions the menu",
        "definition attaches to it. The page is generated from the sources and checked in CI,",
        "so it matches the code it was generated from.",
        "",
        "- **Menu path** -- the titles in English, from the section down.",
        "- **Entry id**, **Menu id** -- the entry's `id` and the `menuId` it opens.",
        "- **Opens** -- the page file under `src/rfsuite/app/pages/` (`<path>/page.lua`), a",
        "  submenu, or both.",
        "- **Documentation** -- the file under `docs/pages/` that documents the page;",
        "  **none** where that file does not exist yet, &mdash; where nothing opens a page.",
        "- **Conditions** -- every other key of the entry as the menu definition writes it,",
        "  and the keys of the submenu it opens (`menu:`). The keys that only identify or place",
        "  an entry (`" + "`, `".join(STRUCTURAL_KEYS) + "`) are left out. What a condition",
        "  does is not explained here.",
        "",
        "**%d entries, %d of them open a page, %d of those pages are documented.**" % (
            counts["entries"], counts["pages"], counts["documented"]),
        "",
    ] + diagrams
    tail = [
        "## Not an entry of any menu",
        "",
        "Menu ids that the menu definition (`src/rfsuite/app/manifest.lua`) or the page registry",
        "(`src/rfsuite/app/pages/init.lua`) knows, but that no menu above lists. Whether code",
        "outside the menus opens one of them is not read here.",
        "",
        "| Menu id | Title | Defined in | Page file | Documentation |",
        "| --- | --- | --- | --- | --- |",
    ] + loose + [""] if loose else []
    return "\n".join(head + body + tail).rstrip("\n") + "\n"


def menu_tree(root):
    """The menus as nested entries, in the order the tool shows them, for the site navigation.

    One dict per section and per entry: `title` in English, `menuId`, `page` -- the page
    directory under `app/pages/` the entry opens, or None -- and `children`, the entries of
    the menu it opens. The same reading as the page above, so the two cannot disagree.
    """
    titles = Titles(root)
    sections, menus = read_manifest((root / MANIFEST).read_text(encoding="utf-8"))
    pages = read_registry((root / REGISTRY).read_text(encoding="utf-8"))

    def walk(entries, stack):
        nodes = []
        for entry in entries:
            menu_id = entry["menuId"]
            menu = menus.get(menu_id)
            children = []
            if menu and menu["entries"]:
                if menu_id in stack:
                    raise SourceError(f"{MANIFEST}:{entry['line']}: menu `{menu_id}` contains itself")
                children = walk(menu["entries"], stack + [menu_id])
            nodes.append({
                "title": titles(entry["title"], f"{MANIFEST}:{entry['line']} ({entry['id']})"),
                "menuId": menu_id,
                "page": pages.get(menu_id),
                "children": children,
            })
        return nodes

    return [{
        "title": titles(section["title"], f"{MANIFEST} (section `{section['id']}`)"),
        "menuId": None,
        "page": None,
        "children": walk(section["entries"], []),
    } for section in sections]


def generate(root):
    def docs_exist(path):
        return (root / path).is_file()
    return build(root,
                 (root / MANIFEST).read_text(encoding="utf-8"),
                 (root / REGISTRY).read_text(encoding="utf-8"),
                 docs_exist, Titles(root))


def drift(expected, current, name):
    """A unified diff from the file as it is to the file as it should be; empty if equal."""
    return "".join(difflib.unified_diff(
        current.splitlines(keepends=True), expected.splitlines(keepends=True),
        fromfile=f"{name} (committed)", tofile=f"{name} (generated)"))


def read_lf(path):
    if not path.is_file():
        return ""
    return path.read_bytes().decode("utf-8").replace("\r\n", "\n")


# --------------------------------------------------------------------------- control


def self_test(root):
    """Each case states its verdict before it runs; the red ones are the point."""
    manifest = (root / MANIFEST).read_text(encoding="utf-8").replace("\r\n", "\n")
    registry = (root / REGISTRY).read_text(encoding="utf-8").replace("\r\n", "\n")
    titles = Titles(root)

    def docs_exist(path):
        return (root / path).is_file()

    def page(m=manifest, g=registry, t=titles):
        return build(root, m, g, docs_exist, t)

    baseline = page()
    first = re.search(r"lockedWhileArmed = true", manifest)
    entry_line = manifest.count("\n", 0, first.start())
    lines = manifest.split("\n")
    changed = "\n".join(lines[:entry_line]
                        + [lines[entry_line].replace("lockedWhileArmed = true", "lockedWhileArmed = false", 1)]
                        + lines[entry_line + 1:])
    without_menus = manifest.replace("  menus = {", "  pages_by_menu = {", 1)
    unbalanced = manifest[:manifest.rindex("}")]
    no_menu_id = manifest.replace('menuId = "tools_menu", ', "", 1)
    bad_registry = registry.replace('definePage("logs")', 'definePage(LOGS_PATH)', 1)
    unknown_key = manifest.replace("@i18n(app.modules.tools.name)@", "@i18n(app.modules.tools.no_such_key)@", 1)
    tools_title = 'title = "@i18n(app.modules.tools.name)@", menuId = "tools_menu"'
    numbered = manifest.replace(tools_title, 'title = 1 .. ". " .. "@i18n(app.modules.tools.name)@", menuId = "tools_menu"', 1)
    computed = manifest.replace(tools_title, 'title = n .. "@i18n(app.modules.tools.name)@", menuId = "tools_menu"', 1)
    numbered_title = "1. " + titles("@i18n(app.modules.tools.name)@", "self-test")

    def charted(text):
        """'complete' when the charts after the overview draw, besides their root, exactly
        the entries the tables list below a section's first level; 'short' otherwise."""
        charts = text.split("```mermaid")[2:]
        drawn = sum(chart.split("```")[0].count(":::") - 1 for chart in charts)
        rows = [line for line in text.split("\n") if line.startswith("| ") and "` | `" in line
                and not line.startswith("| `")]
        nested = sum(1 for line in rows if "&rsaquo;" in line.split(" | ")[0])
        return "complete" if drawn == nested else "short"

    def unchart(text):
        """The page with the first page node of the second chart removed."""
        head, _, rest = text.partition("```mermaid")
        overview, _, rest = rest.partition("```mermaid")
        node = re.search(r"\n  n\d+\[[^\n]*:::documented", rest)
        return head + "```mermaid" + overview + "```mermaid" + rest[:node.start()] + rest[node.end():]

    def verdict(run):
        try:
            return run(), ""
        except SourceError as err:
            return "error", str(err)

    cases = [
        ("the tree as it is generates", lambda: page() and "ok", "ok"),
        ("a one-line manifest change is drift",
         lambda: "drift" if drift(page(changed), baseline, "page") else "same", "drift"),
        ("the page lists a sample entry",
         lambda: "listed" if "`flight_tuning_pids_page`" in baseline else "missing", "listed"),
        ("a manifest without `menus` fails", lambda: page(without_menus) and "ok", "error"),
        ("an unbalanced manifest fails", lambda: page(unbalanced) and "ok", "error"),
        ("an entry without `menuId` fails", lambda: page(no_menu_id) and "ok", "error"),
        ("a registry path that is not a literal fails", lambda: page(g=bad_registry) and "ok", "error"),
        ("a title key without English text fails", lambda: page(unknown_key) and "ok", "error"),
        ("a title assembled from literals is read as one string",
         lambda: "listed" if numbered_title in page(numbered) and numbered_title not in baseline else "missing", "listed"),
        ("a title assembled from a variable fails", lambda: page(computed) and "ok", "error"),
        ("the menu charts draw every entry once", lambda: charted(baseline), "complete"),
        ("a chart missing one node is caught", lambda: charted(unchart(baseline)), "short"),
        ("a label escapes quotes and markup",
         lambda: "escaped" if node_label('A "b" & <c>') == '["A #quot;b#quot; #amp; #lt;c#gt;"]' else "raw",
         "escaped"),
    ]
    if manifest in (unbalanced, no_menu_id, without_menus, unknown_key, changed, numbered, computed) \
            or bad_registry == registry:
        print("FAIL  a mutation found nothing to change -- the control is stale")
        return 1

    failures = 0
    for what, run, expect in cases:
        got, detail = verdict(run)
        mark = "ok  " if got == expect else "FAIL"
        failures += got != expect
        print(f"  {mark}  expects {expect:6} {what}" + (f"\n        {detail}" if detail else ""))
    if failures:
        print(f"\n{failures} self-test case(s) failed -- this check proves nothing.")
        return 1
    print(f"\n{len(cases)} case(s): the page can be generated, can drift and can refuse a source.")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true",
                    help="regenerate in memory, print a diff and exit 1 if the page is stale")
    ap.add_argument("--self-test", action="store_true", help="run the control and exit")
    args = ap.parse_args()

    if args.self_test:
        return self_test(ROOT)
    try:
        text = generate(ROOT)
    except SourceError as err:
        print(f"FAILED -- {err}\nNothing was written.")
        return 2
    if args.check:
        diff = drift(text, read_lf(ROOT / OUTPUT), OUTPUT)
        if diff:
            sys.stdout.write(diff)
            print(f"\nFAILED -- {OUTPUT} does not match the menu definition.\n"
                  "  It follows the menu definition, the page registry, the English titles and\n"
                  "  the files under docs/pages/. Run `python3 bin/docs/menu_structure.py` and\n"
                  "  commit the result.")
            return 1
        print(f"OK -- {OUTPUT} matches the menu definition.")
        return 0
    (ROOT / OUTPUT).write_bytes(text.encode("utf-8"))
    print(f"Wrote {OUTPUT}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
