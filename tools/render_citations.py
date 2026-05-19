#!/usr/bin/env python3
"""Render citation variants from citations.yaml (single source of truth).

Edit ~/Github/registream-org/registream/citations.yaml, then run:

    python tools/render_citations.py check          # print all variants
    python tools/render_citations.py write-python   # write _citation_data.py into Python packages
    python tools/render_citations.py write-r        # write _citation_data.R into R packages
    python tools/render_citations.py write-flask    # vendor a copy into registream-website/app/
    python tools/render_citations.py write-cff      # write CITATION.cff into each repo root
    python tools/render_citations.py write-all      # all of the above

Callers that want the data as a dict (e.g. the Stata build script) import
``load()`` and ``as_dict()`` directly.

Version handling:
- ``apa`` is versionless — for the website and plain citations.
- ``apa_versioned`` emits the literal string ``{{VERSION}}`` inside the result;
  Stata's ``stamp_file()`` substitutes that at build time.
- ``sthlp_apa_versioned`` is the same, wrapped in Stata help markup
  ({it:...}, {browse ...}).
- ``ado_cite_block`` emits the full multi-line ``di as text "..."`` block used
  in the Stata ``.ado`` files (registream cite / autolabel cite / datamirror
  cite). The version inside that block references the Stata local
  ``REGISTREAM_VERSION`` which is resolved at Stata runtime, not build.
- ``bibtex`` is versionless plain text; ``bibtex_versioned`` includes a
  ``version = {{{{VERSION}}}}`` line for the Stata build pipeline.
- Python packages consume a generated ``_citation_data.py`` file; the
  hand-maintained ``citation.py`` formats it with ``importlib.metadata.version``
  at runtime.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml

SCRIPT_DIR = Path(__file__).parent.resolve()
CORE_REPO = SCRIPT_DIR.parent                    # ~/Github/registream-org/registream
ORG_ROOT = CORE_REPO.parent                      # ~/Github/registream-org
YAML_PATH = CORE_REPO / "citations.yaml"


def load(path: Path = YAML_PATH) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def _authors_apa(work: dict) -> str:
    parts = [f"{a['family']}, {a['given']}" for a in work["authors"]]
    if len(parts) == 1:
        return parts[0]
    return " & ".join([", ".join(parts[:-1]), parts[-1]]) if len(parts) > 2 else " & ".join(parts)


def _authors_bibtex(work: dict) -> str:
    return " and ".join(a["full"] for a in work["authors"])


def apa(key: str, works: dict) -> str:
    w = works[key]
    return f"{_authors_apa(w)} ({w['year']}). {w['title']}. {w['url']}"


def apa_versioned(key: str, works: dict) -> str:
    """APA with (Version {{VERSION}}) — build-time placeholder for Stata/Python."""
    w = works[key]
    return (
        f"{_authors_apa(w)} ({w['year']}). {w['title']} "
        f"(Version {{{{VERSION}}}}). Available at: {w['url']}."
    )


def sthlp_apa_versioned(key: str, works: dict) -> str:
    """Stata .sthlp help-file markup: italics on title, {browse} on URL."""
    w = works[key]
    return (
        f"{_authors_apa(w)} ({w['year']}). {{it:{w['title']}}} "
        f'(Version {{{{VERSION}}}}). Available at: {{browse "{w["url"]}"}}.'
    )


def html_apa(key: str, works: dict) -> str:
    w = works[key]
    return (
        f"{_authors_apa(w)} ({w['year']}). <em>{w['title']}</em>. "
        f'Available at: <a href="{w["url"]}" target="_blank">{w["url"]}</a>'
    )


def plain_apa(key: str, works: dict) -> str:
    return apa(key, works)


# ─── Journal-article renderers ────────────────────────────────────────────────
# Parallel to the software renderers above. Used for works with
# ``type: journal_article``. Volume / issue / pages may be missing while a
# paper is forthcoming or in preparation; the renderers degrade gracefully.

def _article_locator(w: dict) -> str:
    """Return ', Vol(Iss), pages' if all three are present, '' otherwise."""
    vol = w.get("volume", "")
    iss = w.get("issue", "")
    pages = w.get("pages", "")
    if vol and iss and pages:
        return f", {vol}({iss}), {pages}"
    return ""


def _article_doi_url(w: dict) -> str:
    doi = w.get("doi", "")
    if doi:
        return f"https://doi.org/{doi}"
    return w.get("url", "")


def apa_article(key: str, works: dict) -> str:
    w = works[key]
    locator = _article_locator(w)
    venue = w.get("venue", "")
    tail = f"{venue}{locator}." if venue else ""
    doi_url = _article_doi_url(w)
    doi_tail = f" {doi_url}" if doi_url else ""
    return f"{_authors_apa(w)} ({w['year']}). {w['title']}. {tail}{doi_tail}".strip()


def html_apa_article(key: str, works: dict) -> str:
    w = works[key]
    locator = _article_locator(w)
    venue = w.get("venue", "")
    tail = f"<em>{venue}</em>{locator}." if venue else ""
    doi_url = _article_doi_url(w)
    doi_tail = (
        f' <a href="{doi_url}" target="_blank">{doi_url}</a>' if doi_url else ""
    )
    return f"{_authors_apa(w)} ({w['year']}). {w['title']}. {tail}{doi_tail}".strip()


def bibtex_article(key: str, works: dict) -> str:
    w = works[key]
    lines = [
        f"@{w['bibtex_type']}{{{w['bibtex_key']},",
        f"  author  = {{{_authors_bibtex(w)}}},",
        f"  title   = {{{{{w['title']}}}}},",
    ]
    if w.get("venue"):
        lines.append(f"  journal = {{{w['venue']}}},")
    lines.append(f"  year    = {{{w['year']}}},")
    if w.get("volume"):
        lines.append(f"  volume  = {{{w['volume']}}},")
    # SJ style omits issue numbers when continuously paginated; emit only
    # when populated (caller's policy choice).
    if w.get("issue"):
        lines.append(f"  number  = {{{w['issue']}}},")
    if w.get("pages"):
        lines.append(f"  pages   = {{{w['pages']}}},")
    if w.get("doi"):
        lines.append(f"  doi     = {{{w['doi']}}}")
    else:
        # Strip trailing comma from last line if no doi
        if lines[-1].endswith(","):
            lines[-1] = lines[-1].rstrip(",")
    lines.append("}")
    return "\n".join(lines)


def bibtex(key: str, works: dict, include_version_placeholder: bool = False) -> str:
    w = works[key]
    lines = [
        f"@{w['bibtex_type']}{{{w['bibtex_key']},",
        f"  author  = {{{_authors_bibtex(w)}}},",
        f"  title   = {{{{{w['title']}}}}},",
    ]
    if include_version_placeholder:
        # BibTeX value braces wrap the {{VERSION}} placeholder → {{{VERSION}}}
        lines.append("  version = {{{VERSION}}},")
    lines.append(f"  year    = {{{w['year'].replace('–', '--')}}},")
    lines.append(f"  url     = {{{w['url']}}}")
    lines.append("}")
    return "\n".join(lines)


def ado_cite_block(key: str, works: dict, version_local: str = "REGISTREAM_VERSION") -> str:
    """Full multi-line Stata `di as text` block for the cite command.

    References a Stata local `version_local` (default ``REGISTREAM_VERSION``)
    for runtime version — does NOT use {{VERSION}} placeholder. The block
    prints both the short and versioned APA form plus the BibTeX entry.
    """
    w = works[key]
    authors = _authors_apa(w)
    bib_authors = _authors_bibtex(w)
    year = w["year"]
    title = w["title"]
    url = w["url"]

    lines = [
        f'\tdi as text "  {authors} ({year}). {title}."',
        f'\tdi as text "  Available at: {url}"',
        '\tdi as text ""',
        '\tdi as text "For version-specific citation (recommended for replicability):"',
        '\tdi as text ""',
        f'\tdi as text "  {authors} ({year}). {title}"',
        f"\tdi as text \"  (Version `{version_local}'). Available at: {url}\"",
        '\tdi as text ""',
        '\tdi as text "BibTeX:"',
        '\tdi as text "{hline 60}"',
        f'\tdi as text "@{w["bibtex_type"]}{{{w["bibtex_key"]},"',
        f'\tdi as text "  author  = {{{bib_authors}}},"',
        f'\tdi as text "  title   = {{{{{title}}}}},"',
        f"\tdi as text \"  version = {{`{version_local}'}},\"",
        f'\tdi as text "  year    = {{{year.replace("–", "--")}}},"',
        f'\tdi as text "  url     = {{{url}}}"',
        '\tdi as text "}"',
        '\tdi as text "{hline 60}"',
    ]
    return "\n".join(lines)


def cff(key: str, works: dict) -> str:
    """Citation File Format (CFF) — GitHub-recognized YAML block."""
    w = works[key]
    year_first = w["year"].split("–")[0].strip()
    lines = [
        "cff-version: 1.2.0",
        'message: "If you use this software, please cite it as below."',
        f'title: "{w["title"]}"',
        "authors:",
    ]
    for a in w["authors"]:
        lines.append(f"  - family-names: {a['family']}")
        lines.append(f'    given-names: "{a["given"]}"')
    lines.append(f"year: {year_first}")
    lines.append(f'url: "{w["url"]}"')
    lines.append("type: software")
    return "\n".join(lines) + "\n"


_VERSION_LOCALS = {
    # Per-work Stata local-macro name used inside ado_cite_block.
    # Each ``_<module>_cite`` program receives the stamped version as its
    # first positional argument and peels it into the named local via
    # ``gettoken <NAME> 0 : 0`` so the rendered block's backtick-version
    # reference resolves at runtime.
    "registream": "REGISTREAM_VERSION",
    "autolabel":  "AUTOLABEL_VERSION",
    "datamirror": "DATAMIRROR_VERSION",
}


def as_dict(works: dict) -> dict:
    """Return a dict of {work_key: {variant_name: string}} covering all formats.

    Dispatches on ``work['type']``:
      - "software" (default): uses the software renderers (versioned forms, etc.)
      - "journal_article": uses the article renderers; versioned/sthlp/ado-cite
        variants fall back to the article apa form since articles aren't
        versioned and don't ship inside Stata packages.
    """
    out = {}
    for key in works:
        w = works[key]
        wtype = w.get("type", "software")

        if wtype == "journal_article":
            article_apa = apa_article(key, works)
            article_html = html_apa_article(key, works)
            article_bibtex = bibtex_article(key, works)
            out[key] = {
                "apa": article_apa,
                "apa_versioned": article_apa,
                "sthlp_apa_versioned": article_apa,
                "html_apa": article_html,
                "plain_apa": article_apa,
                "bibtex": article_bibtex,
                "bibtex_versioned": article_bibtex,
                "ado_cite_block": "",
                "cff": cff(key, works),
                "title": w["title"],
                "short_title": w.get("short_title", w["title"]),
                "url": _article_doi_url(w),
                "year": w["year"],
                "bibtex_key": w["bibtex_key"],
            }
        else:
            out[key] = {
                "apa": apa(key, works),
                "apa_versioned": apa_versioned(key, works),
                "sthlp_apa_versioned": sthlp_apa_versioned(key, works),
                "html_apa": html_apa(key, works),
                "plain_apa": plain_apa(key, works),
                "bibtex": bibtex(key, works),
                "bibtex_versioned": bibtex(key, works, include_version_placeholder=True),
                "ado_cite_block": ado_cite_block(
                    key, works, version_local=_VERSION_LOCALS.get(key, "VERSION")
                ),
                "cff": cff(key, works),
                "title": w["title"],
                "short_title": w["short_title"],
                "url": w["url"],
                "year": w["year"],
                "bibtex_key": w["bibtex_key"],
            }
    return out


# ─── Placeholder substitution for text files ──────────────────────────────────

def substitute(content: str, works: dict) -> str:
    """Replace all {{CITATION_<KEY>_<VARIANT>}} tokens in ``content``.

    Tokens are uppercase, e.g. {{CITATION_REGISTREAM_STHLP_APA_VERSIONED}},
    {{CITATION_AUTOLABEL_BIBTEX}}, {{CITATION_DATAMIRROR_ADO_CITE_BLOCK}}.

    The existing {{VERSION}}, {{DATE}}, {{STHLP_DATE}} placeholders are NOT
    touched here — that's the Stata build script's job in a separate pass.
    """
    d = as_dict(works)
    for work_key, variants in d.items():
        for variant_name, variant_value in variants.items():
            token = f"{{{{CITATION_{work_key.upper()}_{variant_name.upper()}}}}}"
            content = content.replace(token, str(variant_value))
    return content


# ─── CLI actions ──────────────────────────────────────────────────────────────

def _cmd_check(works: dict) -> None:
    d = as_dict(works)
    for key, variants in d.items():
        print(f"━━━ {key} ━━━")
        for name, val in variants.items():
            print(f"  ▸ {name}:")
            for line in str(val).splitlines() or [""]:
                print(f"      {line}")
        print()
    print(f"OK — {len(d)} work(s) rendered.")


_PY_HEADER = '''\
"""Generated by registream/tools/render_citations.py — DO NOT EDIT BY HAND.

