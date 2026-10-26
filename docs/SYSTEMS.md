# SimpleSales Systems Index

This is the navigation document for the active implementation systems. The root expansion plan remains the execution source of truth; this file makes its remaining slices and supporting evidence easy to find.

## Source-of-truth documents

- [Master expansion plan](../simplepos_expansion_plan.md)
- [Theme System & Human Interface Design Plan](SIMPLESales-THEME-SYSTEM.md)
- [Commercial pilot validation brief](commercial-pilot-brief.md)
- [Handover and remaining implementation notes](../HANDOVER-REMAINING.md)
- [Theme implementation evidence](SIMPLESales-THEME-SYSTEM.md)

## Product onboarding

The pre-account product tour is implemented in
[`duka_pos_app/lib/screens/product_onboarding_screen.dart`](../duka_pos_app/lib/screens/product_onboarding_screen.dart).
It introduces the Kenyan business context and all four profiles, then routes
to sign-in or account creation. Local photo assets live under
`duka_pos_app/assets/onboarding/` so the first-run flow works offline. The
reference-grid artwork is used only as visual direction: the app displays
cleanly cropped Kenyan shop photography inside shared Flutter cards, with the
copy and profile feature lists rendered as native, responsive UI. The old
post-account demo/import walkthrough is no longer rendered; legacy installs are
sent directly to the functional optional-permissions step.

## Profile completion status

The four business profiles are implemented through the shared profile, finance, navigation and analytics layers:

- Drinks — complete under the profile gate.
- Duka — complete under the profile gate.
- Fashion — complete under the profile gate.
- Open — quick sale, stock/cost handling, navigation and backend support are implemented and covered by the profile gate.

The Group F gate was verified after Open work with 1,675 Flutter tests passing. This confirms profile implementation status; it does not imply that the entire expansion plan is complete.

## Remaining expansion-plan slices

These are the remaining Group J/release-readiness slices. They must be completed in order, and a slice must not be checked off while only partially evidenced.

### J-2 — Buyer discovery and one narrow paid pilot

Status: **blocked / not complete**.

The required buyer interviews, design-partner commitments and paid-pilot evidence are external business activities and have not been recorded. The bounded experiment is documented in [commercial-pilot-brief.md](commercial-pilot-brief.md). Do not mark this item complete or build advanced self-service/ML infrastructure until its decision gate has evidence.

### J-3 — End-to-end release validation

Status: **pending J-2 and release evidence**.

Validate financial correctness, profile switching, tax behaviour, security, privacy, accessibility, performance, migrations and restore end-to-end. Use focused tests during implementation and run the full applicable suite at the end of the section before advancing.

### J-4 — Legal and tax issue documentation

Status: **pending review**.

Document unresolved legal/tax questions and required approvals rather than inventing defaults. KRA/eTIMS/tax functionality is intentionally turned off for now to preserve the previous behaviour; the relevant enablement work remains a future, reviewed release slice.

### J-5 — Final release, security and legal gates

Status: **pending**.

Release only after applicable acceptance criteria, security/privacy checks, legal/tax review and the end-to-end validation evidence pass.

## Completed supporting slice

Group J data-quality/reproducibility work is complete: the restricted admin Data Quality view/API reports coverage, freshness, suppression, duplicate handling, quality flags and deterministic fingerprints. Backend build/lint and the full backend suite passed at 22 files / 155 tests, and the admin production build passed.

## Working rule

The next implementation action must always be the first incomplete item in the active source-of-truth plan. Evidence belongs beside the item it proves; no later slice is considered complete when an earlier slice is partial or blocked.
