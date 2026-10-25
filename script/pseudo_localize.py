#!/usr/bin/env python3
"""Write a copy of a string catalog with an en-XA pseudo-language added.

Usage: script/pseudo_localize.py <in.xcstrings> <out.xcstrings>

Every string becomes accented, bracketed and about 30% longer, with its format
specifiers kept (and numbered, as a translation's would be): "Pair with %@"
becomes "[Þàîŕ ŵîţĥ %1$@···]". Run in en-XA, anything still plain English
skipped localization, and anything cut off or overflowing will be in German
too. package_app.sh --pseudo compiles the result into the app; the catalogs in
the repository are never touched.
"""

import json
import re
import sys

ACCENTED = dict(
    zip(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
        "àƀçđéƒĝĥîĵķļɱñöþǫŕšţûṽŵẋýžÅƁÇĐÉƑĜĤÎĴĶĻṀÑÖÞǪŔŠŢÛṼŴẊÝŽ",
    )
)
SPECIFIER = re.compile(r"%(\d+\$)?(@|lld|ld|d|f|%)")


def numbered(text):
    if "$" in text:
        return text
    position = iter(range(1, 100))
    return SPECIFIER.sub(
        lambda m: m.group(0) if m.group(2) == "%" else f"%{next(position)}${m.group(2)}", text
    )


def pseudo(text):
    pieces, start = [], 0
    for match in SPECIFIER.finditer(text):
        pieces.append("".join(ACCENTED.get(c, c) for c in text[start : match.start()]))
        pieces.append(match.group(0))
        start = match.end()
    pieces.append("".join(ACCENTED.get(c, c) for c in text[start:]))
    return "[" + "".join(pieces) + "·" * max(1, len(text) * 3 // 10) + "]"


def main(source, destination):
    with open(source, encoding="utf-8") as file:
        catalog = json.load(file)
    for key, entry in catalog["strings"].items():
        if entry.get("shouldTranslate") is False:
            continue
        english = entry.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value", key)
        localizations = entry.setdefault("localizations", {})
        localizations["en-XA"] = {"stringUnit": {"state": "translated", "value": pseudo(numbered(english))}}
    with open(destination, "w", encoding="utf-8") as file:
        json.dump(catalog, file, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[2])
    main(sys.argv[1], sys.argv[2])