Edit registream/citations.yaml, then run `python tools/render_citations.py write-python`.
"""

from __future__ import annotations

'''


def _cmd_write_python(works: dict) -> None:
    """Emit _citation_data.py into both Python packages."""
    d = as_dict(works)

    def render_module(work_key: str) -> str:
        w = d[work_key]
        # Preserve {version} format slot for runtime substitution
        apa_tmpl = w["apa"]
        apa_v_tmpl = w["apa_versioned"].replace("{{VERSION}}", "{version}")
        # BibTeX has its own `{...}` braces — str.format() can't parse it. Keep
        # the {{VERSION}} token literal; consumers use str.replace() instead.
        bib_v_tmpl = w["bibtex_versioned"]
        bib_plain = w["bibtex"]
        return (
            _PY_HEADER
            + f"WORK_KEY = {work_key!r}\n"
            + f"TITLE = {w['title']!r}\n"
            + f"SHORT_TITLE = {w['short_title']!r}\n"
            + f"URL = {w['url']!r}\n"
            + f"YEAR = {w['year']!r}\n"
            + f"BIBTEX_KEY = {w['bibtex_key']!r}\n"
            + f"AUTHORS_APA = {w['apa'].split(' (')[0]!r}\n"
            + "\n"
            + f"APA = {apa_tmpl!r}\n"
            + f"APA_VERSIONED_TEMPLATE = {apa_v_tmpl!r}\n"
            + f"BIBTEX_PLAIN = {bib_plain!r}\n"
            + f"BIBTEX_VERSIONED_TEMPLATE = {bib_v_tmpl!r}\n"
        )

    targets = [
        (
            "registream",
            CORE_REPO / "python" / "registream-core" / "src" / "registream" / "_citation_data.py",
        ),
        (
            "autolabel",
            ORG_ROOT / "autolabel" / "python" / "registream-autolabel" / "src" / "registream" / "autolabel" / "_citation_data.py",
        ),
    ]
    for work_key, path in targets:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(render_module(work_key), encoding="utf-8")
        print(f"  wrote {path.relative_to(ORG_ROOT)}")


_R_HEADER = '''\
# Generated by registream/tools/render_citations.py -- DO NOT EDIT BY HAND.
#
# Edit registream/citations.yaml, then run
#   python tools/render_citations.py write-r
# from the registream/ repo root.

'''


def _r_string(s: str) -> str:
    """Emit a double-quoted R string literal.

    Escapes backslash, double-quote, and newline. ALL non-ASCII
    characters are emitted as ``\\uXXXX`` escapes so the generated R
    source stays ASCII-clean — CRAN's portability check requires this
    ("Portable packages must use only ASCII characters in their R
    code").
    """
    out = []
    for ch in s:
        code = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif code < 0x80:
            out.append(ch)
        elif code <= 0xFFFF:
            out.append(f"\\u{code:04x}")
        else:
            out.append(f"\\U{code:08x}")
    return '"' + "".join(out) + '"'


def _cmd_write_r(works: dict) -> None:
    """Emit _citation_data.R into both R packages."""
    d = as_dict(works)

    def render_module(work_key: str) -> str:
        w = d[work_key]
        # R consumers use sprintf("%s", version), so swap {{VERSION}}/{version}
        # for %s in the APA template. BibTeX keeps {{VERSION}} as a literal
        # token users substitute via gsub(..., fixed = TRUE).
        apa_v_tmpl = w["apa_versioned"].replace("{{VERSION}}", "%s")
        bib_v_tmpl = w["bibtex_versioned"]
        authors_apa = w["apa"].split(" (")[0]
        return (
            _R_HEADER
            + f".CITATION_WORK_KEY    <- {_r_string(work_key)}\n"
            + f".CITATION_TITLE       <- {_r_string(w['title'])}\n"
            + f".CITATION_SHORT_TITLE <- {_r_string(w['short_title'])}\n"
            + f".CITATION_URL         <- {_r_string(w['url'])}\n"
            + f".CITATION_YEAR        <- {_r_string(w['year'])}\n"
            + f".CITATION_BIBTEX_KEY  <- {_r_string(w['bibtex_key'])}\n"
            + f".CITATION_AUTHORS_APA <- {_r_string(authors_apa)}\n"
            + "\n"
            + f".CITATION_APA                      <- {_r_string(w['apa'])}\n"
            + f".CITATION_APA_VERSIONED_TEMPLATE   <- {_r_string(apa_v_tmpl)}\n"
            + f".CITATION_BIBTEX_PLAIN             <- {_r_string(w['bibtex'])}\n"
            + f".CITATION_BIBTEX_VERSIONED_TEMPLATE <- {_r_string(bib_v_tmpl)}\n"
        )

    targets = [
        (
            "registream",
            CORE_REPO / "r" / "R" / "citation_data.R",
        ),
        (
            "autolabel",
            ORG_ROOT / "autolabel" / "r" / "R" / "citation_data.R",
        ),
    ]
    for work_key, path in targets:
        if not path.parent.exists():
            print(f"  skip {work_key}: {path.parent} missing")
            continue
        path.write_text(render_module(work_key), encoding="utf-8")
        print(f"  wrote {path.relative_to(ORG_ROOT)}")


def _cmd_write_flask(works: dict) -> None:
    """Emit the pre-rendered citations JSON into the Flask app tree.

    The Flask app consumes ``app/_citations.json`` — a ``{work_key: {variant:
    string, ...}}`` dict produced by :func:`as_dict`. No re-rendering
    happens in Flask; the rendering logic lives here in one place.

    A commented vendored copy of the source YAML is also written alongside
    as a human-readable reference (not loaded at runtime).
    """
    import json

    app_dir = ORG_ROOT / "registream-website" / "app"
    app_dir.mkdir(parents=True, exist_ok=True)

    json_dst = app_dir / "_citations.json"
    payload = {
        "_generated_by": "registream/tools/render_citations.py write-flask",
        "_source": "registream/citations.yaml",
        "schema_version": 1,
        "works": as_dict(works),
    }
    json_dst.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"  wrote {json_dst.relative_to(ORG_ROOT)}")

    yaml_dst = app_dir / "_citations.yaml"
    header = (
        "# GENERATED — human-readable copy of registream/citations.yaml.\n"
        "# Flask loads _citations.json (pre-rendered); this file is for reference.\n"
        "# DO NOT EDIT. Run `python tools/render_citations.py write-flask` to refresh.\n"
    )
    yaml_dst.write_text(
        header + YAML_PATH.read_text(encoding="utf-8"), encoding="utf-8"
    )
    print(f"  wrote {yaml_dst.relative_to(ORG_ROOT)}")


def _cmd_write_cff(works: dict) -> None:
    """Write CITATION.cff into each repo root."""
    d = as_dict(works)
    targets = {
        "registream": CORE_REPO / "CITATION.cff",
        "autolabel":  ORG_ROOT / "autolabel" / "CITATION.cff",
        "datamirror": ORG_ROOT / "datamirror" / "CITATION.cff",
    }
    for work_key, path in targets.items():
        if not path.parent.exists():
            print(f"  skip {work_key}: {path.parent} missing")
            continue
        path.write_text(d[work_key]["cff"], encoding="utf-8")
        print(f"  wrote {path.relative_to(ORG_ROOT)}")


def main() -> int:
    p = argparse.ArgumentParser(description="Render citations from citations.yaml.")
    p.add_argument(
        "command",
        choices=["check", "write-python", "write-r", "write-flask", "write-cff", "write-all"],
    )
    args = p.parse_args()

    data = load()
    works = data.get("works", {})
    if not works:
        print("citations.yaml has no `works:` section", file=sys.stderr)
        return 2

    if args.command in ("check", "write-all"):
        _cmd_check(works)
    if args.command in ("write-python", "write-all"):
        _cmd_write_python(works)
    if args.command in ("write-r", "write-all"):
        _cmd_write_r(works)
    if args.command in ("write-flask", "write-all"):
        _cmd_write_flask(works)
    if args.command in ("write-cff", "write-all"):
        _cmd_write_cff(works)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
