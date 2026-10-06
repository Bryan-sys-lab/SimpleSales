#!/usr/bin/env bash
#
# The greppable half of the design system.
#
# A hit is not automatically a defect — it is a place a decision must EXIST.
# Resolve each hit or record why the code is right; never blanket-suppress.
#
# What this cannot check, stated honestly: composition, colour harmony, copy
# register, and whether a radius suits its container. Those pull from tokens too
# and do not grep. A clean run means the MECHANICAL half passed — never report
# it as "the design system is correct".
#
# Usage: tool/check_design_gates.sh [target-dir]   (default: lib)

set -uo pipefail

TARGET="${1:-lib}"
FAILURES=0

red()   { printf '\033[31m%s\033[0m\n' "$1"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }
bold()  { printf '\033[1m%s\033[0m\n' "$1"; }

# Files allowed to carry an aesthetic value.
#
# lib/theme/**      — the token layer. This is where a value LIVES.
# lib/ui/brand/**   — brand identity. A logotype's tracking and a mark's plate
#                     are proportions, not scale choices a screen picks from.
ALLOW='^(lib/theme/|lib/ui/brand/)'

EXCEPTIONS="tool/design_gate_exceptions.txt"

# Strip comments before matching.
#
# A grep gate that matches PROSE is a gate nobody reads: the first thing it
# reports is `/// controllers here means they live exactly as long as…`, and from
# then on every hit is noise. This removes `//`, `///` and `/* … */` from each line
# while preserving the line NUMBER, so a diagnostic still points at the right
# line, and it is deliberately conservative — if it cannot tell code from comment
# it leaves the text alone rather than hiding a real hit.
strip_comments() {
  awk '
    function flush(s,   i, c, out) {
      out = ""; i = 1
      while (i <= length(s)) {
        c = substr(s, i, 1)
        if (c == "/" && substr(s, i + 1, 1) == "/") break
        if (c == "\"" || c == "\047") {
          # Copy the literal, honouring an escape, so a "//" inside a string is
          # not mistaken for a comment.
          q = c; out = out c; i++
          while (i <= length(s)) {
            c = substr(s, i, 1); out = out c; i++
            if (c == "\\") { if (i <= length(s)) { out = out substr(s, i, 1); i++ } }
            else if (c == q) break
          }
          continue
        }
        out = out c; i++
      }
      return out
    }
    {
      line = $0
      if (inblock) {
        p = index(line, "*/")
        if (p == 0) { print ""; next }
        line = substr(line, p + 2); inblock = 0
      }
      while ((p = index(line, "/*")) > 0) {
        q = index(substr(line, p + 2), "*/")
        if (q == 0) { line = substr(line, 1, p - 1); inblock = 1; break }
        line = substr(line, 1, p - 1) substr(line, p + 2 + q + 1)
      }
      print flush(line)
    }
  ' "$1"
}

# Is there a REVIEWED exception for this file and gate? Matched on file and gate
# name, never on line number: a line-number allowlist silently re-approves
# whatever drifts into that line after a reformat, which is how an allowlist
# stops meaning anything.
reviewed() {
  local file="$1" gate="$2"
  [ -f "$EXCEPTIONS" ] || return 1
  # The path in the exception file is relative to the app root.
  local rel="${file#./}"
  grep -qE "^${rel}:${gate} " "$EXCEPTIONS" 2>/dev/null
}

# Call order is LABEL, GATE-NAME, PATTERN — the gate name second so every call
# site reads as one labelled sentence and the pattern stays on its own line.
# A gate may name a narrower scope than $TARGET, for rules that only mean
# something where there is a widget tree.
#
# The motion rules are the case that needs it: a `Duration(seconds: 20)` in
# `backend_service.dart` is an HTTP timeout and a `Duration(seconds: 30)` in
# `auth_service.dart` is a PIN-attempt lockout. Neither is motion, neither file
# has a theme, and putting either in `AppMotion` would claim they are tunable
# like a transition. The same literal in `lib/screens/` IS a design decision and
# belongs in a token.
UI_SCOPE='lib/screens lib/widgets lib/routing lib/ui'

