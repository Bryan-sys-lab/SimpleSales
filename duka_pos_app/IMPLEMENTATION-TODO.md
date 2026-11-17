# Incremental implementation todo

This checklist tracks the v84 patch pack and the reported production issues. Each
item is completed and tested before the next item is started.

## Canonical v84 patch-pack progress

The authoritative specifications are `patches/DUKA_POS_V84_FINAL_PATCHES/PATCH-00`
through `PATCH-12`; this is an implementation status table, not a claim that the
specification itself is executable code.

- [x] PATCH-00 — baseline, invariants, dependency order, and acceptance contract
      reviewed. The user's explicit instruction to erase jobs overrides the
      source pack's legacy-job compatibility note; Open Business Profile is
      preserved.
- [x] PATCH-01 — remove job functionality completely at the user's direction;
      active UI/profile surfaces, local fresh-schema creation, v85 cleanup
      migration, backend routes/models, and obsolete job tests are removed.
      Historical upgrade migrations retain only the create-then-drop path needed
      to upgrade an old database; they are not runtime features or fresh-schema
      tables. The Open business profile and pooled-cost flows remain preserved.
- [x] PATCH-02 — Open now uses the shared InventoryScreen and SellScreen,
      profile/permission gates are preserved, Cost of Goods remains nested
      under Inventory, and navigation/route acceptance coverage passes.
- [x] PATCH-03 — Duka/Open loose goods use shared measured-serving behaviour,
      Drinks retains tank workflows, serving dimensions convert through one
      unit helper, invalid count dimensions are rejected, legacy tank rows stay
      visible, and no free-form product amount fallback remains.
- [x] PATCH-04 — Duka and Open dashboards use one in-place QuickSale modal;
      it uses configured catalogue prices, shared sale/stock/COGS writes,
      guarded credit selection, and SuccessView receipt actions. Transaction,
      dashboard, and receipt regressions pass.
- [x] PATCH-05 — Normal checkout and QuickSale always expose customer credit,
      disable it with a reason when unavailable, support validated existing or
      new Kenyan customers, revalidate limits/permissions in the transaction,
      reject split credit, and commit customer/sale/ledger atomically. Credit
      writes receivables with zero cash and the credit receipt label; focused
      ledger, rollback, split, QuickSale, and till tests pass.
- [x] PATCH-06 — linked products automatically recover measured true cost
      rather than gross revenue, pool reload uses the standard atomic receipt
      path with persisted payment source and one purchase event, and pool
      recovery reversals are append-only on restocked returns. Permission,
      reload, linked-sale, automatic-link, and full database regression tests
      pass.
- [x] PATCH-07 — Open dashboard now uses the shared commerce snapshot with
      average sale, expected till, payment mix, top items, inventory health,
      receivables, permission-aware Cost of Goods figures, and an owner-only
      Portfolio card. Fashion inventory also retains variant presentation
      while exposing ordinary/loose/tank products instead of hiding them.
      Dashboard, routing, navigation, and analyzer checks pass.
- [x] PATCH-08 — analytics uses request/session/range guards, shared Open
      snapshot values, parallel remote period reads, bounded shift SQL, latest
      reconciliation reads, and fresh/upgrade analytics indexes. Analytics,
      cashier-scope, shift, and performance regressions pass.
- [x] PATCH-09 — accessibility and operational hardening coverage passes for
      compact/text-scaled layouts, 44px targets, dashboard attention, loose
      goods, tanks, servings, credit, routing and shared navigation. Duka,
      Drinks, Fashion and Open dashboards now expose owner-only Portfolio cards
      and profile-relevant average/stock/till KPIs. No local app build was run.
- [x] PATCH-10 — schema version is authoritative at 87, v85→v87 migrations
      add pool-recovery reversals and bounded-analytics indexes safely, fresh
      and legacy schema parity passes, and the Android package identity,
      FileProvider, install permission, hardware-optional manifest, build
      number, and Redmi-compatible JNI packaging safeguards are covered by
      static tests. No APK build was run by instruction.
