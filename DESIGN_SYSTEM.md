# SimpleSales Design System

The only authoritative design-system specification is
[`duka_pos_app/DESIGN_SYSTEM.md`](duka_pos_app/DESIGN_SYSTEM.md). It documents
the app's shared color, typography, spacing, shape, component, accessibility,
motion, and interaction rules.

The implementation source of truth is `duka_pos_app/lib/theme/`: primitives
feed semantic `AppColors`, `AppSpacing`, `AppShapes`, and the shared theme.
Screens, including dashboards, shop pages, access, and plan details, must use
those tokens and shared components. Do not add feature-specific palettes,
forced themes, or duplicate card styles.

Update the canonical specification and its focused tests when changing a
shared design rule. This file is an entry point only, not a second specification.
