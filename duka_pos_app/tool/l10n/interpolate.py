"""Generate an ARB message from an interpolated Dart literal, and rewrite the call.

The second half of a localization sweep is Dart string interpolation, and every
one of those sites needs the same two things done to it:

  * the interpolation turned into a named ICU placeholder, so the surrounding
    words can be reordered by a translator instead of being frozen in English
    order; and
  * a placeholder name that says what the value IS.

This does that mechanically for the sites that are a plain interpolation inside
one sentence — `'${p.name} is now ${q} in stock.'`. It deliberately refuses to
guess at the sites that are not:

  * a `cond ? 'a' : 'b'` inside the text, because the right answer is usually an
    ICU `plural` rather than a `select`, and only a human can tell which;
  * an expression it cannot name (`$e.id`, a map lookup, a method call), because a
    placeholder called `{v0}` is worse than no placeholder — it tells a translator
    nothing and survives the next refactor under a name that means less.

Both are reported so they get hand-written. Nothing is guessed.

Usage:  python3 tool/l10n/interpolate.py <file.dart> <keyPrefix>
"""

import collections
import io
import json
import os
import re
import sys

ARB = 'lib/l10n/app_en.arb'

# Dart adjacent string literals: `'a' 'b'` and `'a'\n    'b'` concatenate.
LITERAL = re.compile(r"'((?:[^'\\\n]|\\.)*)'")
GAP = re.compile(r'^[ \t\r\n]*$')
INTERP = re.compile(r'\$\{([^}]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)')


def name_for(expression, taken):
    """A placeholder name that says what the value is, not what it was called."""
    text = expression.strip()
    base = None
    simple = re.fullmatch(r'([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)', text)
    if simple:
        attr = simple.group(2)
        owner = simple.group(1)
        # A plural-shaped attribute on a count-shaped owner is a count.
        if re.search(r'(Count|count|Len|length|Total|qty|Qty)$', attr):
            base = attr.lower()
        elif re.fullmatch(r'(name|label|title|code|reference|id)', attr):
            base = attr
        else:
            base = attr[0].lower() + attr[1:]
    elif re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', text):
        base = text[0].lower() + text[1:]
    elif text.startswith('formatMoney('):
        base = 'amount'
    if base is None:
        return None
    base = re.sub(r'[^A-Za-z0-9]', '', base)
    if base in taken:
        suffix = 2
        while '%s%d' % (base, suffix) in taken:
            suffix += 1
        base = '%s%d' % (base, suffix)
    return base


STOP = set('a an the of to in on at is it for and or as by be this that your '
           'you no not from with which will was were has have had can may do '
           'does did if so but then they them their there here when what who '
           'how all any each every some most more less than into over under '
           'one two out up down off only just also still yet been being'.split())


def derive_key(prefix, message, arb):
    """A readable key from the WORDS of the message, not its punctuation.

    `dashboardOpenshiftsincestarttimeexpectedindrawer` is technically a valid key
    and useless to a human six months later. Taking the first few content words
    gives `dashboardOpenShiftSince`, which reads as what it is at the call site.
    """
    # A message that OPENS with its placeholder ("{amount} over the expected
    # figure") is named from the placeholder, then the words after it. Deriving it
    # from the words alone yields `dashboardOverExpected` for something whose
    # subject is the amount, which reads as a statement about the comparison.
    tokens = re.findall(r"\{([a-zA-Z0-9_]+)\}|([A-Za-z0-9]+)", message)
    parts = []
    for placeholder, word in tokens:
        if placeholder:
            if not parts:
                parts.append(placeholder)
            continue
        if word.lower() in STOP:
            continue
        parts.append(word)
    base = ''.join(w[0].upper() + w[1:] for w in parts[:4]) or 'message'
    # An apostrophe or a stray symbol in the copy would produce a name that is not
    # a Dart identifier, and gen-l10n then rejects the ENTIRE arb file — one
    # typographic apostrophe taking out every key in the app.
    base = re.sub(r'[^A-Za-z0-9]', '', base)
    if not base or base[0].isdigit():
        base = 'Message' + base
    key = prefix + base
    n = 2
    while key in arb and arb[key] != message:
        key = '%s%d' % (prefix + base, n)
        n += 1
    return key


