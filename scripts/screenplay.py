#!/usr/bin/env python3
"""Build and check THE EXACT ONE screenplay from its saved Drive export.

    python3 scripts/screenplay.py build   # write screenplay.md and the .fountain file
    python3 scripts/screenplay.py pdf     # render the .fountain file to PDF (needs: pip install 'screenplain[PDF]')
    python3 scripts/screenplay.py check   # fail if the outputs drift from the source or break the script's own rules
"""

import hashlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FILM = ROOT / "docs" / "drop-assassin" / "the-exact-one"
SOURCE = FILM / "source" / "revision-3-drive-export.md"
SCREENPLAY = FILM / "screenplay.md"
FOUNTAIN = FILM / "the-exact-one.fountain"
PDF = FILM / "the-exact-one.pdf"

# Drive file 1lIwBBMKfuQhy6v8jS_s9tazWTt2bXhPN, modified 2026-11-13T01:44:00Z, 20320 bytes.
SOURCE_SHA256 = "aee8baae1938b35adb979d3a1a5dc0116db6ae1ef38cab31aa7263aaa736c606"

HEADINGS = {n: "INT. ALEX'S APARTMENT - NIGHT" for n in range(1, 8)}
HEADINGS[8] = "INT. ALEX'S APARTMENT - NEXT EVENING"

TIMING = re.compile(r"^\*\*(\d+):(\d\d)–(\d+):(\d\d)\.\*\*\s*(.*)$")
SCENE = re.compile(r"^## SCENE (\d+) — (.+)$")
DIALOGUE = re.compile(r"^> \*\*([A-Z ]+):\*\*\s*(.*)$")
PAREN = re.compile(r"\*\(([^)]*)\)\*")
PLATE_PREFIX = re.compile(r"^(Button|Buttons|Caption|Footer|Columns):\s*")
CURRENCY = re.compile(r"[$€£¥]")


def source_text():
    return SOURCE.read_text(encoding="utf-8")


def screenplay_body(src):
    start = src.index("# THE EXACT ONE\n")
    end = src.index("## REVISION 3 CHANGES, FOR RESEARCH TO CHECK")
    return src[start:end].rstrip() + "\n"


def section(body, title):
    m = re.search(rf"^## {re.escape(title)}\n(.*?)(?=^## |\Z)", body, re.S | re.M)
    return m.group(1) if m else ""


def parse_scenes(body):
    """Return the opening card and scenes as lists of (kind, payload) blocks."""
    blocks, current = [], None
    lines = body.split("\n")
    i = 0
    in_film = False
    while i < len(lines):
        line = lines[i]
        if line == "## OPENING CARD":
            in_film = True
            current = {"number": 0, "title": "OPENING CARD", "blocks": []}
            blocks.append(current)
        elif line.startswith("## COPY DECK"):
            break
        elif in_film and (m := SCENE.match(line)):
            current = {"number": int(m.group(1)), "title": m.group(2), "blocks": []}
            blocks.append(current)
        elif in_film and line.strip():
            if m := TIMING.match(line):
                current["start"] = int(m.group(1)) * 60 + int(m.group(2))
                current["end"] = int(m.group(3)) * 60 + int(m.group(4))
                if m.group(5):
                    current["blocks"].append(("action", m.group(5)))
            elif m := DIALOGUE.match(line):
                current["blocks"].append(("dialogue", (m.group(1), m.group(2))))
            elif line.startswith(">"):
                plate = []
                while i < len(lines) and lines[i].startswith(">") and not DIALOGUE.match(lines[i]):
                    plate.append(lines[i][1:].strip())
                    i += 1
                current["blocks"].append(("plate", plate))
                continue
            elif line.startswith("- "):
                current["blocks"].append(("item", line[2:]))
            else:
                current["blocks"].append(("action", line))
        i += 1
    return blocks


def dialogue_parts(text):
    """Split '*(beat)*'-style asides out of a spoken line, keeping their order."""
    parts, pos = [], 0
    for m in PAREN.finditer(text):
        if text[pos:m.start()].strip():
            parts.append(("line", text[pos:m.start()].strip()))
        parts.append(("paren", m.group(1).strip()))
        pos = m.end()
    if text[pos:].strip():
        parts.append(("line", text[pos:].strip()))
    return parts


def fmt_time(seconds):
    return f"{seconds // 60}:{seconds % 60:02d}"


def to_fountain(body):
    title_line = "THE EXACT ONE"
    status = body.split("\n")[1].strip()
    out = [
        f"Title: {title_line}",
        "Credit: Written by",
        "Author: Brandon Bradshaw",
        "Source: A concept film for Drop Assassin",
        "Draft date: Revision 3, 2026-11-13. Unapproved draft.",
        f"Notes: {status}",
        "",
    ]
    for scene in parse_scenes(body):
        span = f"{fmt_time(scene['start'])}–{fmt_time(scene['end'])}"
        if scene["number"] == 0:
            out += [f"!OPENING CARD ({span})", ""]
        else:
            if scene["number"] == 8:
                out += ["DISSOLVE TO:", ""]
            out += [
                f".{HEADINGS[scene['number']]} #{scene['number']}#",
                "",
                f"= {span} · {scene['title']}",
                "",
            ]
        centred = scene["number"] == 0
        items = []
        for kind, payload in scene["blocks"]:
            if kind != "item" and items:
                out += ["!" + "\n".join(items), ""]
                items = []
            if kind == "action":
                if payload.startswith("End card"):
                    centred = True
                out += ["!" + payload, ""]
            elif kind == "item":
                items.append("    " + payload)
            elif kind == "plate":
                if centred:
                    out += ["\n".join(f"> {p} <" for p in payload), ""]
                else:
                    out += ["!" + "\n".join("    " + p for p in payload), ""]
            elif kind == "dialogue":
                name, text = payload
                lines = [name]
                for part, value in dialogue_parts(text):
                    lines.append(f"({value})" if part == "paren" else value)
                out += ["\n".join(lines), ""]
        if items:
            out += ["!" + "\n".join(items), ""]
    return "\n".join(out).rstrip() + "\n"


