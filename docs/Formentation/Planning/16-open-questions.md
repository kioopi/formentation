---
title: Formentation Open Questions
tags:
  - formentation
  - decisions
status: active
---

# Open questions

These questions should be answered by prototypes, tests, and user needs. They are not all prerequisites for [[phase-1-walking-skeleton|Phase 1]]. Questions that get answered move to the [[18-decisions|decision log]].

## Core representation

- ~~Should semantic node kinds be separate structs or one tagged struct?~~ Answered 2026-07-22: one struct per kind, split when the shape differs rather than when values differ — [[18-decisions#D-015 — One struct per node kind|D-015]].
- Should `:group`'s two flavors (data-nesting vs presentational) become separate structs too? `nests_data?` still flags kind-like variation inside one struct; a split is now a cheap, localized change. Links [[18-decisions#D-006 — One `:group` kind, flagged for data nesting|D-006]] and [[18-decisions#D-015 — One struct per node kind|D-015]].
- A presentation group's `fields:` list or a `fields` UI hint can claim a property that is not a field. Since D-015, membership stamps and hints apply only to `Field` nodes; non-field claims are placed (groups) or ignored (hints) silently. Should they warn instead? Related to the existing hint-strictness questions.
- How opaque should `Formentation.Definition` be to extension authors?
- Which decisions merit full provenance objects versus compact origin references? (Initial answer: tags only — [[18-decisions|D-003]]; the question returns when the full model lands.)
- Is the definition intended to be serializable, or only deterministic and cacheable within an application version?
- How should recursive semantic graphs be exposed through `Info` without surprising tree-oriented consumers?
- What are the semantics of a field claimed by two presentation groups? Today the second group emits a misleading `unknown_group_field` warning; overlap needs a real decision.
- Should a failed compile return all diagnostics accumulated before the error instead of only the fatal one? Revisit with the Phase 2 compiler/diagnostics restructuring.
- Group declarations are outside the node budget: many groups with many unknown field names generate unbounded warning diagnostics. Fold into the next guards/hardening pass.

## Source and validation

- ~~Which JSON Schema dialect, and which validator?~~ Answered 2026-07-21: draft 2020-12, validated by JSV — [[18-decisions#D-008 — JSV is the JSON Schema validator|D-008]].
- Does the validator adapter expose only validation, or also compiled schemas and reference registries?
- What remote-reference policy is safe and usable by default?
- How should custom vocabularies declare whether they change validation or only annotations?
- How can three-valued condition evaluation (`true | false | unknown`) be built on top of two-valued JSON Schema validators without Formentation re-implementing validation semantics? Deriving `unknown` from partial input is itself an interpretation of the schema, which [[02-design-principles#Validation semantics have a single owner|the single-owner principle]] forbids Formentation from doing casually. This is the hardest open problem behind [[phase-4-dynamic-schemas|Phase 4]].
- A scalar `type` combined with `oneOf`/`anyOf`/`allOf` currently compiles the scalar and silently ignores the combinator for shape derivation (instance validation still honors it); a warning may fit the spec's intent better. The same policy covers `const` combined with `enum`: const wins the option set silently.
- `default` and `examples` on object schemas are silently ignored; only scalar fields carry them. Should they warn, or land on group nodes? Likewise `const`/`enum` on an object-typed property: the object clause routes first, so the keyword is silently ignored for shape derivation (instance validation still honors it).
- JSON Schema 2020-12's native `readOnly`/`writeOnly` annotation keywords are silently ignored: a schema carrying `"readOnly": true` — the standard spelling of exactly [[18-decisions#D-016 — Participation is definition-driven, not transport-driven|D-016]]'s intent — compiles with `read_only?: false` and no diagnostic, and the author must re-declare it as the `read_only` UI hint. Should the schema keyword seed the flag, with the UI hint overriding?

## UI declaration

- Should the first UI format closely follow RJSF `uiSchema`, or define a smaller Formentation-specific vocabulary? (A first provisional vocabulary is drafted in [[17-end-to-end-example|the end-to-end example]].)
- Are UI hints a declaration source with their own adapter, or a compile option attached to a primary source? The conceptual model and the compile API currently disagree.
- How are ordered layouts expressed without making object map order semantically significant?
- Can UI hints target semantic/template paths as well as source schema paths?
- How are conditional UI rules represented and composed with schema conditions?
- Should field hints targeting a nested-object (group) node warn or apply? Today `fields.<name>` hints stamp widget/help onto non-field nodes silently.
- Should a non-string `help` hint warn like an unknown widget does, or stay silently ignored? Sibling mistakes currently get three strictness levels (error / warning / silent).
- What are the semantics when an `order` entry matches both a field name and a group id? Today: silent first-match-wins.
- The JSON Schema adapter's `fields.*` hints address top-level property names only (`apply_field_hints` does not recurse), while the map source compiles inline hints at any depth. Since [[18-decisions#D-016 — Participation is definition-driven, not transport-driven|D-016]] made `read_only` a decode-participation flag, the two adapters can no longer express equivalent intent for nested fields — and a hint naming a nested field warns `unknown_hint_field` even though the field exists. Needs a nested-path addressing decision (relates to "Can UI hints target semantic/template paths as well as source schema paths?").

## Runtime and state

- ~~What is the minimal state-view interface required beyond `%Phoenix.HTML.Form{}`?~~ Answered 2026-07-22: the per-field read model is `Formentation.Form.FieldState` (transport, operation, usage, issues, derived display value) plus `Form.show_issues?/2` for visibility; collection and branch accessors still wait for Milestone B and Phase 4 — step-4 spec `docs/superpowers/specs/2026-07-22-phase1-step4-state-and-codecs-design.md`. Answered again 2026-07-25 for the projection boundary: three read-only callbacks (`submitted?/2`, `issue_visibility/3`, `issues/2`) on `Formentation.Phoenix.StateView`, dispatched on `form.source` with an `Any` fallback — [[18-decisions#D-027 — Projection reads semantic state through a StateView protocol|D-027]]. Collection and branch accessors still wait for Milestone B and Phase 4.
- ~~Where should decoding occur relative to Phoenix `FormData` conversion?~~ Answered 2026-07-22: decoding precedes conversion; `FormData` projects already-decoded state — [[18-decisions#D-009 — Form state separates transport from operation|D-009]].
- ~~What is validated when some fields fail decoding?~~ Answered 2026-07-22: nothing — whole-instance validation defers while any decode issue exists, so no second `required`-style error piles onto a decode issue and raw text never reaches the validator; the progressive target is recorded in the same entry — [[18-decisions#D-012 — Schema validation defers while any decode fails|D-012]].
- How does decoding interact with branch selection when branches imply different value shapes and codecs? The active branch determines codecs, but decoded values determine the active branch — a fixpoint risk for [[phase-4-dynamic-schemas|Phase 4]]. (Direction in `docs/discussion/encoding-and-decoding.md`: branch selection is interaction state resolved by a branch-neutral codec, explicit selectors before implicit inference; decide with Phase 4.)
- ~~What are the default policies for empty strings, absent keys, and explicit null?~~ Answered 2026-07-22: typed empty-string handling, explicit-only null, replace-scope deletion — [[18-decisions#D-010 — Empty-string, null, and absent-key decode policies|D-010]]; booleans ride the hidden-input transport contract — [[18-decisions#D-011 — Booleans use the hidden-input transport contract|D-011]].
- How are stable item identities generated for anonymous arrays? (Direction in `docs/discussion/encoding-and-decoding.md`: opaque sidecar identities assigned at initialization or item add, reconciled by ID, stripped before domain decoding; decide with Milestone B.)
- Which inactive-branch data policy is least surprising? (Direction in `docs/discussion/encoding-and-decoding.md`: preserve by default and separate visibility from participation; stash only provably branch-owned values; decide with Phase 4.)
- ~~How is touched/used-input state tracked across the transport boundary and represented for error visibility?~~ Answered 2026-07-22: usage (`:unused` | `:used` | `:unknown`) is a first-class interaction axis populated by transport normalization from LiveView's `_unused_` convention; the `FormData` view preserves Phoenix-compatible params so `used_input?/1` keeps working; issues are always stored, usage and `action` control visibility only — [[18-decisions#D-014 — Usage is a first-class interaction axis|D-014]].
- ~~How do fields that legitimately never submit survive replace-mode deletion?~~ Answered 2026-07-22: participation is definition-driven — `read_only` fields are excluded from the replace scope (operation `:keep`, values from original data, submitted values discarded), while `hidden` fields stay in the transport as hidden inputs — [[18-decisions#D-016 — Participation is definition-driven, not transport-driven|D-016]].
- Should the map source eventually provide instance validation for parity with the JSON Schema adapter? `Formentation.Definition` carries an optional `validation` plan (`Formentation.ValidationPlan`, [[18-decisions#D-025 — Instance validation dispatches through a source-neutral behaviour|D-025]]) that only the JSON Schema adapter fills; map-source forms carry `validation: nil` and skip instance validation (decode semantics are unaffected). Options when a use case arrives: compile the map declaration to an equivalent JSON Schema, or provide a map-native `Formentation.Validation` implementation, or accept validation as adapter-specific.
- ~~What is the `_persistent_id` transport policy for step 7?~~ LiveView's `<.inputs_for>` injects `_persistent_id` into nested params by default, and `Formentation.Transport` currently lets it into domain params and the usage map as a phantom path — harmless today (it never decodes, never reaches the candidate, and its usage agrees with `used_input?/1` because LiveView marks it `_unused__persistent_id`), but step 7 must either strip it as transport metadata or render with `skip_persistent_id`. Found by the step-5 final review. Half-answered 2026-07-23: step 6 renders nested objects directly through `Phoenix.HTML.FormData.to_form/4`, never `<.inputs_for>`, so nothing injects `_persistent_id` into Formentation-rendered markup — [[18-decisions#D-019 — Projection is Phoenix-generic|D-019]]. Answered 2026-07-24: `Transport.normalize/1` strips `_persistent_id` by key at every nesting level, alongside `_unused_*`, `_csrf_token`, and `_target`, so an arriving `_persistent_id` — from a parent `<.inputs_for>` or a hostile client — never decodes, never reaches the candidate, and never becomes a phantom usage path — [[18-decisions#D-021 — LiveView integration is wrappers plus a demo, not framework machinery|D-021]].

## Rendering

- ~~Does theme selection affect compilation, projection, or only rendering?~~ Answered 2026-07-23, for Phase 1: rendering only, and there is no theme selection yet — `Formentation.Phoenix.Theme.Reference` is called directly rather than dispatched through a configurable parameter — [[18-decisions#D-020 — The reference theme is a markup set, not a contract|D-020]].
- Which capability failures should be compile errors versus projection errors?
- What component customization can be expressed with theme data, and where are slots/callbacks needed?
- What is the minimum accessible markup contract every theme must satisfy? First answered 2026-07-23 by the reference theme's documented, Floki-tested contract (labels, `aria-describedby`, `aria-invalid`, fieldsets with legends, a submit-gated error summary, no duplicate ids, escaped schema text) — [[18-decisions#D-020 — The reference theme is a markup set, not a contract|D-020]]. The question stays open until [[phase-3-extensibility|Phase 3]] extracts the general contract from a second theme implementation.
- How do behavioural widgets fit the render-plan model? File uploads, async option search (live_select-style comboboxes), and widgets needing JS hooks or their own LiveView events are not pure render functions; the capability model currently only describes render-time support.
- ~~Number inputs render `type="number"`; browsers may refuse to display non-numeric raw text (e.g. `"51o2"`) even though the attribute carries it.~~ Answered 2026-07-24: confirmed against a real browser (Chrome) — it fails raw-input preservation two ways at once, blocking non-numeric keystrokes outright and, when invalid text is force-injected anyway, sanitizing it away on the round-trip patch. The number widget now ships as `type="text" inputmode="numeric"` instead of `type="number"` (commit "Fall back number inputs to text with numeric inputmode") — [[18-decisions#D-021 — LiveView integration is wrappers plus a demo, not framework machinery|D-021]].
- Under embedding, `Formentation.Phoenix.fields/1` renders the submit-gated error summary at the top of the Formentation fields block, before the group/field markup — which lands mid-form whenever hand-written parent inputs precede the embedded block (observed live in the pump-inspection demo, where `asset[name]` precedes the payload fields). Acceptable for [[phase-1-walking-skeleton|Phase 1]], which has no slot mechanism; the [[phase-3-extensibility|Phase 3]] theme-contract/slot design should let callers reposition or suppress the summary — [[18-decisions#D-021 — LiveView integration is wrappers plus a demo, not framework machinery|D-021]].
- ~~Step 7 showed that `Phoenix.LiveViewTest` never runs the browser's `LiveSocket` hook, so it cannot observe `_unused_` marker gating at all — the LiveView test suite and a real browser check had to disagree on record to both be right ([[18-decisions#D-021 — LiveView integration is wrappers plus a demo, not framework machinery|D-021]]). Should Formentation adopt browser-real end-to-end tests (Playwright, Wallaby) to close that gap with automated coverage, and if so, at what layer — library test suite, demo-only, or both? Flagged for discussion after step 7.~~ Answered 2026-07-24: adopted PhoenixTest + Playwright as an opt-in, demo-driven suite — the layer is the library's test suite (`test/browser/`) driving the demo, tagged `browser: :chromium`, run via `mix test.browser`, excluded from `mix test`/`mix ci` — [[18-decisions#D-022 — Browser-real tests are an opt-in, demo-driven Playwright suite|D-022]].

## Extensions

- At what point do pass ordering and descriptors warrant adopting Spark?
- How are extension versions and configuration included in fingerprints?
- Can custom nodes remain introspectable without exposing arbitrary opaque terms?
- What compatibility promises are made to third-party renderer packages before 1.0?

## Ash

- Should an Ash adapter derive definitions directly from `Ash.Resource.Info`, from action inputs, from generated JSON Schema, or from a combination?
- How are authorization-sensitive accepted fields reflected without treating visibility as security?
- Can one definition represent create, update, and read actions, or should each action compile separately?
- What metadata should be added by Ash applications for presentation without coupling Ash core semantics to UI?

## Process

Answered questions move to the [[18-decisions|decision log]]. Each decision should link to the fixture, prototype, or user requirement that motivated it — [[00-use-case|the motivating use case]] is the first such record.

## Related notes

- [[18-decisions|Decision log]]
- [[13-roadmap|Roadmap]]
- [[10-algorithms|Algorithms and invariants]]
- [[phase-1-walking-skeleton|Phase 1]]
- [[Formentation|Back to the entry point]]