- [x] PATCH-11 — complete acceptance/regression/release verification matrix;
      full Flutter analysis/tests and backend tests/lint pass, including the
      migration, profile, dashboard, inventory, till, analytics, credit, and
      receipt acceptance coverage. No app build was run.
- [x] PATCH-12 — shared receipt text/PDF/print actions now read the committed
      sale snapshot across Till completion, sale details, QuickSale and Reports
      reprint, with share-link history retained.

## Follow-up quality gate requested by the owner

- [ ] Audit every feature journey from entry point to completion, including
      deep links, blank destinations, not-found states, and recovery actions.
      - [x] Route symbols and registered destinations were audited; stale or
            invalid destinations now offer Inventory, Sell, and Analytics
            recovery actions, and tank detail restores from its path id.
      - [x] Not-found recovery actions now use the localized shared destination
            labels instead of hard-coded English; focused recovery rendering
            and analyzer checks pass.
      - [x] Sync Center's Incoming Payments recovery actions now use the
            centralized route constant instead of raw path strings; focused
            route/navigation tests and analyzer pass.
      - [x] Notification destinations and Open cost-group route patterns now
            use the centralized route contract; route/profile/not-found and
            notification focused tests pass.
- [ ] Apply the shared Apple/Flutter UI pass to every form: comfortable field
      rhythm, readable dynamic text, responsive sheets, clear focus/error
      states, and consistent premium interaction feedback.
      - [x] Dashboard greetings now use localized time-of-day copy and show the
            active staff/owner name separately from the shop identity.
      - [x] Dashboard financial heroes now use the active profile palette while
            preserving contrast, responsive layout, and reduced-motion behavior.
      - [x] Shared tappable surface cards now provide restrained, interruptible
            spring press feedback with a static reduced-motion fallback.
      - [x] Dashboard KPI and hero values crossfade/settle on refresh instead of
            snapping, keyed by the committed display value.
      - [x] Open dashboard now uses the shared responsive page shell, safe-area
            handling, content width, and pull-to-refresh behavior.
      - [x] Shared dashboard surfaces now cover the rest of the app's tappable
            cards with the same press response; profile product dialogs use
            FormFieldGroup spacing instead of a cramped field stack.
      - [x] Fashion variant fields now collapse into a vertically spaced layout
            below 600dp instead of forcing identity, barcode, stock, and price
            fields into cramped horizontal rows.
      - [x] Product editor stock, reorder, cost, sell, half-price, and
            quarter-price fields now collapse to a comfortable vertical stack
            on narrow sheets instead of forcing cramped pairs.
      - [x] Activity log rows and transaction timeline rows now use clearer
            vertical rhythm while retaining wrapping, tap targets, and the
            existing sale-details action.
      - [x] Transaction sale rows now expose a clear disclosure affordance;
            sale details use a draggable Apple-style sheet with one primary
            receipt action and wrapped secondary PDF/print actions, preserving
            large-text reachability. Focused transaction/activity/detail/UI
            tests pass.
      - [x] Activity logs now expose an explicit, disabled-while-loading
            refresh action in addition to pull-to-refresh, keeping recovery
            reachable without leaving the screen. Activity text-scale and
            overflow tests pass.
      - [x] Manual Backup now runs the remote sync cycle; when automatic sync
            is explicitly off it also preserves the existing encrypted export
            and share flow. New workspaces default automatic sync to on.
      - [x] Verification emails now embed the Nerva wordmark as an inline CID
            PNG attachment instead of a remote image link, use escaped and
            responsive HTML, and keep the verification code selectable. The
            verification-code sheet now supports copy/paste and passes its
            large-text regression coverage.
      - [x] Open cost-group stock reload now uses the shared vertical field
            rhythm, so product, quantity, cost, payment source, and supplier
            reference remain readable in a narrow dialog.
      - [x] Product detail headers now present a larger accessible product
            image with a shared inventory/sell Hero transition; focused detail
            image, dashboard, and analyzer checks pass.
      - [x] Tank detail now uses the stored tank product photo in the same
            accessible 128dp identity presentation and Hero namespace, keeping
            the fill percentage in its separate progress surface.
      - [x] Open dashboard quick actions now use the shared press-responsive
            SurfaceCard button primitive with semantic labels instead of raw
            Card/InkWell links.
      - [x] Product detail quick actions now use responsive stadium buttons
            instead of three full-width stacked rows; inventory serving and
            low-stock utility links now use explicit action pills.
      - [x] Ordinary product detail stock activity now reads the persisted
            stock ledger instead of placeholder sale/receipt figures, with a
            real empty state and movement-specific labels.
      - [x] Button-surface audit: dashboard and operational row actions now use
            compact icon pills (portfolio, stock/cost actions, retry/open,
            revoke, receive-order, PIN reset, and profile photo); dividers are
            retained only where they separate non-action facts or data rows.
      - [x] Variant/serving editor now uses the shared FormFieldGroup rhythm,
            keeping helper text and paired price/stock fields separated at
            narrow widths and larger text scales.
      - [x] Inventory footer actions now use horizontally scrollable icon pills
            with consistent spacing instead of bare text links.
      - [x] PIN reset confirmation fields now use the same medium vertical
            rhythm, avoiding a cramped new-PIN/confirmation pair.
      - [x] Serving edits now remove the previous normalized `product_cups`
            link before relinking a product or changing serving shape; focused
            shared-template, per-product-price, and relink regressions pass.
