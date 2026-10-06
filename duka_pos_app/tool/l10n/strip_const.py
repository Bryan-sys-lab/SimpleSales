import io, re, sys

def strip(text):
    """Remove the `const ` keyword from any widget literal whose balanced
    argument subtree contains `AppLocalizations.of(`.

    Only the five characters `const` are deleted. The identifier, the argument
    subtree and every trailing token are copied verbatim, which is the whole
    reason this is written as a slice rather than a rebuild."""
    out = []
    pos = 0
    for m in re.finditer(r'\bconst (?=\w+\()', text):
        open_at = m.end()
        depth = 0
        end = None
        for j in range(open_at, len(text)):
            if text[j] == '(':
                depth += 1
            elif text[j] == ')':
                depth -= 1
                if depth == 0:
                    end = j
                    break
        if end is None:
            continue
        if 'AppLocalizations.of(' in text[open_at:end + 1]:
            out.append(text[pos:m.start()])
            pos = m.start() + len('const ')
            changed = True
        else:
            changed = False
        if end is not None and changed:
            continue
    out.append(text[pos:])
    return ''.join(out)

for path in sys.argv[1:]:
    src = io.open(path, encoding='utf-8').read()
    io.open(path, 'w', encoding='utf-8').write(strip(src))
    print('stripped const in', path)