def groups(source, start):
    """Yield (text, start, end) for each run of adjacent literals from `start`."""
    m = LITERAL.match(source, start)
    if not m:
        return
    while True:
        text = m.group(1)
        cursor = m.end()
        # `search`, not `match`: the next literal is a few characters away, and a
        # `match` at the closing quote sees the newline first and gives up.
        nxt = LITERAL.search(source, cursor)
        if nxt and GAP.match(source[cursor:nxt.start()]):
            text += nxt.group(1)
            cursor = nxt.end()
            m = nxt
            continue
        yield text, m.start(), cursor
        return


def main():
    path, prefix = sys.argv[1], sys.argv[2]
    source = io.open(path, encoding='utf-8').read()
    arb = json.load(io.open(ARB, encoding='utf-8'),
                    object_pairs_hook=collections.OrderedDict)

    existing = [k for k in arb if k.startswith(prefix)]
    out, cursor, made, skipped = [], 0, [], []
    i = 0
    while True:
        m = LITERAL.search(source, i)
        if not m:
            break
        i = m.end()
        line_start = source.rfind('\n', 0, m.start()) + 1
        if source[line_start:source.find('\n', m.start())].lstrip().startswith('import '):
            continue

        pieces = list(groups(source, m.start()))
        # Skip the WHOLE run, not just its first literal. Dart concatenates
        # adjacent literals, so `'a' ' ' 'b'` is one string; processing the tail
        # on its own produces a second message for half a sentence.
        group_end = pieces[-1][2]
        raw = pieces[0][0]
        if '?' in raw or ':' in raw.replace('::', ''):
            # A ternary or a named argument: leave it for a human.
            skipped.append((source[:m.start()].count('\n') + 1, raw))
            i = group_end
            continue
        if '$' not in ''.join(piece for piece, _, _ in pieces):
            i = group_end
            continue

        taken, args, icu, ok = set(), [], [], True
        for piece, _, _ in pieces:
            pos = 0
            for hit in INTERP.finditer(piece):
                icu.append(piece[pos:hit.start()])
                expression = hit.group(1) or hit.group(2)
                if expression is None or '?' in expression or ' ' in expression.strip():
                    ok = False
                    break
                name = name_for(expression, taken)
                if name is None:
                    ok = False
                    break
                taken.add(name)
                # The ARGUMENT is the original expression, verbatim. A placeholder
                # named `startTime` must still be handed `open.startTime`.
                args.append(expression)
                icu.append('{%s}' % name)
                pos = hit.end()
            if not ok:
                break
            icu.append(piece[pos:])
        if not ok or not taken:
            skipped.append((source[:m.start()].count('\n') + 1,
                            ''.join(p[0] for p in pieces)))
            i = group_end
            continue

        message = ''.join(icu)
        key = derive_key(prefix, message, arb)
        arb[key] = message

        out.append(source[cursor:m.start()])
        out.append('AppLocalizations.of(context).%s(%s)' % (key, ', '.join(args)))
        cursor = group_end
        made.append((source[:m.start()].count('\n') + 1, key))
        i = group_end

    out.append(source[cursor:])
    io.open(path, 'w', encoding='utf-8').write(''.join(out))
    json.dump(arb, io.open(ARB, 'w', encoding='utf-8'),
              ensure_ascii=False, indent=2)
    io.open(ARB, 'a', encoding='utf-8').write('\n')

    print('%s: wrote %d key(s), skipped %d' % (path, len(made), len(skipped)))
    for line, key in made:
        print('   %5d  %s' % (line, key))
    if skipped:
        print('  SKIPPED (ternary or unnameable expression):')
        for line, raw in skipped:
            print('   %5d  %s' % (line, raw[:90].replace('\n', ' ')))


if __name__ == '__main__':
    main()
