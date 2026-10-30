#!/usr/bin/env python3
"""Validate the SP11 documentation against the standard in SKILL.md. Run from the repository root.

Checks: line length (116, outside fenced code and table rows), line endings and whitespace, relative markdown
links, backticked document paths and cited section names (in docs, CLAUDE.md, README.md, the skills, the scripts,
the spec templates, sp11.conf and sp11-diag), orphans (guides not linked from README.md, notes not indexed in
docs/README.md), duplicate headings, heading-level jumps, doubled words, and the per-unit-identifier grep.
Exits 1 when it finds anything."""
import collections
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path('.')
DOCS = [ROOT / 'README.md', ROOT / 'CLAUDE.md', *sorted((ROOT / 'docs').rglob('*.md'))]
CITING = [*DOCS, *sorted((ROOT / '.claude/skills').rglob('*.md')), *sorted((ROOT / 'scripts').glob('*')),
          *sorted((ROOT / 'rpm').glob('*')), ROOT / 'sp11.conf', ROOT / 'payload/sp11-diag']
findings = []


def finding(msg):
    findings.append(msg)
    print(msg)


def text(p):
    try:
        return p.read_text()
    except (UnicodeDecodeError, OSError):
        return ''


# 1. line length, endings, whitespace
for f in DOCS:
    raw = f.read_bytes()
    if b'\r' in raw:
        finding(f'{f}: CRLF line ending')
    if b'\t' in raw:
        finding(f'{f}: tab character')
    if raw and not raw.endswith(b'\n'):
        finding(f'{f}: no final newline')
    code = False
    for i, line in enumerate(raw.decode().split('\n'), 1):
        if line.startswith('```'):
            code = not code
            continue
        if line != line.rstrip():
            finding(f'{f}:{i}: trailing whitespace')
        if not code and len(line) > 116 and not line.startswith('|'):
            finding(f'{f}:{i}: {len(line)} columns')

# 2. relative markdown links
for f in [ROOT / 'README.md', ROOT / 'docs/README.md', *sorted((ROOT / 'docs/guide').glob('*.md'))]:
    for m in re.finditer(r'\]\(([^)]+)\)', text(f)):
        target = m.group(1)
        if target.startswith('http'):
            continue
        path, _, _anchor = target.partition('#')
        if path and not (f.parent / path).exists():
            finding(f'{f}: broken link {target}')

# 3. document paths and cited sections
heading_cache = {}


def has_heading(doc, section):
    if doc not in heading_cache:
        heading_cache[doc] = text(doc)
    return re.search(r'^#+ .*' + re.escape(section), heading_cache[doc], re.M) is not None


for f in CITING:
    for m in re.finditer(r'(docs/[a-z/-]+\.md)`?(?:\]\([^)]*\))?(?:, ([A-Z][A-Za-z -]+))?(?=[\s\.\);,:`]|$)', text(f)):
        doc = ROOT / m.group(1)
        if not doc.exists():
            finding(f'{f}: cites missing document {m.group(1)}')
            continue
        section = (m.group(2) or '').strip()
        if section and not has_heading(doc, section):
            finding(f'{f}: cites {m.group(1)}, {section}: no such heading')

# 4. orphans
readme = text(ROOT / 'README.md')
for g in sorted((ROOT / 'docs/guide').glob('*.md')):
    if f'({g.as_posix()})' not in readme:
        finding(f'{g}: guide not linked from README.md')
index = text(ROOT / 'docs/README.md')
for n in sorted((ROOT / 'docs').glob('*.md')):
    if n.name != 'README.md' and f'`{n.as_posix()}`' not in index:
        finding(f'{n}: note not indexed in docs/README.md')

# 5. headings and doubled words
for f in DOCS:
    heads = [l.strip() for l in text(f).splitlines() if l.startswith('#')]
    for h, n in collections.Counter(heads).items():
        if n > 1:
            finding(f'{f}: duplicate heading {h!r}')
    prev = 1
    for i, l in enumerate(text(f).splitlines(), 1):
        m = re.match(r'^(#+) ', l)
        if m:
            level = len(m.group(1))
            if level > prev + 1:
                finding(f'{f}:{i}: heading level jumps from {prev} to {level}')
            prev = level
        for w in re.finditer(r'\b([a-z]+) \1\b', l):
            finding(f'{f}:{i}: doubled word {w.group(0)!r}')

# 6. per-unit identifiers
mac = subprocess.run(['git', 'grep', '-nE', r'([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}'], capture_output=True, text=True)
for line in mac.stdout.splitlines():
    if 'AA:BB:CC:DD:EE:FF' not in line:
        finding(f'per-unit address in a tracked file: {line}')

words = sum(len(text(f).split()) for f in DOCS)
print(f'{len(DOCS)} files, {words} words, {len(findings)} finding(s)')
sys.exit(1 if findings else 0)
