#!/usr/bin/env python3
"""Check every catalog service has an atlas cell; run during the app build."""
import json
import re
import struct
from pathlib import Path

root = Path(__file__).resolve().parent.parent
catalog = root / 'Sources/CooltimeCore'
entries = []
for name in ('Catalog.swift', 'ManualCatalog.swift'):
    entries += re.findall(r'ServiceDef\(id: "([^"]+)", name: "([^"]+)"', (catalog / name).read_text())
manifest = json.loads((root / 'docs/service-icons.json').read_text())
ids = [row['id'] for row in manifest]
assert len(ids) == len(set(ids)), 'Duplicate icon IDs'
assert ids == [id for id, _ in entries], 'Icon manifest must cover catalog in order'
assert all(row['index'] == i for i, row in enumerate(manifest)), 'Icon indices must be contiguous'
assert all(row['source'] in ('lobe', 'simple', 'monogram') for row in manifest)
source = (root / 'Sources/Cooltime/ServiceIconCatalog.swift').read_text()
indices = dict((id, int(index)) for id, index in re.findall(r'"([^"]+)": (\d+),', source))
assert indices == {row['id']: row['index'] for row in manifest}, 'Swift indices differ from manifest'
image = (root / 'Sources/Cooltime/Resources/ServiceIcons.png').read_bytes()
assert image[:8] == b'\x89PNG\r\n\x1a\n', 'Invalid PNG'
width, height = struct.unpack('>II', image[16:24])
assert width == 12 * 72 and height == ((len(entries) + 11) // 12) * 72, 'Atlas dimensions differ'
print(f'Icon coverage: {len(entries)}/{len(entries)}; branded: {sum(x["source"] != "monogram" for x in manifest)}; monogram: {sum(x["source"] == "monogram" for x in manifest)}')