- [ ] Re-run the full visual/overflow/accessibility matrix after the journey
      and form pass; do not claim the release gate complete while any route or
      form remains unverified.

## Current baseline

- [x] Preserve and inspect the existing v84 working tree changes.
- [x] Read the v84 patch work order and identify the shared contracts.
   - [x] Run the focused Flutter/backend baseline test suites and record/fix the
         shared stock-receipt financial contract regression.

## Ordered work

0. **User-authorized job removal**
   - [x] Remove job profile flags, navigation metadata, KPI, routes, job-only
         screens, job-linked quick sales, and job receivable rows.
   - [x] Remove job permissions, local repository/schema/tables, financial
         projections, account-deletion references, and backend job sync/routes;
      runtime, migration, Prisma, route, and obsolete-test cleanup are done.
      Historical migration compatibility references and generated legacy
      localization entries remain intentionally isolated for final cleanup.
   - [x] Add the destructive schema migration and regression coverage proving
         job tables are absent while Open pooled-cost operations remain.

1. **Servings, tanks, and navigation**
   - [x] Make servings reachable for every profile that supports measured goods.
   - [x] Make tank register/detail routes reachable for Drinks and ensure route IDs
         load the requested tank from the path parameter.
   - [x] Make the serving list show persisted servings immediately after save and
         refresh Till/catalogue state.
   - [x] Complete serving copy/edit/deactivate behavior, including per-product
         prices and sharing one serving definition across products.
   - [x] Make tank receive post a real stock receipt against the selected tank.
   - [x] Make tank history load the tank's persisted stock movements.
   - [x] Complete tank measurement/edit behavior and verify no blank destinations
         remain (measurement opens scoped stocktake; edit uses the tank editor).
   - [x] Tank detail now exposes its own permission-gated edit action and stacks
         receive/measure/history actions on narrow screens instead of cramping
         three buttons into one row.
   - [x] Tank detail remaining and capacity figures now display their stored
         litre unit correctly, including fractional values.
   - [x] Cold tank detail links now pass the path id explicitly into the screen,
         so register → detail → operations also works after process restart.
   - [x] Dashboard and Inventory stocktake entry points now use the registered
         `/inventory/stocktake` route rather than ad-hoc page pushes.
   - [x] Serving sync now carries the declared capacity unit to the backend;
         focused persistence coverage guards litre/kilogram serving reloads
         from silently defaulting back to millilitres.
   - [x] Serving sync leaves rows pending when catalogue sync has not yet
         established a remote product id, preventing unusable null-linked
         operational records on the backend; focused contract coverage passes.
   - [x] Backend serving sync now validates resolved product identifiers and
         serving payload fields instead of accepting opaque malformed rows;
         validation, lint, and TypeScript checks pass.
      - [x] Backend serving sync now accepts only the shared product-unit
            vocabulary (with legacy aliases) and rejects arbitrary dimensions;
            litre/kilogram and invalid-unit regression coverage is included.
   - [x] Backend serving sync now verifies every referenced product belongs to
         the authenticated shop before writing the serving ledger; cross-tenant
         product regression coverage passes.
   - [x] Backend lay-by sync now verifies customer UUIDs and referenced product
         IDs belong to the authenticated shop before writing lifecycle snapshots;
         customer and product cross-tenant rejection coverage passes.
   - [x] Copying a serving to another product now opens the normal editor so
         the shared serving shape is retained while the destination product's
         price can be configured independently; duplicate active label/product
         links are excluded. Shared-template/per-product-price database tests
         and serving analyzer checks pass.
   - [x] Servings search now filters persisted rows by serving label, parent
         product, or unit; its filtering contract has focused regression tests.
   - [x] Serving editing now preserves the declared capacity unit and new
         servings can choose millilitres, litres, or kilograms; validation and
         form spacing follow the selected unit. Serving cards preserve that
         unit in their displayed capacity as well.

