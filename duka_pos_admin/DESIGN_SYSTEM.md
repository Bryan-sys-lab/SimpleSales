# SimplerAnalytics Admin design system

## Product direction

The admin app is an operational dashboard for a team that primarily works from phones. Prioritize a clear daily overview, fast access to frequent work, and safe handling of sensitive shop, billing, and staff records. Use established interaction patterns from systems such as GitHub Primer and Material 3 as references, while retaining SimplerAnalytics branding and workflows.

## Visual language

- Use base 50 (`#f7f8f6`) for the light canvas, white for surfaces, and base 950 for the dark canvas. Keep cards quiet; reserve stronger color for the primary action and status.
- Primary action: accent/electric 700 with white text; hover: accent/electric 800.
- Use sage for success or completed states, electric for active or in-progress states, coral for warnings, declines, or elevated risk, and base colors for neutral or unknown states. Never rely on color alone to convey status.
- Use the transparent WebP mark with the HTML wordmark on page surfaces; use the dark-backed WebP icon for installed-app icons.
- Focus uses a 3 px accent outline with offset. Keep contrast and visible focus in both light and dark themes.

## App shell and page structure

- On wide screens, group every permission-filtered destination in the persistent side navigation. On phones, keep four frequent destinations in the bottom bar and place the rest in an accessible, scrollable More sheet.
- Every route has one clear `h1`, a short purpose line, and a consistent content rhythm. Use `h2` for primary sections and `h3` for their subsections.
- Place filters near the data they affect. Keep primary actions visible and full-width on narrow screens where that improves reach.
- Use 16 px text for primary reading, 14 px for supporting values, and 12 px for compact metadata. Use tabular numerals for money and counts; keep IDs and technical values monospaced and secondary.
- Give each screen explicit loading, empty, error, and success states. Errors must be announced; asynchronous success feedback should be announced politely.

## Data and forms

- Prefer the shared `DataTable` for sortable and paginated records. Switch between table and card layouts based on the component's available width, not only the viewport. Keep preset sorting visible in the selector and `aria-sort`; on small screens, expose identifying fields in readable record cards with an explicit detail affordance.
- Label every input visibly and associate labels with controls. Use the correct mobile keyboard/input type and retain native validation.
- Use disclosure details for secondary record fields, with a clear keyboard-operable summary and visible open/closed state.
- Keep high-risk actions explicit, label the effect, and confirm before applying destructive changes.
- Keep credentials, customer-entered text, and unnecessary personal data out of telemetry and diagnostic summaries.

## Interaction and accessibility

- Use 44 px minimum touch targets for interactive controls on touch devices.
- All interactions must work by keyboard, expose names and state to assistive technology, and preserve a visible focus indicator.
- Respect reduced-motion preferences; avoid unnecessary movement and do not animate loading text when reduced motion is requested.
- For diagnostic replay, show an ordered timeline and a separate expandable stack trace.
