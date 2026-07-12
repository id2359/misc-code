#!/usr/bin/env python3
"""Dedupe a Netscape-format bookmark HTML export (Brave/Chrome/Firefox).

- Removes duplicate URLs, keeping the copy with the longest or shortest
  link text (ties broken by first occurrence in document order).
- Merges sibling folders with the same name (recursively).
- Optionally prunes folders left empty after deduplication.

Output is a valid Netscape bookmark file re-importable into Brave.
Stdlib only.
"""

from __future__ import annotations

import argparse
import html
import sys
from dataclasses import dataclass, field
from html.parser import HTMLParser
from urllib.parse import urlsplit, urlunsplit


# --------------------------------------------------------------------------
# Data model
# --------------------------------------------------------------------------

@dataclass
class Bookmark:
    url: str
    text: str
    attrs: dict[str, str]  # ADD_DATE, ICON, etc. (HREF excluded)
    order: int = 0         # document order, for tie-breaking


@dataclass
class Folder:
    name: str
    attrs: dict[str, str]  # ADD_DATE, PERSONAL_TOOLBAR_FOLDER, etc.
    children: list = field(default_factory=list)  # Bookmark | Folder


# --------------------------------------------------------------------------
# Parser
# --------------------------------------------------------------------------

class BookmarkParser(HTMLParser):
    """Tolerant parser for the (sloppy) Netscape bookmark format.

    The format never closes <DT> and sprinkles <p> around, so we key the
    tree structure off <DL>/<H3>/<A> only.
    """

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.root = Folder(name="", attrs={})
        self._stack: list[Folder] = []
        self._pending_folder: Folder | None = None
        self._pending_bookmark: Bookmark | None = None
        self._text_parts: list[str] = []
        self._capture: str | None = None  # "h3" | "a" | None
        self._counter = 0
        self._seen_first_dl = False

    # -- helpers ----------------------------------------------------------

    @property
    def _current(self) -> Folder:
        return self._stack[-1] if self._stack else self.root

    def _flush_text(self) -> str:
        text = "".join(self._text_parts).strip()
        self._text_parts.clear()
        return text

    # -- HTMLParser hooks --------------------------------------------------

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        attr_map = {k.upper(): (v or "") for k, v in attrs}

        if tag == "dl":
            if not self._seen_first_dl:
                self._seen_first_dl = True
                self._stack.append(self.root)
            elif self._pending_folder is not None:
                folder = self._pending_folder
                self._pending_folder = None
                self._current.children.append(folder)
                self._stack.append(folder)
            else:
                # DL without a preceding H3 (shouldn't happen, but be safe)
                anon = Folder(name="", attrs={})
                self._current.children.append(anon)
                self._stack.append(anon)
        elif tag == "h3":
            self._capture = "h3"
            self._pending_folder = Folder(name="", attrs=attr_map)
        elif tag == "a":
            self._capture = "a"
            url = attr_map.pop("HREF", "")
            self._pending_bookmark = Bookmark(url=url, text="", attrs=attr_map)

    def handle_endtag(self, tag):
        tag = tag.lower()
        if tag == "dl":
            if self._stack:
                self._stack.pop()
        elif tag == "h3" and self._capture == "h3":
            if self._pending_folder is not None:
                self._pending_folder.name = self._flush_text()
            self._capture = None
        elif tag == "a" and self._capture == "a":
            bm = self._pending_bookmark
            self._pending_bookmark = None
            self._capture = None
            if bm is not None:
                bm.text = self._flush_text()
                self._counter += 1
                bm.order = self._counter
                self._current.children.append(bm)

    def handle_data(self, data):
        if self._capture:
            self._text_parts.append(data)


def parse_bookmarks(source: str) -> Folder:
    parser = BookmarkParser()
    parser.feed(source)
    parser.close()
    return parser.root


# --------------------------------------------------------------------------
# Deduplication
# --------------------------------------------------------------------------

def normalize_url(url: str) -> str:
    """Case-fold scheme/host, drop fragment, strip trailing slash on bare paths."""
    try:
        parts = urlsplit(url)
    except ValueError:
        return url
    path = parts.path
    if path.endswith("/") and path != "/":
        path = path.rstrip("/")
    return urlunsplit((parts.scheme.lower(), parts.netloc.lower(),
                       path, parts.query, ""))


def iter_bookmarks(folder: Folder):
    """Yield every Bookmark in the tree, depth-first document order."""
    for child in folder.children:
        if isinstance(child, Folder):
            yield from iter_bookmarks(child)
        else:
            yield child