2. **Feature-complete product details and editing**
   - [x] Make edit actions work from the shared product detail surface (including
         tank editing); fashion detail already routes to its editor.
   - [x] Ordinary product detail now gates Edit by the shared inventory
         capability, matching Inventory, Tank, and Fashion detail instead of
         incorrectly depending on supplier-management permission.
   - [x] Reconcile ordinary, loose-good, tank, fashion, variant, and pack edits.
      - [x] Pack definitions now have an edit flow that preserves stock,
            validates barcode uniqueness, and refreshes the inventory sheet.
      - [x] Fashion detail now reloads its product and variants after the editor
            returns successfully, so the completed edit is visible immediately.
   - [x] Add database regression coverage for product edit save/reload and
         preservation of stock, variant, and portion-price fields.
   - [x] Add catalogue regression coverage proving edited products appear with
         the new values on the Till data source.
   - [x] Drinks product creation no longer exposes a pack-type field that the
         product persistence contract cannot store; supported crate/keg units
         remain explicit product units.

3. **Backend staff/auth/sync**
   - [x] Trace mobile auth headers against backend middleware and token refresh.
   - [x] Allow the tenant-scoped fresh-device staff PIN bootstrap without an app
         bearer token; keep all other protected routes bearer-authenticated.
   - [~] Fix remote staff registration, login, creation, and sync contracts;
         backend tenant-scoped authentication, staff upsert/pull routes, and
      app client calls are present and backend/mock-owner coverage passes,
      while live device coverage remains.
      - [x] Existing-device staff login now always sends the active tenant
            selector required by the backend bootstrap route; fresh devices
            continue to use the owner-provided shop ID.
      - [x] Staff sync now accepts the backend's opaque CUID profile IDs as
            well as legacy UUID IDs; validation and HTTP regression coverage
            prove a second sync can carry the returned remote identity.
      - [x] Owner catalogue, M-Pesa product references, and stock-adjustment
            payloads now accept the backend's opaque CUID product/profile IDs;
            focused validation and stock-route coverage protect repeat syncs
            and owner operations after the first remote write.
      - [x] Support and diagnostics tenant filters accept both readable new
            account IDs and legacy UUID tenant IDs.
      - [x] Staff bootstrap now survives the backend's global-plus-router
            double auth-middleware pass; normalized original-path regression
            coverage proves a tenant-scoped request is not rejected twice.
      - [x] Backend client auth and tenant headers are now restricted to the
            backend origin; direct R2 presigned uploads no longer receive API
            credentials or trigger session-refresh retries.
      - [x] App/backend contract audit covered mounted endpoint paths, tenant
            scoping, auth refresh, opaque CUID/legacy-ID handling, product
            repeat-sync responses, staff bootstrap, and presigned uploads;
            focused route/validation tests and backend type/lint checks pass.
      - [x] Protected-route HTTP regressions still pass after the stricter
            serving contract: 25 auth, staff, and mounted-route tests pass.
      - [x] Fashion variant sync now maps local parent products to opaque
            backend product IDs before upload, preserves reserved stock, and
            accepts optional SKUs; focused Flutter/backend contract checks pass.
      - [x] Fashion variants now have a tenant-scoped backend pull route and
            merge by remote variant ID on other tills; catalogue sync invokes
            the pull and protected-route coverage passes.
      - [x] Purchase and return queues now remain pending until every product
            reference has a remote catalogue ID, preventing accepted but
            unreconcilable null-linked history; focused contract tests pass.
      - [x] Supplier-product links and purchase-order queues apply the same
            remote-product readiness gate, including every order line, so
            reorder history cannot be acknowledged with broken references.
      - [x] Open cost-pool and owner-transaction payloads now include required
            local ids, map staff to remote profile IDs when available, and use
            the app's lot/bale/rolling-stock pool vocabulary; focused Flutter
            and backend validation checks pass.
      - [x] Cost pools and owner transactions now have tenant-scoped pull
            routes and local UUID-based merges, so Open finance records created
            on another till become visible without replacing local pool entries.
      - [x] Fashion lay-by uploads now wait for real customer UUIDs and remote
            product IDs instead of sending `local:*` placeholders that another
            till could not reconcile; focused contract coverage passes.
      - [x] Backend variant sync now verifies every parent product belongs to
            the authenticated tenant before writing; tenant-boundary regression
            coverage passes.
      - [x] M-Pesa incoming-payment listings now return claim metadata the
            mobile model consumes, and cursor filtering uses receipt time
            consistently; focused M-Pesa tests and backend checks pass.
      - [x] Incoming M-Pesa pulls now drain paginated status streams using the
            forward cursor; backend pages ascend by receipt time so older
            payments are not stranded beyond the first page.
      - [x] Online STK checkout now awaits catalogue sync and reloads remote
            product IDs before initiation, preventing null product payloads
            from failing after payment setup; sell-screen analyzer passes.
      - [x] PayHero channel setup now supports bank destinations as well as
            tills and paybills, normalizes the documented Basic authorization
            header, validates bank account numbers, and masks bank details in
            Settings. Focused Flutter/backend payment tests and backend
            build/lint pass.
      - [x] PayHero status reconciliation now persists a provider check
            timestamp/status and claims refreshes transactionally, preventing
            multiple tills from hammering the provider. Ambiguous STK
            transport responses remain queued for reconciliation rather than
            being marked failed and retried as duplicates.
      - [x] Risiti retryable responses now honor request IDs and Retry-After;
            simulated acceptance cannot be presented as a KRA fiscal receipt,
            and transient submission failures return a retryable response
            while preserving the stable receipt idempotency key.
      - [x] Add a verified M-Pesa Dynamic QR checkout: Safaricom's official
            Dynamic QR API is separate from PayHero, so the backend now has
            Daraja OAuth/merchant configuration, a QR-payment endpoint, C2B
            callback correlation to the pending sale reference, and a Flutter
            dialog that renders the returned base64 PNG. Scanning alone never
            records a sale; only the authenticated callback/status path does.
            Focused backend tests/build/lint and Flutter analyzer checks pass;
            the QR action/copy is localized and uses the shared pill treatment.
      - [x] Staff sync now persists role changes on existing remote profiles,
            alongside username/name/active updates; focused staff HTTP coverage
            passes.
      - [x] Pulling a newly created remote staff profile now materializes it on
            another till with an intentionally unusable empty local PIN; later
            roster pulls update identity fields without overwriting the local
            PIN verifier. Database regression and focused analyzer pass.
      - [x] Staff PIN ownership is now explicit: owner roster sync can only set
            the initial PIN for a new profile; existing PINs cannot be replaced
            by an owner sync/reset. Online staff authentication issues a
            tenant/profile-bound session token, and staff can change their own
            PIN after verifying the current one. The first online staff login
            recommends changing and keeping the PIN private; focused settings,
            backend staff/auth, and Flutter contract tests pass.
      - [x] A reachable backend rejection during staff login now overrides a
            valid cached local PIN; only transport and 5xx failures retain the
            documented offline-login fallback. The boundary has focused
            Flutter regression coverage.
      - [x] Forgotten staff PIN recovery now uses a tenant-scoped owner request:
            staff can notify the owner from the login screen without exposing
            username existence, the owner sees pending requests in Settings and
            owner notifications, and can issue a temporary PIN. The temporary
            verifier is stored only as a hash, never returned or included in
            live events/activity; the owner audit entry explicitly masks its
            value. Backend request/approval and notification/settings regressions
            pass.
      - [x] Backup restores now verify the returned workspace key and backup
            kind before decrypting or applying ciphertext; backend routes remain
            tenant-scoped.
      - [x] Live multi-till updates now use tenant-authenticated WebSockets:
            the mobile handshake sends bearer plus tenant headers, the Node
            server verifies both and emits mutation signals, and the Worker
            isolates Durable Object rooms per tenant and relays successful API
            mutations. The channel remains signal-only; authenticated HTTP
            reads remain the source of truth and reconnect is the fallback;
            foreground `read` requests now receive a private snapshot response
            instead of being ignored or echoed to other tills.
            Tenant-isolation regression coverage, focused live-channel checks,
            backend build, and lint pass.
      - [x] Transactions and Activity now subscribe to the shared live-refresh
            mixin, so visible ledger/log surfaces reload after remote till
            mutations instead of waiting for navigation or manual refresh.
            The mixin also runs one coalesced remote business pull before local
            rereads, so the screens do not merely repaint stale SQLite data.
            Their focused UI, backend-service, and live-channel tests pass.
      - [x] Live-refresh visibility now follows TickerMode by default, so Sell,
            Activity, and Transactions do not reload while their shell branch is
            hidden; focused visibility regression coverage passes.
      - [x] Sell/catalogue now uses the same event-driven pull and reload path,
            preserving the active cart while refreshing remote products, stock,
            variants, and servings. Sell layout, backend-service, and live
            channel tests pass.
   - [x] Add focused backend HTTP/validation coverage and run the backend
         auth/validation regression tests.
   - [x] Add mock-owner coverage for successful remote staff upsert, pull, and
         fresh-device login; live-device verification remains release work.
   - [x] New backend tenant/account ids are readable owner-shop-number values;
         existing ids are preserved, and local new-shop workspace keys use the
         same human-readable naming convention.