hits() {
  local label="$1"; shift
  local gate="$1"; shift
  local pattern="$1"; shift
  local scope="${1:-$TARGET}"
  local output="" hard="" reviewed_hits="" tmp
  tmp=$(mktemp)
  # Strip comments per file, then grep the stripped copy with the real file
  # prefixed back on, so the reviewed-exception lookup still sees a path.
  find $scope -name '*.dart' -type f 2>/dev/null | while IFS= read -r f; do
    case "$f" in
      lib/theme/*|lib/ui/brand/*) continue ;;
    esac
    strip_comments "$f" | grep -nE "$pattern" | while IFS= read -r hit; do
      printf '%s:%s\n' "$f" "$hit"
    done
  done > "$tmp"
  output=$(cat "$tmp")
  rm -f "$tmp"
  # Read line by line. A `for x in $output` word-splits on whitespace, which
  # turns every hit into one word and matches files against garbage.
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local f="${line%%:*}"
    if reviewed "$f" "$gate"; then
      reviewed_hits="${reviewed_hits}${line}"$'\n'
    else
      hard="${hard}${line}"$'\n'
    fi
  done <<< "$output"
  if [ -n "$reviewed_hits" ]; then
    yellow "! $label — ${gate} (REVIEWED exception, see ${EXCEPTIONS})"
    echo "$reviewed_hits" | sed 's/^/      /'
  fi
  if [ -n "$hard" ]; then
    red "✗ $label"
    echo "$hard" | sed 's/^/    /'
    FAILURES=$((FAILURES + 1))
  elif [ -z "$reviewed_hits" ]; then
    green "✓ $label"
  fi
}

bold "Design gates over $TARGET"
echo

hits "no raw colour outside the token layer" "raw-color" \
  'Color\(0x[0-9A-Fa-f]{8}\)|Colors\.(white|black|grey|gray|red|green|blue|orange|amber|transparent\))'

hits "no literal corner radius outside the token layer" "radius" \
  'BorderRadius\.(circular|only)\([0-9]'

# Milliseconds and seconds are MOTION. Minutes/hours/days are POLICY — how long a
# till stays signed in, how long a receipt is kept — and a design token for those
# would claim they are tunable like a transition. Policy values live beside the
# code that enforces them.
hits "no literal motion duration outside the token layer" "duration" \
  'Duration\((milliseconds|seconds):' "$UI_SCOPE"

hits "no literal curve outside the token layer" "curve" \
  'Curves\.(easeIn|easeOut|easeInOut|linear|decelerate|accelerate|elastic|bounce)\b' \
  "$UI_SCOPE"

hits "no literal font size outside the token layer" "fontSize" \
  'fontSize:[[:space:]]*[0-9]'

hits "no literal elevation outside the token layer" "elevation" \
  'elevation:[[:space:]]*[0-9]'

# The clamps. These are the "fixes" that look like solutions and are the defect:
# each one defeats the OS text-scale setting while every guideline stays green.
hits "text scale is never clamped or overridden" "textscale" \
  'withClampedTextScaling|textScaleFactor|FittedBox'

hits "no ellipsis on a value a user must read" "ellipsis" \
  'TextOverflow\.ellipsis'

# Physical-side geometry bypasses RTL by construction.
# Note: `Icons.arrow_back` / `arrow_forward` / `chevron_left` / `chevron_right`
# are NOT banned. Flutter declares them with `matchTextDirection: true`, so `Icon`
# mirrors them automatically under an RTL locale. `Icons.adaptive.*` does not exist
# in Flutter at all (it is React Native's idiom) and is checked separately.
hits "no physical-side geometry (RTL must mirror by construction)" "geometry" \
  'EdgeInsets\.only\([^)]*(left|right):|Align(ment)?\.center(Left|Right)|Positioned\([^)]*(left|right):|TextAlign\.(left|right)\b'

hits "no Icons.adaptive — it is not a Flutter API" "icons-adaptive" \
  'Icons\.adaptive\.'

hits "no device or platform check selecting a layout" "platform" \
  'Platform\.is(Android|IOS|Windows|Linux|MacOS|Fuchsia)'

hits "MediaQuery read through the narrowest aspect getter" "mediaquery" \
  'MediaQuery\.of\(context\)\.(size|padding|textScaler|boldText|disableAnimations|highContrast|viewInsets|viewPadding)'

hits "one navigation system: no Navigator.push or MaterialPageRoute" "navigator" \
  'Navigator\.of\([^)]*\)\.push|MaterialPageRoute'

hits "no controller or subscription created in build()" "controllers" \
  'build\([^)]*\)[[:space:]]*\{[^}]*(TextEditingController|AnimationController|ScrollController|FocusNode)\('

# State and feedback.
hits "no FutureBuilder or StreamBuilder over a repository in a widget" "builders" \
  'FutureBuilder|StreamBuilder'

hits "no raw exception rendered to the user" "exception-text" \
  "Text\([^)]*toString\(\)"

hits "no blank suppressions" "suppressions" \
  '//[[:space:]]*ignore:|catch[[:space:]]*\([[:space:]]*\)[[:space:]]*\{|catch[[:space:]]*\(e\)[[:space:]]*\{[[:space:]]*\}'

# Excludes the IMPORT of the map: importing `HapticTheme` is how a feature spends
# a slot, which is the whole point of the map.
hits "no imperative haptics — go through the event map" "haptics" \
  '[^.a-zA-Z]HapticFeedback\.(light|medium|heavy|selection)Impact\(\)'

hits "no GlobalKey used for identity" "global-key" \
  'GlobalKey<[A-Za-z]*State>\(\s*key:'

echo
# ------------------------------------------------------- colour is not enough
# Deliberately NOT a grep. "Does this state survive greyscale?" is not a pattern
# question: `StatusTone` answers it by construction (a per-status GLYPH, a per-
# status WORD, and a monotonic weight, with colour derived last), and
# `test/theme/contrast_test.dart` asserts the luminance gap for the one state pair
# that differs only by hue. A gate here would only ever match prose.
printf '\033[33m·\033[0m %s\n' \
  "colour-never-alone is structural (StatusTone), not greppable — asserted in test/theme/contrast_test.dart"

echo
# ------------------------------------------------------------------ i18n
# English-only for this pass, but the geometry is directional from this commit so
# adding a locale later is a translation task rather than a rewrite.
if grep -rn "localizationsDelegates" "$TARGET" --include='*.dart' >/dev/null 2>&1; then
  green "✓ gen-l10n is wired"
else
  printf '\033[33m!\033[0m %s\n' \
    "gen-l10n is not wired yet (expected: English-only pass). Adding a locale"
  printf '  %s\n' \
    "means extracting every literal, which this gate cannot help with."
fi

echo
if [ "$FAILURES" -eq 0 ]; then
  green "All greppable design gates passed over $TARGET."
  echo
  echo "This covered the MECHANICAL rules only. Colour harmony, composition,"
  echo "copy register and whether a radius suits its container do not grep and"
  echo "need the design review pass."
  exit 0
fi

red "$FAILURES design gate(s) failed."
echo "A legitimate new need is a NEW TOKEN SLOT in lib/theme/, never an ignore."
exit 1