def dedupe_urls(root: Folder, keep: str, normalize: bool) -> int:
    """Remove duplicate-URL bookmarks; returns number removed."""
    groups: dict[str, list[Bookmark]] = {}
    for bm in iter_bookmarks(root):
        key = normalize_url(bm.url) if normalize else bm.url
        groups.setdefault(key, []).append(bm)

    losers: set[int] = set()
    for group in groups.values():
        if len(group) < 2:
            continue
        # max/min by text length; earliest document order wins ties
        pick = max if keep == "longest" else min
        winner = pick(group, key=lambda b: (len(b.text), -b.order))
        losers.update(id(b) for b in group if b is not winner)

    def prune(folder: Folder):
        folder.children = [
            c for c in folder.children
            if isinstance(c, Folder) or id(c) not in losers
        ]
        for c in folder.children:
            if isinstance(c, Folder):
                prune(c)

    prune(root)
    return len(losers)


def merge_folders(folder: Folder, case_insensitive: bool) -> int:
    """Merge sibling folders sharing a name; returns number of folders merged away."""
    merged = 0
    seen: dict[str, Folder] = {}
    new_children = []
    for child in folder.children:
        if isinstance(child, Folder):
            key = child.name.casefold() if case_insensitive else child.name
            if key in seen:
                seen[key].children.extend(child.children)
                # keep useful attrs from the absorbed folder if missing
                for k, v in child.attrs.items():
                    seen[key].attrs.setdefault(k, v)
                merged += 1
                continue
            seen[key] = child
        new_children.append(child)
    folder.children = new_children

    for child in folder.children:
        if isinstance(child, Folder):
            merged += merge_folders(child, case_insensitive)
    return merged


def prune_empty(folder: Folder) -> int:
    """Remove folders with no remaining children (post-order); returns count."""
    removed = 0
    kept = []
    for child in folder.children:
        if isinstance(child, Folder):
            removed += prune_empty(child)
            if not child.children:
                removed += 1
                continue
        kept.append(child)
    folder.children = kept
    return removed


# --------------------------------------------------------------------------
# Serialization
# --------------------------------------------------------------------------

HEADER = """<!DOCTYPE NETSCAPE-Bookmark-file-1>
<!-- This is an automatically generated file.
     It will be read and overwritten.
     DO NOT EDIT! -->
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Bookmarks</TITLE>
<H1>Bookmarks</H1>
"""


def _attrs_str(attrs: dict[str, str]) -> str:
    return "".join(f' {k}="{html.escape(v, quote=True)}"' for k, v in attrs.items())


def serialize(root: Folder) -> str:
    lines = [HEADER.rstrip("\n"), "<DL><p>"]

    def emit(folder: Folder, depth: int):
        pad = "    " * depth
        for child in folder.children:
            if isinstance(child, Folder):
                lines.append(f"{pad}<DT><H3{_attrs_str(child.attrs)}>"
                             f"{html.escape(child.name)}</H3>")
                lines.append(f"{pad}<DL><p>")
                emit(child, depth + 1)
                lines.append(f"{pad}</DL><p>")
            else:
                href = html.escape(child.url, quote=True)
                lines.append(f'{pad}<DT><A HREF="{href}"{_attrs_str(child.attrs)}>'
                             f"{html.escape(child.text)}</A>")

    emit(root, 1)
    lines.append("</DL><p>")
    return "\n".join(lines) + "\n"


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        description="Dedupe a Brave bookmark HTML export.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("input", help="bookmark HTML export file")
    ap.add_argument("-o", "--output",
                    help="output file (default: <input>.deduped.html)")
    ap.add_argument("--keep", choices=("longest", "shortest"), default="longest",
                    help="which copy of a duplicate URL to keep, by link text length")
    ap.add_argument("--normalize-urls", action="store_true",
                    help="treat URLs as duplicates ignoring case of host, "
                         "fragments, and trailing slashes")
    ap.add_argument("--no-merge-folders", action="store_true",
                    help="do not merge same-named sibling folders")
    ap.add_argument("--case-insensitive-folders", action="store_true",
                    help="match folder names case-insensitively when merging")
    ap.add_argument("--prune-empty", action="store_true",
                    help="remove folders left empty after deduplication")
    ap.add_argument("--dry-run", action="store_true",
                    help="report what would change without writing output")
    args = ap.parse_args(argv)

    with open(args.input, encoding="utf-8", errors="replace") as f:
        root = parse_bookmarks(f.read())

    total_before = sum(1 for _ in iter_bookmarks(root))
    removed = dedupe_urls(root, keep=args.keep, normalize=args.normalize_urls)
    merged = 0 if args.no_merge_folders else merge_folders(
        root, args.case_insensitive_folders)
    pruned = prune_empty(root) if args.prune_empty else 0

    print(f"bookmarks: {total_before} -> {total_before - removed} "
          f"({removed} duplicate URL{'s' if removed != 1 else ''} removed, "
          f"kept {args.keep} text)", file=sys.stderr)
    print(f"folders merged: {merged}, empty folders pruned: {pruned}",
          file=sys.stderr)

    if args.dry_run:
        return 0

    out_path = args.output or (args.input.rsplit(".", 1)[0] + ".deduped.html")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(serialize(root))
    print(f"wrote {out_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