4. **Android installation/update reliability**
   - [ ] Verify application ID, signing/update identity, manifest, SDK/package
         metadata, and Redmi-compatible APK build/install behavior.
      - [x] Static package identity, FileProvider, install permission, optional
            hardware, SDK floor, JNI packaging, and release-signing guards pass.
   - [x] Run manifest/release configuration regression checks.
   - [ ] Build and inspect an APK; local build is currently blocked because the
         Android SDK NDK 28.2.13676358 license is not accepted in this environment.

5. **Images and sale-evidence journey**
   - [x] Use the shared local product-photo editor for Drinks, Duka, and Open;
         add local photo selection/removal to Fashion product forms.
   - [x] Show product photos in standard and Fashion detail headers, Sell tiles,
         and inventory surfaces.
   - [x] Keep inventory stock quantity at the trailing action end of each row,
         beside the overflow menu, so photo rows have one leading identity
         visual and never collide with the stock indicator.
   - [x] Add workspace-scoped serving-photo persistence, migration, editor,
         Servings cards, and Sell chooser rendering; focused image and serving
         persistence tests pass.
   - [x] Add tenant-scoped R2 sale-evidence metadata, presigned upload/confirm/
         list endpoints, and Open/Fashion sale-detail capture/viewing.
   - [x] Capture offline evidence into the workspace database and retry it from
         sale details and the owner/business sync cycle; encrypted backup/import
         carries the metadata, and full-snapshot acceptance covers the evidence
         table.

6. **Patch-pack completion and release gate**
   - [ ] Finish remaining v84 patches in dependency order.
   - [ ] Remove only tests proven obsolete by changed contracts; replace them with
         acceptance/regression coverage.
   - [ ] Run Flutter analyze/tests, backend lint/tests, and release checks.

