# Duka Platform Admin design system

## Direction

An operational console for a phone-first team. Use compact summaries for scanning and disclosure cards or detail panels for the full record. Keep high-risk actions explicit and audit-visible.

## Color

- Canvas: base 50 (`#f7f8f6`); surfaces: white; dark canvas: base 950.
- Primary action: electric 700 (`#0b7544`) with white text; hover: electric 800 (`#075a38`).
- Coral, electric, and sage each use a 50–950 ramp. Use sage for successful or completed states, electric for active or in-progress states, and coral for warnings, declines, or elevated risk. Keep neutral and unknown states on the base scale.
- Use the transparent WebP mark with the HTML wordmark on page surfaces; use the dark-backed WebP icon for installed-app icons. Loading states animate the name and respect reduced-motion preferences.
- Focus uses a 3 px electric outline with offset. Do not rely on color alone for status.

## Layout and type

- Mobile first: four frequent destinations on the bottom bar; less frequent sections in an accessible More sheet.
- Use one clear page title, a short purpose line, then the primary action or table.
- Use 16 px minimum body text for primary reading, 14 px for supporting values, and 12 px for compact metadata.
- Use tabular numerals for money and counts. Keep IDs and technical values monospaced and secondary.
- Tables remain on wide screens. On small screens, show two identifying values and reveal the rest in a disclosure card.

## Interaction

- Rows open a detail view when they have meaningful additional information. Provide a visible Details affordance on mobile.
- Keep destructive actions labeled with their effect and confirm before applying them.
- Use 44 px minimum touch targets for primary mobile actions.
- Respect reduced motion. Focus indicators, keyboard access, and labels remain visible in light and dark themes.
- For diagnostic replay, show an ordered timeline and a separate expandable stack trace; keep credentials and customer-entered text out of event timelines.