def build():
    body = screenplay_body(source_text())
    SCREENPLAY.write_text(body, encoding="utf-8")
    FOUNTAIN.write_text(to_fountain(body), encoding="utf-8")
    print(f"wrote {SCREENPLAY.relative_to(ROOT)}")
    print(f"wrote {FOUNTAIN.relative_to(ROOT)}")


def pdf():
    subprocess.run([sys.executable, "-m", "screenplain.main", "-f", "pdf", str(FOUNTAIN), str(PDF)], check=True)
    print(f"wrote {PDF.relative_to(ROOT)}")


def on_screen_strings(scenes):
    strings = []
    for scene in scenes:
        for kind, payload in scene["blocks"]:
            lines = []
            if kind == "plate":
                lines = payload
            elif kind == "item" and scene["number"] == 4:
                lines = [payload]
            elif kind == "action" and payload.startswith("Columns:"):
                lines = [payload]
            for line in lines:
                line = PLATE_PREFIX.sub("", line.replace("*", ""))
                strings += [piece.strip() for piece in line.split(" · ") if piece.strip()]
    return strings


def check():
    failures = []

    def expect(ok, message):
        print(("ok    " if ok else "FAIL  ") + message)
        if not ok:
            failures.append(message)

    raw = SOURCE.read_bytes()
    expect(hashlib.sha256(raw).hexdigest() == SOURCE_SHA256, "source export matches the recorded Drive hash")
    src = raw.decode("utf-8")
    body = screenplay_body(src)

    expect(SCREENPLAY.read_text(encoding="utf-8") == body, "screenplay.md is the unedited revision 3 text")
    expect(FOUNTAIN.read_text(encoding="utf-8") == to_fountain(body), "the .fountain file is current with the source")

    scenes = parse_scenes(body)
    expect([s["number"] for s in scenes] == list(range(9)), "opening card plus scenes 1 to 8, in order")
    expect(all("start" in s for s in scenes), "every scene has a timing line")
    clock = 0
    for s in scenes:
        expect(s.get("start") == clock and s.get("end", 0) > clock,
               f"{s['title']} runs {fmt_time(s.get('start', 0))}–{fmt_time(s.get('end', 0))} with no gap or overlap")
        clock = s.get("end", clock)
    runtime = int(re.search(r"^RUNTIME_SECONDS: (\d+)$", src, re.M).group(1))
    expect(clock == runtime, f"scene timings end at {fmt_time(clock)}, matching RUNTIME_SECONDS {runtime}")
    expect(f"runtime is {fmt_time(runtime)}" in body, f"the stated runtime is {fmt_time(runtime)}")

    deck = section(body, "COPY DECK")
    spoken = re.search(r"\*\*Spoken lines, in order:\*\* (.*)", deck).group(1).strip()
    lines_said = [value for s in scenes for kind, payload in s["blocks"] if kind == "dialogue"
                  for part, value in dialogue_parts(payload[1]) if part == "line"]
    said = " ".join(lines_said)
    expect(said == spoken, "spoken lines match the copy deck word for word and in order")
    expect({payload[0] for s in scenes for kind, payload in s["blocks"] if kind == "dialogue"} == {"ALEX"},
           "Alex is the only speaking part")

    strings = on_screen_strings(scenes)
    missing = sorted({s for s in strings if s not in deck})
    expect(not missing, f"all {len(strings)} on-screen strings come from the copy deck"
           + (f" (missing: {missing})" if missing else ""))
    expect(not any(CURRENCY.search(s) for s in strings), "no currency symbol on any plate")

    fountain = FOUNTAIN.read_text(encoding="utf-8")
    absent = sorted({s for s in strings if s not in fountain})
    expect(not absent, "every on-screen string survives into the .fountain file"
           + (f" (missing: {absent})" if absent else ""))
    expect(all(f"#{n}#" in fountain for n in range(1, 9)), "the .fountain file numbers all eight scenes")

    try:
        import pymupdf
    except ImportError:
        print("skip  PDF text check (pip install pymupdf to run it)")
    else:
        with pymupdf.open(PDF) as doc:
            text = re.sub(r"\s+", " ", " ".join(page.get_text() for page in doc))
            pages = doc.page_count
        lost = sorted({s for s in strings + lines_said if re.sub(r"\s+", " ", s) not in text})
        expect(not lost, f"the PDF ({pages} pages) carries every spoken line and on-screen string"
               + (f" (missing: {lost})" if lost else ""))
        expect("Unapproved draft" in text, "the PDF title page says it is an unapproved draft")

    print(f"\n{'FAILED' if failures else 'PASSED'}: {len(failures)} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else "check"
    if command == "build":
        build()
    elif command == "pdf":
        pdf()
    elif command == "check":
        sys.exit(check())
    else:
        sys.exit(__doc__)
