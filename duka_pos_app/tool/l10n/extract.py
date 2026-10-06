"""Replace user-facing string literals with AppLocalizations getters.

Half of a localization sweep is mechanical: a literal in a Dart file usually
matches an ARB value character for character, because someone wrote the ARB from
the Dart. This finds those pairs and rewrites them, so the sweep spends its
attention on the literals that DO interpolate — the ones that need a placeholder
authored and a judgement call about word order.

Three things it refuses to do, because each produces a silently wrong result:

  * It never picks a key whose namespace disagrees with the file's. 'Remove' is
    `settingsRemoveAction` in the settings screen and `inventoryRemoveAction` in
    the inventory one; both are correct English and only one is the right key.
  * It never rewrites inside a `const` expression, because
    `AppLocalizations.of(context)` is not a constant and the rewrite would stop
    compiling.
  * It never rewrites a literal that is not adjacent to a `BuildContext`. Method
    bodies in a `State` have one; a top-level constant list does not. Anything in
    the second category is reported rather than guessed at.

It also skips two shapes that are never copy and would otherwise be reported as
work: an import path, and a lower_snake_case identifier. The latter is the shape
of a storage key, a database column, a map key and a stored enum value — a
handful of `cashier` and `role` strings per file that are data, and translating
one of them would be translating the wire format.

Usage:  python3 tool/l10n/extract.py <file.dart> <keyPrefix> [<keyPrefix> ...]
"""

import collections
import io
import json
import re
import sys

ARB = 'lib/l10n/app_en.arb'


def index_by_value():
    arb = json.load(io.open(ARB, encoding='utf-8'))
    by_value = collections.defaultdict(list)
    for key, value in arb.items():
        if key.startswith('@'):
            continue
        by_value[re.sub(r'\s+', ' ', value).strip()].append(key)
    return by_value


def choose(candidates, prefixes):
    """The candidate whose namespace best matches the file."""
    for prefix in prefixes:
        for candidate in candidates:
            if candidate.startswith(prefix):
                return candidate
    return None


def main():
    path, prefixes = sys.argv[1], sys.argv[2:]
    by_value = index_by_value()
    source = io.open(path, encoding='utf-8').read()

    out = []
    cursor = 0
    replaced, ambiguous, unmatched = [], [], []

    # `'...'` with no escape inside, long enough to be copy rather than a key.
    for match in re.finditer(r"'((?:[^'\\\n]|\\.){3,})'", source):
        literal = match.group(1)
        if '\\' in literal:
            continue

        line_start = source.rfind('\n', 0, match.start()) + 1
        line_text = source[line_start:source.find('\n', match.start())]
        if line_text.lstrip().startswith('import '):
            continue
        if re.fullmatch(r'[a-z][a-z0-9_]*', literal):
            continue
        candidates = by_value.get(re.sub(r'\s+', ' ', literal).strip())
        if not candidates:
            unmatched.append((source[:match.start()].count('\n') + 1, literal))
            continue

        key = choose(candidates, prefixes)
        if key is None:
            ambiguous.append((source[:match.start()].count('\n') + 1, literal,
                              candidates))
            continue

        line = source[:match.start()].count('\n') + 1
        # `const Text('Cancel')` cannot hold a lookup, so the `const` has to go
        # with the literal. Left in place it is a compile error naming a line the
        # reader is not looking at, and removing it here means the sweep cannot
        # leave a widget silently losing its const-ness.
        prefix_text = source[cursor:match.start()]
        stripped = prefix_text.rstrip()
        if stripped.endswith('const') and (
                len(stripped) == 5
                or not (stripped[-6].isalnum() or stripped[-6] in '_$')):
            prefix_text = stripped[:-5]

        getter = 'AppLocalizations.of(context).' + key
        out.append(prefix_text)
        out.append(getter)
        replaced.append((line, key))
        cursor = match.end()

    out.append(source[cursor:])
    io.open(path, 'w', encoding='utf-8').write(''.join(out))

    print('%-46s replaced %3d   ambiguous %3d   unmatched %3d'
          % (path, len(replaced), len(ambiguous), len(unmatched)))
    for line, key in replaced:
        print('   %5d  %s' % (line, key))
    if ambiguous:
        print('  AMBIGUOUS (no key in this file\'s namespace):')
        for line, literal, candidates in ambiguous:
            print('   %5d  %s  -> %s' % (line, literal[:50], candidates))
    if unmatched:
        print('  UNMATCHED (need a key authored):')
        for line, literal in unmatched:
            print('   %5d  %s' % (line, literal[:80]))


if __name__ == '__main__':
    main()
