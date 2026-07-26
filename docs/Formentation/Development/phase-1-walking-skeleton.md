---
title: Phase 1 — Walking Skeleton
tags:
  - formentation
  - roadmap
  - phase-1
  - phoenix
status: in-progress
phase: 1
---

# Phase 1 — Walking skeleton

## Goal

Deliver one thin, end-to-end vertical slice as early as possible: compile a deliberately small declaration into a `Formentation.Definition`, render it through Phoenix components backed by JSON-backed form state, validate changes, preserve raw input, and submit decoded JSON-compatible data — for the payload forms described in [[00-use-case|the motivating use case]].

This phase merges the formerly separate "static foundation" and "Phoenix runtime" phases ([[18-decisions#D-002 — Phase 1 is a walking skeleton|D-002]]). A definition-only phase could not retire its own headline risk: whether the IR is useful is only proven by a consumer.

> [!important] Alignment gate before Milestone B
> Milestone A proved the behaviour but also exposed a mixed
> semantic/presentation definition and an over-explicit public lifecycle.
> [[phase-1-north-star-alignment|Phase 1 — North-star alignment]] now comes
> before collections. It migrates the working skeleton to
> [[19-north-star-architecture|the north-star `Definition`/`Form` model]]
> without changing this phase's behavioural promises.

## Progress

> [!success] 2026-07-21 — Implementation strategy steps 1–2 complete (map-source static pipeline)
> `Formentation.compile/2` with the `Formentation.Source.Map` adapter compiles to `Formentation.Definition`/`Formentation.Node` with origin tags, queried through the full slice-1 `Formentation.Info` surface (`root/1`, `fields/1`, `node/2`, `node_at/2`, `required?/2`, `role/2`, `origins/2`, `diagnostics/1`). Presentation groups are one `:group` kind flagged by `nests_data?` ([[18-decisions|D-006]]); invalid and unsupported declarations produce distinct diagnostics; depth/node budgets and the no-atoms guarantee are property-tested; [[17-end-to-end-example|the end-to-end example]] compiles as the acceptance fixture. Execution record: `docs/superpowers/plans/2026-07-21-phase1-slice1-map-source-static-pipeline.md`. Before step 3 pins the differential test's ID equivalence, resolve node-ID escaping ([[16-open-questions#Core representation|open questions]]).

> [!success] 2026-07-21 — Implementation strategy step 3 complete (JSON Schema adapter)
> `Formentation.JSONSchema` compiles the pinned 2020-12 dialect behind a JSV metaschema pre-pass ([[18-decisions#D-008 — JSV is the JSON Schema validator|D-008]]) and applies the slice-2 UI-hints vocabulary (`order`, `groups`, `fields.*.widget|help`). Node IDs escape segments ([[18-decisions#D-007 — Node-ID segments are escaped, not restricted|D-007]]). The [[18-decisions#D-004 — Two declaration sources from the start|D-004]] differential test asserts Info-equivalence with the map source apart from origins. Deferred to a both-adapters mini-slice: `const`, `description`, `examples`, `default` *(delivered — see the next callout)*. Execution record: `docs/superpowers/plans/2026-07-21-phase1-slice2-json-schema-adapter.md`.

> [!success] 2026-07-21 — Annotations mini-slice complete (`const`, `description`, `examples`, `default`)
> Both adapters carry `description` (→ `help`, with the `fields.*.help` hint overriding and replacing the origin entry), `examples`, and `default` (null defaults warn and drop); string `const` compiles to a fixed single-option field per [[18-decisions#D-005 — Scalar enums are fields, not choice nodes|D-005]]. A second differential fixture (`Formentation.Fixtures.Annotations`) pins Info-equivalence for the new keywords; the property generators cover them. Execution record: `docs/superpowers/plans/2026-07-21-phase1-annotations-mini-slice.md`.

> [!success] 2026-07-22 — Step-4 browser-parameter semantics decided on paper
> Per the step-4 instruction to decide semantics before coding: form state separates transport from decode operation and `FormData` projects already-decoded state ([[18-decisions#D-009 — Form state separates transport from operation|D-009]]); empty-string/null/absent-key handling is a set of typed global codec defaults ([[18-decisions#D-010 — Empty-string, null, and absent-key decode policies|D-010]]); booleans ride the hidden-input transport contract ([[18-decisions#D-011 — Booleans use the hidden-input transport contract|D-011]]); whole-instance validation defers while any decode fails ([[18-decisions#D-012 — Schema validation defers while any decode fails|D-012]]); transitions take a replace-only params envelope ([[18-decisions#D-013 — Transitions take an explicit params envelope|D-013]]). Source discussion: `docs/discussion/encoding-and-decoding.md`. Touched-state tracking, item identity, and branch policies remain [[16-open-questions#Runtime and state|open questions]] with recorded direction *(touched-state since decided — see the next callout)*.

> [!success] 2026-07-22 — Usage/interaction semantics decided (touched tracking)
> Usage (`:unused` | `:used` | `:unknown`) is a first-class interaction axis separate from the decode operation, bookkept per path and populated by transport normalization from LiveView's `_unused_` convention; the `FormData` implementation preserves Phoenix-compatible params so `used_input?/1` keeps working while decoding consumes cleaned domain params; issues are always stored — usage and `action` control visibility only ([[18-decisions#D-014 — Usage is a first-class interaction axis|D-014]]). The dormant patch operation is renamed `:keep`. Source discussion: `docs/discussion/untouched.md`. New open question recorded: non-submitting fields (disabled/read-only) versus replace-mode deletion — [[16-open-questions#Runtime and state|open questions]].

> [!success] 2026-07-22 — Implementation strategy step 4 complete (state and codecs without Phoenix)
> `Formentation.Form` implements pure replace transitions from IEx: the `Formentation.Params` envelope ([[18-decisions#D-013 — Transitions take an explicit params envelope|D-013]]), transport normalization with usage extraction ([[18-decisions#D-014 — Usage is a first-class interaction axis|D-014]]), strict-with-trim scalar codecs and the decode policies ([[18-decisions#D-010 — Empty-string, null, and absent-key decode policies|D-010]], [[18-decisions#D-011 — Booleans use the hidden-input transport contract|D-011]]), candidate materialization from `{:set, _}`/`:unset` operations ([[18-decisions#D-009 — Form state separates transport from operation|D-009]], `:delete` renamed `:unset`), whole-instance validation deferring on any decode failure ([[18-decisions#D-012 — Schema validation defers while any decode fails|D-012]]), opt-in defaults at initialization, and the issue-visibility rule. The JSON Schema adapter carries an opaque instance validator on the definition; map-source forms skip schema validation (recorded in [[16-open-questions#Runtime and state|open questions]]). New compiler warnings: `:required_permits_empty` and `:reserved_property_name`. Spec: `docs/superpowers/specs/2026-07-22-phase1-step4-state-and-codecs-design.md`; execution record: `docs/superpowers/plans/2026-07-22-phase1-step4-state-and-codecs.md`.

> [!success] 2026-07-22 — Non-submitting-fields mini-slice complete (`hidden` and `read_only` hints)
> Both adapters compile `hidden` and `read_only` to flags on `Node.Field` (non-boolean values warn `:invalid_hint_value`); read-only fields are excluded from the replace scope — operation `:keep`, candidate and display from original data, submitted values discarded — while hidden fields decode unchanged ([[18-decisions#D-016 — Participation is definition-driven, not transport-driven|D-016]]). A third differential fixture pins Info-equivalence for the hints, and a property test pins read-only preservation. Step-6 rendering obligations (hidden inputs, readonly/disabled controls, no mirrors) are recorded in the decision. Spec: `docs/superpowers/specs/2026-07-22-phase1-non-submitting-fields-design.md`; execution record: `docs/superpowers/plans/2026-07-22-phase1-non-submitting-fields.md`.

> [!success] 2026-07-23 — Implementation strategy step 5 complete (`Phoenix.HTML.FormData`)
> `Formentation.Form` implements `Phoenix.HTML.FormData` in `Formentation.Phoenix` behind a required phoenix_html dependency and a tested namespace boundary ([[18-decisions#D-017 — Phoenix integration ships in-tree behind a namespace boundary|D-017]]): root and nested-object projection of already-decoded state ([[18-decisions#D-009 — Form state separates transport from operation|D-009]]), the Phoenix-compatible params view feeding a `used_input?/1` contract test ([[18-decisions#D-014 — Usage is a first-class interaction axis|D-014]]), action-gated error tuples keyed for atom access without atom creation, `input_validations` derived per [[18-decisions#D-010 — Empty-string, null, and absent-key decode policies|D-010]], and a property pinning input naming against Plug's param reassembly. Spec: `docs/superpowers/specs/2026-07-23-phase1-step5-formdata-design.md`; execution record: `docs/superpowers/plans/2026-07-23-phase1-step5-formdata.md`.

> [!success] 2026-07-23 — Implementation strategy step 6 complete (projector, components, reference theme)
> `Formentation.Phoenix.Projector` reads any `%Phoenix.HTML.Form{}` through Phoenix conventions — field values, action-gated errors, `Phoenix.Component.used_input?/1` — and emits per-kind render nodes carrying widget resolution (hidden → hint → options → boolean → number → role → text), with a `:widget_fallback` diagnostic when a hint resolves to nonsense; nested objects materialize through `Phoenix.HTML.FormData.to_form/4` rather than `<.inputs_for>`, so nothing injects `_persistent_id` ([[18-decisions#D-019 — Projection is Phoenix-generic|D-019]]). `Formentation.Phoenix.Theme.Reference` is a plain, deliberately unpolished set of per-widget function components called directly by `Formentation.Phoenix.fields/1` and `field/1` — no theme parameter yet — implementing the accessibility contract: labels, `aria-describedby`, `aria-invalid`, fieldsets with legends, a submit-gated error summary, no duplicate ids, escaped schema text; the editable checkbox carries the D-011 hidden input, read-only fields render `readonly`/`disabled` with no hidden mirrors, and selects lead with a blank option ([[18-decisions#D-020 — The reference theme is a markup set, not a contract|D-020]]). `phoenix_live_view` was promoted to a required dependency (amending [[18-decisions#D-017 — Phoenix integration ships in-tree behind a namespace boundary|D-017]] in place). The end-to-end example's static render is pinned as a reviewed Floki snapshot. Spec: `docs/superpowers/specs/2026-07-23-phase1-step6-projector-components-theme-design.md`; execution record: `docs/superpowers/plans/2026-07-23-phase1-step6-projector-components-theme.md`.

> [!success] 2026-07-24 — Implementation strategy step 7 complete (LiveView lifecycle, embedding, demo)
> `Formentation.Form.validate/2` and `submit/2` build the [[18-decisions#D-013 — Transitions take an explicit params envelope|D-013]] envelope (`event: :change`/`:submit`); params extraction from the event payload stays in the handler, with no `use` macro or auto-wired events ([[18-decisions#D-021 — LiveView integration is wrappers plus a demo, not framework machinery|D-021]], later amended by [[18-decisions#D-032 — Submit returns the application decision|D-032]] so `submit/2` returns the success-or-redisplay tuple). `Formentation.Transport.normalize/1` strips `_persistent_id` as transport metadata at every nesting level, alongside `_unused_*`, `_csrf_token`, and `_target`. The reference theme absorbed the step-6 review minors — radio `validation_attrs` now includes `required`, the radio fieldset gains `role="radiogroup"`, the error-summary nil-id branch's style was cleaned up — with the static-render snapshot regenerated. A repo-root `demo/` directory, compiled in dev and test, holds `FormentationDemo.PumpInspectionLive` (the end-to-end example embedded under a hand-written parent form) and `FormentationDemo.NestedLive` (the nested-object round-trip); `mix demo [port]` (default 4000) serves both on Bandit, and the same LiveViews drive the `Phoenix.LiveViewTest` suite. The suite pins a discovery that corrected the spec's working belief rather than confirming it: `Phoenix.LiveViewTest` sends no `_unused_` markers on any event, change or submit alike — the marker convention is JS-client-only, applied by the browser's `LiveSocket` hook, which `Phoenix.LiveViewTest` never runs — so every serialized field is `:used` and blank required fields error from the very first change in the test suite. A real-browser check (2026-07-24, Chrome) then confirmed the actual `_unused_` gating the spec had originally expected (an untouched blank required field stays silent until touched) and that `type="number"` fails raw-input preservation two ways at once (blocking non-numeric keystrokes; sanitizing force-injected invalid text away on the round trip), so the number widget ships as `type="text" inputmode="numeric"`. Spec: `docs/superpowers/specs/2026-07-24-phase1-step7-liveview-design.md`; execution record: `docs/superpowers/plans/2026-07-24-phase1-step7-liveview.md`.

## Risks being retired

1. A source-independent semantic definition can represent basic forms without merely mirroring JSON Schema or HTML controls — proven by compiling the same form from **two sources** ([[18-decisions#D-004 — Two declaration sources from the start|D-004]]).
2. The definition maps cleanly to Phoenix naming, nested params, raw input preservation, errors, and accessible components.
3. Definition, state, projection, and rendering are genuinely separable layers, each testable without the next.

## Supported slice

One JSON Schema dialect, chosen explicitly. Two milestones.

### Milestone A — skeleton

- root object schema with named `properties` and `required`;
- scalar `string`, `integer`, `number`, and `boolean` fields;
- `title`, `description`, `examples`, and `default` as annotations (`default` never mutates data);
- string `enum`/`const` as a **field with a fixed option set** — not a choice node ([[18-decisions#D-005 — Scalar enums are fields, not choice nodes|D-005]]);
- `format`-based roles for date, email, and URI;
- basic numeric and string constraints useful for presentation;
- nested objects (one level is enough to prove paths and `inputs_for`);
- a small UI-hints vocabulary: order, presentation groups, label/help override, hidden/read-only ([[18-decisions#D-016 — Participation is definition-driven, not transport-driven|D-016]]), widget override — first drafted in [[17-end-to-end-example|the end-to-end example]];
- embedding the rendered payload form inside an enclosing hand-written form.

### Milestone B — collections

- homogeneous arrays of supported scalars/objects;
- stable item identity, hidden identity fields, add/remove/reorder LiveView helpers.

Collections are deliberately second: item identity adds a dimension of complexity the skeleton should not start with. They begin only after [[phase-1-north-star-alignment|the alignment gate]], so semantic item templates and presentation collection layouts do not deepen the transitional mixed tree.

### Explicitly deferred

`$ref`, composition, conditionals, remote anything; fingerprints and caching;
`Info.explain/3` and the full `Decision` model; support reports; generated UI
hints; extension APIs and a UI integration contract; a second substantially
different UI. The introspection items land in
[[phase-2-compiler-diagnostics|Phase 2]].

## Two declaration sources

- `Formentation.Source.Map` (working name): a plain Elixir data source in core, zero dependencies. Reference adapter and cheapest fixture format.
- `Formentation.JSONSchema`: the JSON Schema adapter for the subset above, with one validator chosen after evaluating [ex_json_schema](https://github.com/jonasschmidt/ex_json_schema) and [JSV](https://github.com/lud/jsv) against the criteria in [[12-ecosystem-and-dependencies#JSON Schema|Ecosystem and dependencies]].

A differential test compiles the same fixture from both sources and asserts identical `Info` answers apart from origins.

## Simplified provenance

Every node and resolved option carries a compact origin tag — `{:json_schema, pointer}`, `{:map_source, key}`, `{:ui_hints, pointer}`, `{:inference, rule_name}` — sufficient for diagnostics that point at the right place ([[18-decisions#D-003 — Simplified provenance first|D-003]]). No `Decision` structs, no superseded candidates, no derivation chains, no `explain/3`. The full model remains documented in [[09-diagnostics-provenance-introspection|Diagnostics, provenance, and introspection]] as the Phase 2 target.

Node identity is likewise simple: deterministic IDs derived from template paths. Hashed stable IDs arrive with caching in Phase 2 (see [[10-algorithms#Stable node IDs|Stable node IDs]]).

## Deliverables

### Project skeleton

- Mix project with documented Elixir/OTP versions; core namespaces free of Phoenix;
- CI for formatting, warnings-as-errors, tests, and documentation;
- fixture directory organized by feature, seeded from [[17-end-to-end-example|the end-to-end example]].

### Core

- `Formentation.Definition` with a format version;
- nodes for group, field, and unsupported constructs; typed schema location, template path, and instance path;
- origin tags, `Diagnostic`, and `Issue` in minimal form;
- minimal depth/node-count guards (expert-authored schemas arrive at runtime — [[00-use-case|use case, requirement 2]]);
- both source adapters and a direct recursive compiler with named inference functions and explicit UI-hint precedence;
- minimal `Formentation.Info`: `root/1`, `fields/1`, `node/2`, `node_at/2`, `required?/2`, `role/2`, `origins/2`, `diagnostics/1`.

### Runtime and rendering

- `Formentation.Form` state: original data, raw params, decoded value, issues, action, touched/submitted state; explicit empty-string/null/absent-key ([[18-decisions#D-010 — Empty-string, null, and absent-key decode policies|D-010]], [[18-decisions#D-011 — Booleans use the hidden-input transport contract|D-011]]) and default-initialization policies; immutable transitions through a replace-only params envelope ([[18-decisions#D-013 — Transitions take an explicit params envelope|D-013]]);
- codecs for the supported scalars with path-aware decode issues and raw-input preservation;
- `Phoenix.HTML.FormData` implementation for root and nested objects (Milestone B: collections with hidden stable keys);
- a Phoenix transport normalizer separating domain params from transport metadata (`_unused_*`, `_csrf_token`, `_target`), recording per-path usage, and preserving Phoenix-compatible params for `used_input?/1` ([[18-decisions#D-014 — Usage is a first-class interaction axis|D-014]]);
- the smallest projector that walks the full definition each time and emits component-ready render nodes free of schema traversal;
- a plain, accessible, deliberately unpolished reference theme: form wrapper, field wrapper with label/help/errors, text/number/checkbox/select/textarea/date inputs, fieldset groups, error summary;
- whole-form and subtree rendering, composing under an enclosing form.

### Example application

A small LiveView reproducing the end-to-end example: initial data, invalid numeric input preserved on screen, nested object, validation, submission — embedded in a hand-written parent form. Milestone B adds a collection with add/remove.

## Implementation strategy

Classic TDD in thin slices; each iteration leaves the suite green and something demonstrable:

1. **Fixtures first.** Encode [[17-end-to-end-example|the end-to-end example]] as fixtures with expected `Info` answers. Describe expectations through `Info` queries, not struct literals, so tests do not freeze accidental internal layout. *(Map-source fixture done 2026-07-21; the JSON Schema fixture arrives with step 3.)*
2. **Map source → definition → Info.** The whole static pipeline with the simplest source; establish path types here — most later complexity depends on path correctness. *(Done 2026-07-21.)*
3. **JSON Schema adapter.** Validator spike, then compile the same fixture; add the differential test between sources.
4. **State and codecs without Phoenix.** Pure transitions, usable from IEx; decide browser-parameter semantics (checkboxes, empty strings, missing keys) on paper before coding. *(Paper decisions done 2026-07-22 — [[18-decisions#D-009 — Form state separates transport from operation|D-009]] through [[18-decisions#D-014 — Usage is a first-class interaction axis|D-014]]; implementation pending.)* *(Done 2026-07-22 — see the step-4 callout.)*
5. **`FormData`.** Root, then nested objects, using [Phoenix.HTML.FormData](https://hexdocs.pm/phoenix_html/Phoenix.HTML.FormData.html) and the phoenix_ecto implementation as behavioural references. Includes the transport normalizer and the dual-params rule — Phoenix-compatible params for `used_input?/1`, cleaned domain params for decoding ([[18-decisions#D-014 — Usage is a first-class interaction axis|D-014]]). *(Done 2026-07-23 — see the step-5 callout.)*
6. **Projector, components, theme.** Static render of the example; accessibility contract from the start. *(Done 2026-07-23 — see the step-6 callout.)*
7. **LiveView.** Validate/submit lifecycle, embedding, error visibility. *(Done 2026-07-24 — see the step-7 callout.)*
8. **North-star alignment gate.** Separate semantic structure from presentation layout; move `Form` and Phoenix behind query seams; converge the ordinary API on `Definition` plus `Form`. See [[phase-1-north-star-alignment|the detailed plan]].
9. **Milestone B.** Collections, identity, add/remove/reorder on the aligned definition.

Keep the compiler a straightforward recursive function with a context struct. Do not create pass behaviours until [[phase-2-compiler-diagnostics|Phase 2]] extracts them from real, working code.

## Testing strategy

- **Compiler:** every supported keyword and annotation; required vs optional; UI-hint precedence and incompatible-hint diagnostics; unsupported-construct diagnostics instead of crashes; deterministic output regardless of JSON map insertion order.
- **Differential:** both sources produce `Info`-equivalent definitions for shared fixtures.
- **Validator contract:** structured validity and locations; no parsing of formatted messages; accurate dialect reporting.
- **State and codecs:** params take display precedence after interaction; invalid integer retains typed text; empty/absent/null policy; defaults apply only during explicit initialization; immutability.
- **`FormData` contract:** names, IDs, `input_value`, error tuples, `inputs_for`, action-sensitive error visibility.
- **Transport normalization:** Phoenix metadata (`_unused_*`, `_csrf_token`, `_target`) never reaches the decoded instance; normalized usage agrees with `used_input?/1` (contract test, including nested params); a used blank required field shows its error while an unused one stores but hides it; submission exposes all errors; absent markers (`phx-no-unused-field`, plain HTTP) degrade to `:unknown` without fabricated interaction state.
- **Projection:** every projected field maps to a semantic node and Phoenix field; issues attach to the right node; no state mutation.
- **Components:** parse HTML (Floki) and assert labels, IDs, `aria-describedby`, fieldsets/legends, escaping of schema-provided text, error summaries; one reviewed snapshot per example form.
- **LiveView:** initial render, `phx-change` validation, failed decode without input loss, nested updates, submit success/failure, no duplicate DOM IDs; Milestone B lifecycle for collections.
- **Security:** schema text is escaped; no atoms from schema property names; depth/size guards terminate adversarial input.
- **Property tests:** path encode/decode round-trips; map-order independence; compilation terminates within guards.

## Definition of done

- [ ] The supported subset is documented keyword by keyword, including the UI-hints vocabulary.
- [ ] Core compiles without Phoenix or Ash dependencies; only the Phoenix namespace depends on Phoenix.
- [ ] The end-to-end example compiles from both sources with `Info`-equivalent results.
- [x] A documented LiveView renders, validates, and submits the example form, embedded in a parent form.
- [x] Invalid raw input remains visible after validation; decoded submissions match the documented JSON representation.
- [x] Presentation groups render as fieldsets without introducing data nesting.
- [ ] Every resolved option carries an origin tag; diagnostics identify source locations.
- [ ] Unsupported constructs produce structured diagnostics rather than crashes or misleading fields.
- [x] Default components meet the documented accessibility contract; schema-provided text is escaped.
- [ ] No atoms are created from schema property names; depth/node guards are enforced.
- [ ] The [[phase-1-north-star-alignment|north-star alignment gate]] is complete before collection types or transitions are added.
- [ ] (Milestone B) Collection items keep stable identity across add/remove/reorder in LiveView tests.
- [x] The decode/validate interplay policy is written down, even if crude ([[18-decisions#D-012 — Schema validation defers while any decode fails|D-012]]).

## Notes of caution

Carried forward from the merged phase notes:

- Do not equate JSON Schema `default` with data mutation.
- Do not name core fields after HTML input types; roles are not tags.
- Do not treat JSON object order as presentation order; use explicit UI ordering or a documented deterministic fallback.
- Raw params and decoded values are both necessary; do not collapse them.
- Phoenix collection indexes are not stable identity.
- HTML `required`/`min`/`pattern` are progressive hints, not server validation.
- Error visibility follows Phoenix conventions; untouched forms do not display every error.
- Do not make the projector depend on `%Formentation.Form{}` specifically if `%Phoenix.HTML.Form{}` plus a small view interface suffices.
- Do not polish a UI integration contract; that is
  [[phase-3-extensibility|Phase 3]]'s job, extracted from a second editable UI
  and additional proof consumers.
- Do not promise definition serialization.
- Keep invalid schema, unsupported schema, and incompatible UI hints as distinct diagnostics.

## Exit and next phase

The phase ends when the use case's payload forms work end to end for the supported subset, including collections, with an honest list of everything that was deferred.

Before collection work, [[phase-1-north-star-alignment|the alignment gate]]
declares **Aligned Milestone A**: split semantic/presentation definition,
layout-invariant semantic queries and form behaviour, `Definition` and `Form`
as the ordinary model, and Phoenix rendering from the projected `Form` without
a duplicate definition assign. Milestone B then completes collections on that
foundation.
[[phase-2-compiler-diagnostics|Phase 2]] restructures the resulting
grown-but-working compiler into ordered passes and pays back the deferred
introspection: full provenance, explanation, support reports, fingerprints, and
caching.

## Related notes

- [[00-use-case|Motivating use case]]
- [[17-end-to-end-example|End-to-end example]]
- [[03-conceptual-model|Conceptual model]]
- [[07-phoenix-integration|Phoenix integration]]
- [[11-testing-strategy|Testing strategy]]
- [[13-roadmap|Back to the roadmap]]
- [[19-north-star-architecture|North-star architecture]]
- [[phase-1-north-star-alignment|Phase 1 — North-star alignment]]
