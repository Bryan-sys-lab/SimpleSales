#!/usr/bin/env python3
"""Validate ARB locale files without changing them.

The English catalogue is the schema. A translated catalogue may intentionally
omit a message while it is being completed; gen-l10n falls back to English for
that message. It must not, however, invent keys or change the placeholders a
screen passes at runtime.
"""

import json
import re
import sys
from pathlib import Path


PLACEHOLDER = re.compile(r"\{([A-Za-z][A-Za-z0-9_]*)")


def messages(path):
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    return {key: value for key, value in data.items() if not key.startswith("@")}


def placeholders(value):
    return set(PLACEHOLDER.findall(value))


def main():
    root = Path(__file__).resolve().parents[2]
    l10n = root / "lib" / "l10n"
    template_path = l10n / "app_en.arb"
    template = messages(template_path)
    failures = []
    fallback_counts = []

    for path in sorted(l10n.glob("app_*.arb")):
        if path == template_path:
            continue
        locale = path.stem.removeprefix("app_")
        translated = messages(path)
        extra = sorted(set(translated) - set(template))
        if extra:
            failures.append(f"{locale}: unknown keys: {', '.join(extra)}")
        mismatched = []
        for key in sorted(set(translated) & set(template)):
            if placeholders(translated[key]) != placeholders(template[key]):
                mismatched.append(key)
        if mismatched:
            failures.append(
                f"{locale}: placeholder mismatch: {', '.join(mismatched)}"
            )
        missing = len(set(template) - set(translated))
        fallback_counts.append((locale, missing))

    if failures:
        for failure in failures:
            print(f"ERROR: {failure}", file=sys.stderr)
        return 1

    for locale, missing in fallback_counts:
        suffix = f" ({missing} English fallbacks)" if missing else ""
        print(f"ARB OK: {locale}{suffix}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
