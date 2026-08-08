---
title: Decision Log
tags:
  - formentation
  - decisions
status: active
---

# Decision log

Running log of architecture decisions, ADR-style but lightweight. Each entry records context, the decision, and its consequences. Reversing a decision gets a new entry that links back; entries are never silently rewritten. Questions still open live in [[16-open-questions|Open questions]].

## D-001 — Scope is driven by a recorded use case

*2026-07-20*

**Context.** The original notes designed a general form platform without naming a consumer, while the scope-control checklist demanded that features trace to user requirements.

**Decision.** The concrete customer project — spreadsheet migration with expert-defined JSON payloads beside relational data — is recorded in [[00-use-case|Motivating use case]] and is the reference for scope decisions until a second use case is recorded.

**Consequences.** Subset choices (flat objects, groups, enums first; conditionals later; no Ash, no second theme, no remote refs) now have a justification and an expiry condition: a new requirement or use case, not taste.

## D-002 — Phase 1 is a walking skeleton

*2026-07-20*

**Context.** The original roadmap split "static foundation" (no rendering) from "Phoenix runtime". That contradicted the design principle [[02-design-principles#Pragmatism first|"start with one end-to-end useful path"]], and the foundation phase could not retire its own headline risk: whether the IR is any good is only proven by a consumer. It also front-loaded introspection machinery (explain, fingerprints, support reports, generated UI hints) that has no consumer before a renderer exists.

**Decision.** Former Phases 1 and 2 are merged into [[phase-1-walking-skeleton|Phase 1 — Walking skeleton]]: a thin end-to-end slice from declaration to submitted data. Later phases renumber to 2–5. Deferred introspection items move to [[phase-2-compiler-diagnostics|Phase 2]].

**Consequences.** First usable forms arrive one phase earlier; the definition-only API is validated by its first consumer instead of in isolation. The phase is larger, so it is explicitly organized as thin TDD iterations with two milestones. Later phase notes (2–5) are direction sketches expected to be revised by Phase 1 learning.

## D-003 — Simplified provenance first

*2026-07-20*

**Context.** Provenance-as-architecture — `Decision` structs with superseded candidates, derivation chains, `Info.explain/3` — is the most expensive standing commitment in the design, and it serves the library developer and a future schema-editor UI, not the form user. Nothing in Phase 1 consumes it.

**Decision.** Phase 1 records provenance as compact **origin tags** only: `{:json_schema, pointer}`, `{:map_source, key}`, `{:ui_hints, pointer}`, `{:inference, rule_name}` — enough for diagnostics to point at the right place. The full model described in [[03-conceptual-model#Decision|Decision]] and [[09-diagnostics-provenance-introspection|Diagnostics, provenance, and introspection]] remains the target and arrives with [[phase-2-compiler-diagnostics|Phase 2]], where the compiler pipeline gives it structure and the explain API gets its first consumers.

**Consequences.** Every resolved value still knows where it came from, so upgrading to full derivation chains later is additive. `explain/3` is not public API in Phase 1. If a Phase 1 diagnostic turns out to need "why", that is evidence for pulling part of the model forward — record it here.

## D-004 — Two declaration sources from the start

*2026-07-20*

**Context.** "Source-independent definition" was the central claim, but the original roadmap would not have tested it against a second source until Ash integration in the final phase. An IR validated against one source quietly mirrors that source.

**Decision.** Phase 1 ships two source adapters: the JSON Schema adapter and a plain Elixir data source (`Formentation.Source.Map`, working name) living in core with zero dependencies. The same fixture form compiles from both, and a differential test asserts the definitions answer `Info` queries identically apart from origins. See [[17-end-to-end-example|the end-to-end example]] for both declarations.

**Consequences.** The map source doubles as the reference adapter, the cheapest fixture format for tests, and a useful escape hatch for application-defined forms. Cost: a second (small) vocabulary to keep honest. The differential test must define equivalence explicitly (ordering, origins, defaults).

## D-005 — Scalar enums are fields, not choice nodes

*2026-07-20*

**Context.** The `:choice` node kind conflated two different things: a scalar with a fixed option set (`enum` — a select input over one value) and structural alternatives (`oneOf`/union — different subtrees with branch state, branch errors, and discriminators). They differ in state, projection, error mapping, and rendering; conflating them also made `Info.fields/1` skip enum fields.

**Decision.** A scalar `enum`/`const` compiles to a `:field` node with a fixed option set (typically role `:select`). The `:choice` kind is reserved for structural alternatives and does not appear before [[phase-4-dynamic-schemas|Phase 4]].

**Consequences.** Phase 1 needs no `:choice` machinery at all. The conceptual model's node table is updated accordingly. Enum-of-objects and other structural cases remain out of scope until Phase 4 defines them.

## D-006 — One `:group` kind, flagged for data nesting

*2026-07-21*

**Context.** [[16-open-questions|Open question]]: are presentation groups and object-like containers one `:group` kind or two? Slice 1 of Phase 1 had to pick a representation to compile [[17-end-to-end-example|the end-to-end example]], whose fieldset groups flat data while nested objects nest it.

**Decision.** Both compile to `kind: :group` nodes distinguished by a `nests_data?` flag. A data-nesting group contributes an instance-path segment; a presentation group is transparent to instance paths and `Info.node_at/2` looks through it. In the map source, group membership is declared only by the group's `fields:` list; per-field `group:` keys are not part of the vocabulary (the compiler stamps `group` onto member nodes as output, not input).

**Consequences.** Renderers treat every container uniformly and consult `nests_data?` when deriving names and params. The end-to-end example's map declaration dropped a stray `group: "electrical"` on `notes`. If Phoenix work later shows the two behaviours diverging (naming, error routing, projection), splitting into two kinds is a new decision that links here.

> [!note] Superseded as a target by D-029
> The implementation continues to use this representation until
> [[phase-1-north-star-alignment|the north-star alignment gate]] removes it.
> [[#D-029 — Definition and Form are the ordinary public model|D-029]] decides
> that data objects belong to semantic structure and presentation groups belong
> to presentation layout. This entry remains the record of why the Phase 1
> prototype chose the mixed representation.

## D-007 — Node-ID segments are escaped, not restricted

*2026-07-21*

**Context.** Node IDs join template-path segments with `/` and suffix presentation groups with `#`, so a property named `"#electrical"` collided with a group ID and `"a/b"` with a nested path ([[16-open-questions|open question]]). The slice-2 differential test pins ID equivalence across adapters, which forced the decision.

**Decision.** Per-segment escaping: `~` → `~0`, `/` → `~1` (RFC 6901), plus `#` → `~2` as a Formentation extension. Implemented once in `Formentation.NodeId` and used by both adapters; all legal property names compile. Escaping over rejection because expert-authored schemas arrive at runtime ([[00-use-case|use case]]) — rejecting a whole schema over one odd key is worse than an ugly ID.

**Consequences.** IDs stay deterministic and collision-free by construction (property-tested round-trip and uniqueness in `test/formentation/node_id_test.exs`). Node IDs now align with the JSON-Pointer escaping used by `{:json_schema, pointer}` origins. Phase 2's hashed stable IDs ([[10-algorithms#Stable node IDs|algorithms]]) take escaped segments as input.

## D-008 — JSV is the JSON Schema validator

*2026-07-21*

**Context.** [[phase-1-walking-skeleton|Phase 1]] required choosing one validator after evaluating ex_json_schema and JSV against the criteria in [[12-ecosystem-and-dependencies#JSON Schema|Ecosystem and dependencies]]. The fixture pins dialect 2020-12.

**Decision.** JSV (`~> 0.21`). The dialect criterion was dispositive: ex_json_schema supports drafts 4/6/7 only, while JSV has compliance-suite-verified 2020-12 support, ships the metaschema family embedded (offline schema-document validation), returns structured errors with instance and schema locations, has a build-once API, and makes remote `$ref` fetching opt-in behind an allowlist. It sits behind `Formentation.JSONSchema.Validator` — the swap point — with contract tests in `test/formentation/json_schema/validator_test.exs`.

**Consequences.** Three extra runtime dependencies (`abnf_parsec`, `texture`, `idna`). `atoms: false` is explicit in the validator module; format enforcement stays at JSV's default (off). Instance validation (implementation strategy step 4 onwards) reuses the same build/validate flow.

## D-009 — Form state separates transport from operation

*2026-07-22*

**Context.** Step 4 of [[phase-1-walking-skeleton|Phase 1]] requires deciding browser-parameter semantics on paper before coding the state layer. `%Phoenix.HTML.Form{}` deliberately abstracts away facts the state model needs — whether a key was present, whether decoding succeeded, what the user actually typed — and its `input_value/2` may return raw parameter strings. The discussion in `docs/discussion/encoding-and-decoding.md` distilled the requirement into one invariant: never confuse "not submitted", "explicitly cleared", "successfully decoded", and "attempted but undecodable".

**Decision.** `Formentation.Form` records, per field, the transport fact (`:not_provided` | `{:provided, raw}`) separately from the decode operation (`:keep` | `:unset` | `{:set, value}` | `{:invalid, issue}`). The candidate JSON instance materializes only from `{:set, _}` and `:unset`; while any field is `{:invalid, _}` there is no complete candidate instance. (`:delete` was renamed `:unset` at implementation — symmetric with `{:set, _}`, and it marks candidate-instance absence, not destructive mutation of stored data; step-4 spec `docs/superpowers/specs/2026-07-22-phase1-step4-state-and-codecs-design.md`. `:keep` was originally recorded as `:untouched`; renamed by [[#D-014 — Usage is a first-class interaction axis|D-014]], which gives interaction state its own axis.) Decoding precedes `Phoenix.HTML.FormData`: the Phoenix form is a projection of already-decoded state, never the owner of decoding, and `input_value` returns the raw attempted value when decoding failed.

**Consequences.** Raw-input preservation falls out of the model instead of ad-hoc params copying, and the policies in [[#D-010 — Empty-string, null, and absent-key decode policies|D-010]]–[[#D-012 — Schema validation defers while any decode fails|D-012]] become expressible rather than implicit. Deliberately deferred as unconsumed in Phase 1: a participation/stashing dimension (Phase 4 branch work) and stored display values (derivable from transport and operation). Touched/used-input tracking across the transport boundary (Phoenix's `_unused_` convention) was left open here and is decided in [[#D-014 — Usage is a first-class interaction axis|D-014]].

## D-010 — Empty-string, null, and absent-key decode policies

*2026-07-22*

**Context.** Browsers send `""` for every empty text control and cannot distinguish "cleared" from "never typed"; JSON Schema `required` checks key presence only, so each policy choice changes what validation means in practice. [[17-end-to-end-example|The end-to-end example]] forces the question (`"notes": ""`). Ecto's convention (`""` → `nil` via `empty_values`) suits typed changesets, not JSON semantics.

**Decision.** `""` is a transport encoding whose meaning depends on the target type: in a string control it decodes to `{:set, ""}` — preserved, because the schema accepts it and Formentation does not silently redefine the schema; in a typed control (integer, number) it decodes to `:unset`, since empty text was never a candidate value there. `null` is never produced implicitly; it can only occur in original data. Within a replace transition's scope, absent keys decode to `:unset` ([[#D-013 — Transitions take an explicit params envelope|D-013]]). These are global codec defaults; per-node overrides wait for a use case that demands them (scope-control question 6). Two compensations: the compiler emits an advisory diagnostic when a required string property permits empty input ("add `minLength: 1` if non-empty input is intended"), and HTML validation attributes derive from schema plus input policy, never from `required` alone — a bare HTML `required` would reject input the schema accepts. (Amended at step-4 implementation: date/email/URI are *roles on string fields*, not typed controls — they follow the string codec, so a cleared date submits `{:set, ""}`; format conformance belongs to the validator per [[#D-008 — JSV is the JSON Schema validator|D-008]], whose format assertion is currently off. Spec: `docs/superpowers/specs/2026-07-22-phase1-step4-state-and-codecs-design.md`.)

**Consequences.** The example's stored `"notes": ""` stays truthful. A required string submitted empty validates — the diagnostic pushes the fix to the schema author, keeping [[02-design-principles#Validation semantics have a single owner|validation ownership]] intact. Clearing a required typed field produces a genuine `required` error: real absence, in contrast with failed decodes ([[#D-012 — Schema validation defers while any decode fails|D-012]]).

## D-011 — Booleans use the hidden-input transport contract

*2026-07-22*

**Context.** Browsers omit unchecked checkboxes from submissions. Recovering the `false` either couples the codec to absence — conflating "unchecked" with "not rendered" and "not mentioned" — or makes the control's markup guarantee a value. Phoenix already renders a hidden `"false"` input for exactly this reason.

**Decision.** Boolean controls follow a transport contract: the checkbox always submits `"true"` or `"false"` via the hidden-input convention, and the decoder never manufactures `false` from an absent key. The contract belongs to the control's theme contract and is enforced by renderer conformance tests — no more special than requiring a select to submit option values in the expected encoding. Nullable/tri-state booleans use an explicit select or radio control, not a checkbox.

**Consequences.** Absence keeps one meaning across all field types, partial params cannot fabricate values, and `required` on booleans stays meaningful. A theme that omits the hidden input fails conformance tests instead of silently making unchecking impossible; the reference theme's checkbox carries the first such test. The contract binds editable checkboxes only: a read-only boolean renders as a disabled checkbox with no hidden input ([[#D-016 — Participation is definition-driven, not transport-driven|D-016]]).

> [!note] Ownership terminology amended by D-030
> This transport rule remains unchanged. What this entry called the control's
> “theme contract” is now the renderer-prepared widget transport contract that
> every UI must emit faithfully. See
> [[#D-030 — Renderer, UI, theme, and transport responsibilities are separate|D-030]].

## D-012 — Schema validation defers while any decode fails

*2026-07-22*

**Context.** The `"51o2"` walkthrough in [[17-end-to-end-example#A validation round-trip|the end-to-end example]]: omitting the failed field from the validated instance piles a misleading `required`-style error onto the decode issue, while submitting the raw text changes validator semantics — a permissive or union schema might accept it. The [[phase-1-walking-skeleton|Phase 1]] definition of done demands this policy be written down "even if crude".

**Decision.** Phase 1: when any decode issue exists, report every decode issue, retain all raw values, materialize no candidate instance, and defer whole-instance schema validation entirely. Raw undecoded text never enters the validator's instance. The recorded target (not Phase 1 scope) is progressive validation built on three-valued property presence: the decode operation determines the candidate status — `{:set, _}` → present, `:unset` → absent, `{:invalid, _}` → unknown — and `required` evaluates as `present → valid`, `absent → invalid`, `unknown → deferred`. When the progressive validator omits an undecodable property from its temporary instance, it suppresses schema errors whose result depends on that unknown property; a deliberate `:unset` is *known* absence and remains subject to `required`. Transport presence alone can never drive suppression: `{:provided, ""}` proves the control participated in the submission, not that a JSON property exists — only the operation establishes candidate status. Suppression operates on issues normalized inside the validator adapter (instance paths plus affected paths), keeping JSV's recursive error-tree shape behind the [[#D-008 — JSV is the JSON Schema validator|D-008]] boundary.

**Consequences.** Exactly one error per broken field and no fabricated instances. Cost, accepted for Phase 1: schema feedback elsewhere in the form disappears while any decode issue exists; the upgrade path is recorded here so it can be built without changing the state model. This closes the definition-of-done item on decode/validate interplay.

## D-013 — Transitions take an explicit params envelope

*2026-07-22*

**Context.** A bare params map is ambiguous: an absent key could mean "cleared" or "untouched". Step 4's transitions must be pure and usable from IEx — before any Phoenix machinery guarantees full-form posts — and embedding under a parent form ([[00-use-case|use case, requirement 5]]) means the payload's params arrive scoped inside a larger map.

**Decision.** Transitions accept an explicit envelope — values plus a `mode` and a `scope` path — never a bare map. Phase 1 implements `:replace` only: within the declared scope, absent keys decode to `:unset` for participating fields (read-only fields are excluded from the replace scope — [[#D-016 — Participation is definition-driven, not transport-driven|D-016]]). A `:patch` mode (absent keys untouched) is reserved in the envelope shape but rejected explicitly, because no Phase 1 producer exists — LiveView `phx-change`/`phx-submit` and controller posts all deliver the full form.

**Consequences.** Transition semantics are explicit and property-testable instead of implied by transport habits. The `:keep` operation ([[#D-009 — Form state separates transport from operation|D-009]]) stays dormant but named, so patch support is additive. Expiry condition for the deferral: the first real patch producer (per-field events, JS hooks, or a programmatic API) — the first concrete candidate is an input-level `phx-change`, which sends only that input ([[#D-014 — Usage is a first-class interaction axis|D-014]]).

## D-014 — Usage is a first-class interaction axis

*2026-07-22*

**Context.** Error visibility follows Phoenix conventions: untouched forms do not display every error. LiveView's transport convention for this is `_unused_<field>` sibling parameters consumed by `Phoenix.Component.used_input?/1` — which reads `form.params` directly and never asks the `FormData` implementation. The operation model ([[#D-009 — Form state separates transport from operation|D-009]]) overloaded `:untouched` to mean both "this patch does not mention the field" and "the user has not interacted with this control"; the two provably diverge in the most common scenario — a form-level `phx-change` submits every field, so under `:replace` every field carries a real operation on every keystroke while interaction state varies per field. Discussion: `docs/discussion/untouched.md`.

**Decision.** Interaction state is a separate axis from the decode operation. Per-path usage (`:unused` | `:used` | `:unknown`) is bookkept once, in a form-level map keyed by path, populated by transport normalization; the patch operation is renamed `:keep`, freeing "untouched" for interaction vocabulary. Transport normalization produces two parameter views: domain params with Phoenix transport metadata stripped (`_unused_*`, `_csrf_token`, `_target`, and — since [[#D-021 — LiveView integration is wrappers plus a demo, not framework machinery|D-021]] — `_persistent_id`; sort/drop params remain a Milestone B item), and Phoenix-compatible params with the markers preserved. The `FormData` implementation exposes the Phoenix-compatible view as `form.params` so `used_input?/1` keeps working with standard core components, while decoding consumes only domain params. Issues are always complete in form state; usage controls visibility, not validation — an issue renders when the form's `action` is submit or the field's usage is `:used`; cross-field issues attach to a declared primary path, root issues show only after submit. Nested usage propagates to parents (a parent is used when any descendant is) — recorded as Formentation's rule, not Phoenix's, to be verified against `used_input?/1` in a contract test. When markers are absent (`phx-no-unused-field`, plain HTTP posts), usage degrades honestly to `:unknown` and defaults; nothing fabricates interaction data. Property names colliding with reserved transport prefixes get a diagnostic in the LiveView transport adapter for Phase 1; escaping through a reversible encoder is the expected endgame, per the [[#D-007 — Node-ID segments are escaped, not restricted|D-007]] precedent.

Kept deliberately small for Phase 1: the transition envelope grows only `event: :change | :submit` — no `source` field (transport identity must not leak past normalization) and no `:recover` event (LiveView auto-recovery replays a change whose params already carry the markers). The form lifecycle stays the already-planned `action` field; no separate phase concept.

**Consequences.** Standard Phoenix core components work unchanged against a Formentation form; renderer-independent themes read `show_errors?` from the projection instead of knowing about `_unused_`. The transport normalizer's contract is "Phoenix transport metadata never reaches domain decoding", with `_unused_` as the first implemented case. Usage keyed by path meets Milestone B's stable item identities later — index-keyed usage would transfer used-state and errors across a reorder. [[#D-009 — Form state separates transport from operation|D-009]]'s operation list and [[#D-013 — Transitions take an explicit params envelope|D-013]]'s expiry condition are updated in place with links here. New open question recorded: fields that legitimately never submit (disabled, read-only without a hidden mirror) versus replace-mode deletion.

## D-015 — One struct per node kind

*2026-07-22*

**Context.** Slice 1 deliberately shipped a single tagged `%Formentation.Node{}` with a revisit marker ([[031-form-definition|Form definition]], [[16-open-questions|open question]]). By the end of step 4 the shared struct carried 18 fields, 8 of them field-only and 2 group-only; invalid states (a group with a `value_type`, a field with `children`) were representable and excluded only by compiler discipline, and inspecting a definition printed a sea of mostly-nil structs. Step 5 (`FormData`) and milestone B (`:collection`) would each enlarge the consumer surface before Phase 3 extension authors freeze the representation — this was close to the last cheap moment.

**Decision.** Each node kind is its own struct: `Formentation.Node.Field`, `Formentation.Node.Group`, `Formentation.Node.Unsupported`. The struct name is the tag; the `kind` field is gone. `Formentation.Node` remains as the vocabulary module holding the `t()` union and the shared `origin` type. `Group` enforces `nests_data?` so every construction site declares its [[#D-006 — One `:group` kind, flagged for data nesting|D-006]] flavor; `Field` enforces `value_type`. The splitting rule: a kind gets its own struct when its *shape* differs, not when its values differ — scalar fields stay one struct; `:collection` and `:choice` get their own structs when they land. Presentation-group membership (`group:`) and field-level UI hints now apply only to `Field` nodes; a hint claiming a non-field property still places or ignores it silently (edge recorded in [[16-open-questions|open questions]]).

**Consequences.** Illegal states are unrepresentable and `inspect` output self-describes. Consumers dispatch on struct patterns (`%Node.Field{}`), translated one-to-one from the old `kind:` matches. New kinds are additive modules instead of more nil fields on every node. The differential test drops `:kind` from its fact list — kind equivalence is struct equality. Whether `Group`'s two flavors split further stays open and links to D-006.

## D-016 — Participation is definition-driven, not transport-driven

*2026-07-22*

**Context.** [[#D-013 — Transitions take an explicit params envelope|D-013]]'s `:replace` mode reads an absent key as user intent: absence decodes to `:unset`. That inference presumes every field in scope would have submitted a key if it had a value — and HTML breaks the premise: disabled controls never submit, `readonly` exists only for text-like inputs (selects, checkboxes, and radios must be disabled or rendered static to be read-only), and a field hidden from the UI submits nothing unless rendered as a hidden input. Meanwhile the Milestone A hints vocabulary promises `hidden` and `read-only` fields preservation. Recorded as an open question by [[#D-014 — Usage is a first-class interaction axis|D-014]]; source discussion: `docs/discussion/encoding-and-decoding.md`; spec: `docs/superpowers/specs/2026-07-22-phase1-non-submitting-fields-design.md`.

**Decision.** Participation in a replace transition is determined by the definition, not by what the browser happens to submit. Two hints, two trust models. `read_only` is a server-enforced guarantee: the field compiles to a `read_only?` flag on its node and is excluded from the replace scope — its operation is always `:keep`, its candidate and display values come from original data, and submitted values are silently discarded for decoding (readonly text inputs legitimately submit, so arriving values are routine; the Phoenix-compatible params view keeps them verbatim per [[#D-014 — Usage is a first-class interaction axis|D-014]]). `hidden` is presentation only: the field renders as `<input type="hidden">`, submits and decodes under unamended replace semantics — hiding is not protection, and tampering with a hidden input is trust-equivalent to typing in a visible one. Combined, `read_only` wins for decoding and the field renders as nothing. Non-boolean hint values warn (`:invalid_hint_value`) in both adapters. `:keep`, dormant since [[#D-009 — Form state separates transport from operation|D-009]], gains its first producer with pinned candidate semantics: copy the original value at the path, or stay absent when the original has none.

**Consequences.** The read-only guarantee never depends on the client echoing data back, so the theme (Phase 1 step 6) needs no hidden mirrors: `readonly` attributes for text-like controls, `disabled` for selects, checkboxes, and radios. A read-only boolean renders as a disabled checkbox outside [[#D-011 — Booleans use the hidden-input transport contract|D-011]]'s contract, which is scoped to editable checkboxes. Server-side preservation assumes original data is re-suppliable on every transition — free in LiveView, a record-reload obligation for stateless controller flows. [[#D-013 — Transitions take an explicit params envelope|D-013]]'s replace semantics are amended in place: absent keys decode to `:unset` for participating fields.

## D-017 — Phoenix integration ships in-tree behind a namespace boundary

*2026-07-23*

**Context.** Step 5 of [[phase-1-walking-skeleton|Phase 1]] needs `defimpl Phoenix.HTML.FormData, for: Formentation.Form`, but the phase's definition of done says core compiles without Phoenix. phoenix_html is protocols and escaping — not the framework — while the D-014 contract test needs the real `Phoenix.Component.used_input?/1` from phoenix_live_view. Spec: `docs/superpowers/specs/2026-07-23-phase1-step5-formdata-design.md`.

**Decision.** `{:phoenix_html, "~> 4.2"}` is a required dependency and `{:phoenix_live_view, "~> 1.0", only: :test}` supports contract tests. All Phoenix-facing code lives in `lib/formentation/phoenix/` — the enforced boundary is the directory, since a `defimpl`'s generated module name lives under the protocol's own namespace rather than `Formentation.Phoenix.*`; no module outside that directory may reference `Phoenix.*`, asserted by an AST-walking boundary test. The "core compiles without Phoenix" deliverable is met by boundary, not packaging; extracting a `formentation_phoenix` package is a [[phase-3-extensibility|Phase 3]] concern, revisited when the theme contract is extracted. (Amended at step 6: `{:phoenix_live_view, "~> 1.1"}` was promoted from test-only to a required dependency, since HEEx function components live there and phoenix_html 4.x ships no tag helpers — the `~> 1.1` floor because the HEEx formatter normalizes templates to `{...}` body interpolation, which 1.0.0 lacks. The boundary rule is unchanged. See [[#D-019 — Projection is Phoenix-generic|D-019]].)

**Consequences.** Step 5 stays one small `defimpl` instead of package machinery while the representation is still moving (D-015 just churned every consumer). The boundary test makes the directory rule enforceable rather than aspirational. Error entries are keyed by existing atom with string fallback — `String.to_existing_atom/1` never creates an atom, so the no-atoms guarantee holds while `form[:field].errors` works for core components.

## D-018 — Reach is the architecture gate

*2026-07-23*

**Context.** The layer boundaries in [[04-architecture|Architecture]] — a source-independent core with adapters on both sides — were enforced only by convention plus the single AST-walking boundary test from [[#D-017 — Phoenix integration ships in-tree behind a namespace boundary|D-017]]. Reach was already wired into `mix ci` (`reach.check --arch --smells`) but ran against an empty `.reach.exs`, so the gate asserted nothing.

**Decision.** `.reach.exs` declares four layers mirroring the package-boundaries table in [[04-architecture|Architecture]] — `core`, `source`, `json_schema`, `phoenix` — with forbidden layer edges, call bans keeping `Phoenix.*` inside the projection namespace and `JSV.*` behind the [[#D-008 — JSV is the JSON Schema validator|D-008]] swap point, an effects policy (no real IO anywhere in the library), `Source.Shared` internal to the adapters, and full layer coverage. Smells run strict: a new finding fails `mix ci`, matching `credo --strict` and `ex_dna --max-clones 0`. One known finding is baselined in `.reach-baseline.json`: the core↔json_schema layer cycle created by `Formentation.Form` dispatching the opaque validator slot ([[#D-012 — Schema validation defers while any decode fails|D-012]]) directly through the hard-coded D-008 swap point.

**Consequences.** Boundary violations now fail `mix ci` with concrete call-edge evidence instead of relying on review; the D-017 boundary test remains as the spec-level assertion of the Phoenix rule. The baselined cycle is acknowledged debt that dissolves once the validator slot dispatches through a behaviour — natural when a second validating source appears. Two config exceptions document tool limits rather than policy holes: reach classifies the pure `IO.iodata_to_binary/1` and `Enum.each/2` as `:io` (module-level effect allowances in the path modules), and its behaviour-candidate heuristic cannot see `@behaviour` declarations, so the fixtures implementing the extracted `Formentation.Fixture` contract carry a per-check ignore. *Amended:* the baselined `core↔json_schema` cycle and its `.reach-baseline.json` exception have since been removed — instance validation now dispatches through the `Formentation.Validation` behaviour instead of a hard-coded swap point (see [[#D-025 — Instance validation dispatches through a source-neutral behaviour|D-025]]).

## D-019 — Projection is Phoenix-generic

*2026-07-23*

**Context.** Step 6 needs a projector between definition and markup ([[06-runtime-projection|Runtime projection]]'s rendering boundary). [[phase-1-walking-skeleton|Phase 1]] cautions against coupling it to `%Formentation.Form{}` if `%Phoenix.HTML.Form{}` suffices, and [[phase-5-ash-integration|Phase 5]] wants the renderer working against any compatible Phoenix form. Spec: `docs/superpowers/specs/2026-07-23-phase1-step6-projector-components-theme-design.md`.

**Decision.** `Formentation.Phoenix.Projector` consumes a definition plus any `%Phoenix.HTML.Form{}` and reads state exclusively through Phoenix conventions: values via the form field, errors via the action-gated `field.errors` ([[#D-017 — Phoenix integration ships in-tree behind a namespace boundary|D-017]]), usage via `Phoenix.Component.used_input?/1` — so `show_errors?` is computed once, in the plan, and themes never see `_unused_` ([[#D-014 — Usage is a first-class interaction axis|D-014]]). It emits per-kind render nodes ([[#D-015 — One struct per node kind|D-015]]) carrying the `%Phoenix.HTML.FormField{}`; nested objects are materialized directly through `Phoenix.HTML.FormData.to_form/4`, never `<.inputs_for>`, so nothing injects `_persistent_id`. Field access uses the existing-atom-with-string-fallback convention so atom-keyed errors attach without atom creation. One deliberate special case: root and object-level issues for the submit-gated error summary are read from `form.source` when it is a `%Formentation.Form{}`; other sources degrade to visible per-field entries. Widget resolution (hidden → hint → options → boolean → number → role → text) lives in the projector; a nonsense hint falls back to the inferred widget with a `:widget_fallback` plan diagnostic. The dependency posture: `phoenix_live_view` became required (amending [[#D-017 — Phoenix integration ships in-tree behind a namespace boundary|D-017]] in place).

**Consequences.** An `AshPhoenix.Form` is just another `FormData` implementation to project ([[phase-5-ash-integration|Phase 5]]). Projection tests build a form and assert the plan — no HEEx involved — keeping the layers separable. The projector lives behind the D-017/D-018 directory boundary, so core still compiles without Phoenix by boundary, not packaging.

Amended by [[18-decisions#D-027 — Projection reads semantic state through a StateView protocol|D-027]]: the boundary is two-part, not one. Phoenix form conventions carry field-level mechanics; `Formentation.Phoenix.StateView` carries the minimal semantic facts Phoenix cannot express. "Phoenix-generic" means any FormData source projects — through the `Any` fallback when it has no state view — not that every fact comes from `%Phoenix.HTML.Form{}`.

## D-020 — The reference theme is a markup set, not a contract

*2026-07-23*

**Context.** Step 6's deliverable is "a plain, accessible, deliberately unpolished reference theme", while the phase cautions that a theme *contract* is [[phase-3-extensibility|Phase 3]]'s job, extracted from a second implementation. The planning sketch's `theme={MyApp.FormTheme}` attribute predates that caution.

**Decision.** Phase 1 has no theme parameter. `Formentation.Phoenix.Theme.Reference` holds per-widget function components called directly by `Formentation.Phoenix.fields/1` and `field/1`; nothing dispatches through a configurable module. The accessibility contract is documented and Floki-tested against these components: labels for every control, `aria-describedby` for help and visible errors, `aria-invalid`, fieldsets with legends (groups and radio groups), a submit-gated error summary linking to controls, no duplicate ids, all schema text escaped. Conformance obligations bind here: the editable checkbox carries the [[#D-011 — Booleans use the hidden-input transport contract|D-011]] hidden input; read-only renders `readonly`/`disabled` with no hidden mirrors and a read-only boolean drops the hidden input ([[#D-016 — Participation is definition-driven, not transport-driven|D-016]]); selects always lead with a blank option; a required boolean never renders the HTML `required` attribute on its checkbox (HTML required means must-be-*checked*).

**Consequences.** Users cannot plug a theme in before Phase 3 designs the real contract, so nothing informal freezes. The reference components are the executable specification a second theme will be measured against when the contract is extracted.

> [!note] Terminology amended by D-030
> This entry keeps the historical Phase 1 module name and decision title.
> [[#D-030 — Renderer, UI, theme, and transport responsibilities are separate|D-030]]
> reserves **theme** for visual configuration inside one UI. The current
> `Formentation.Phoenix.Theme.Reference` is therefore a reference component
> set/reference UI, not a theme in the target architecture, and should be
> renamed before `0.1.0`. Its accessibility and transport requirements remain
> valid evidence for the later contract.

## D-021 — LiveView integration is wrappers plus a demo, not framework machinery

*2026-07-24*

**Context.** Step 7 needed a lifecycle surface for `phx-change`/`phx-submit` handlers and the phase's example application ([[phase-1-walking-skeleton|Phase 1]]'s LiveView definition-of-done item), while [[07-phoenix-integration|Phoenix integration]] forbids the renderer from owning business submission. Spec: `docs/superpowers/specs/2026-07-24-phase1-step7-liveview-design.md`.

**Decision.** Step 7 introduced `Form.validate/2` and `Form.submit/2` to build the [[18-decisions#D-013 — Transitions take an explicit params envelope|D-013]] envelope internally (`event: :change` / `:submit`); extracting the caller's subtree from the event params stays in the handler, which alone knows its embedding namespace — no `use` macro, no auto-wired `handle_event`, no event-handling helpers beyond these ordinary entry points. Amended by [[#D-032 — Submit returns the application decision]]: `validate/2` remains the form-returning wrapper, while `submit/2` now wraps the transition in the public success-or-redisplay decision. `_persistent_id` joins the [[18-decisions#D-014 — Usage is a first-class interaction axis|D-014]] transport-metadata strip performed by `Transport.normalize/1` at every nesting level, alongside `_unused_*`, `_csrf_token`, and `_target` (amending D-014's "later `_persistent_id`" wording in place with this link). The phase's example application is a repo-root `demo/` directory compiled in dev and test via `elixirc_paths`, not a separate examples project: one LiveView set (`FormentationDemo.PumpInspectionLive`, `FormentationDemo.NestedLive`) serves both the `Phoenix.LiveViewTest` suite and a browser, the latter via `mix demo [port]` (default 4000) on Bandit — so the tested and the browsed version can never drift apart. The end-to-end pump-inspection JSON Schema declaration is demo-owned (`FormentationDemo.PumpInspection`); the test fixture (`Formentation.Fixtures.PumpInspection`) delegates `json_schema/0` and `ui_hints/0` to it while keeping `map_source/0` test-only, because map-source definitions carry no validator — only the JSON Schema adapter can demonstrate live required/format errors ([[16-open-questions#Runtime and state|open question]]). [[18-decisions#D-018 — Reach is the architecture gate|Reach]] grows a `demo` layer permitted to call Phoenix and the library with server/io effects; the library's own layers still forbid depending on it.

**Consequences.** The library's LiveView story stays documentation, not API surface: `validate/2`, `submit/2`, and the pluck-then-call pattern are what the Userguide teaches, nothing framework-shaped ships. The demo lives inside `mix ci`, so it cannot rot silently. Reality diverged from the spec's working belief on markers, corrected in a preceding commit: `Phoenix.LiveViewTest`'s `form/3` plus `render_change/1`/`render_submit/1` re-serialize the *entire* rendered form on every call and carry no `_unused_` markers on any event, change or submit alike — the marker convention is JS-client-only, applied by the browser's `LiveSocket` hook before requests ever reach the server, and `Phoenix.LiveViewTest` never runs that hook. The LiveView suite therefore pins marker-less semantics (every serialized field `:used`, blank required fields erroring from the very first change); a real-browser check independently confirmed the `_unused_` gating the spec had originally expected (an untouched blank required field shows no error until touched) — both are true, for different transports. The Task 11 browser check on `type="number"` failed raw-input preservation two ways at once: Chrome blocks non-numeric keystrokes outright, and a force-injected invalid value is sanitized away on the re-patched round trip — so the number widget shipped as `type="text" inputmode="numeric"` (commit "Fall back number inputs to text with numeric inputmode"), closing the [[16-open-questions#Rendering|open question]] with the fallback rather than leaving `type="number"` in place. [[#D-038 — Semantic value type and abstract widget are orthogonal prepared facts|D-038]] narrows the keyboard hint to `numeric` for integers and `decimal` for general numbers. Because `fields/1` renders the error summary at the top of its own block, an embedded payload form shows the summary mid-page when hand-written inputs precede it — observed in the step-7 browser check and acceptable without slots; repositioning belongs to the [[phase-3-extensibility|Phase 3]] theme contract ([[16-open-questions#Rendering|open question]]).

## D-022 — Browser-real tests are an opt-in, demo-driven Playwright suite

*2026-07-24*

Adopted PhoenixTest + `phoenix_test_playwright` (Playwright 1.61.1, installed via the mise
npm backend) to cover the truths `Phoenix.LiveViewTest` cannot observe — it never runs the
LiveSocket JS hook. The suite drives `FormentationDemo.Endpoint` (Formentation has no HTTP
surface of its own), is tagged `:browser` and excluded from `mix test`/`mix ci`, and runs via
`mix test.browser`. Seed coverage: `_unused_` gating of pristine required errors (D-014),
number-widget raw-text preservation (D-021), error-summary anchor focus, and a valid-submit
smoke. The suite is tagged `browser: :chromium` (a bare `:browser` collides with
phoenix_test_playwright's engine key) and excluded via `exclude: [:browser]`. Motivated by the
step-7 gap and as a dry run for Phase 3 conformance suites.

## D-023 — The demo keeps native validation, behind a toggle

*2026-07-24*

Native HTML5 constraint validation (`required`/`minlength`, emitted by the reference theme)
blocks a real-browser submit of a blank/invalid form, so Formentation's server-side validation
and its submit-gated error summary are unreachable by a click — a browser-only interaction
`LiveViewTest` is blind to, found while writing the unused-gating browser test. Rather than drop
native validation (kept as a genuine feature; already partly traded away by the number widget's
`type="text"` fallback — D-021), the pump-inspection demo gained a checkbox toggling `novalidate`
on the form. It doubles as an exploration aid (native bubbles vs Formentation's accessible
summary) and is what the two submit-driven browser tests flip off to reach the server.

## D-024 — Distribution, license, and CI

Formentation is released under the MIT License (`LICENSE`, Vangelis Tsoumenis, 2026)
and distributed initially as a git-URL dependency (`{:formentation, git:
"https://github.com/kioopi/formentation.git", tag: "v0.1.0"}`), not yet on Hex; a
minimal `package/0` block (`licenses`, `links`) prepares for a later Hex release. CI is
GitHub Actions reusing the pinned `mise.toml` toolchain via `jdx/mise-action`: a
blocking `check` job running the full `mix ci`, plus a non-blocking `browser` job
running `mix test.browser` (isolated from merge gating while CI browser stability is
unproven).

## D-025 — Instance validation dispatches through a source-neutral behaviour

*2026-07-25*

**Context.** `Definition.validator` was an opaque artifact whose executor `Form` hard-coded to `Formentation.JSONSchema.Validator`, creating the core↔json_schema layer cycle that [[#D-018 — Reach is the architecture gate|D-018]] baselined, and blocking any other source from supplying authoritative validation without editing core.

**Decision.** Introduce the core-owned `Formentation.Validation` behaviour (`@callback validate(artifact :: term(), instance :: map()) :: [Issue.t()]`) plus `Formentation.ValidationPlan{module, artifact}` carried on `Definition.validation`; `Form` dispatches `plan.module.validate(plan.artifact, instance)` and names no adapter; `Issue.source` is now `:decode | :validation`; JSON Schema is just one implementer ([[#D-008 — JSV is the JSON Schema validator|D-008]]); `format_version` bumped 1→2; the D-018 baseline and the `core→json_schema` exception are removed. Links: [[#D-008 — JSV is the JSON Schema validator|D-008]], [[#D-012 — Schema validation defers while any decode fails|D-012]], [[#D-018 — Reach is the architecture gate|D-018]].

**Consequences.** Core carries zero adapter references; a fake validator outside the JSON Schema namespace proves JSV-free dispatch; future Ash/Ecto-like/custom sources can supply validation without touching `Form`; a future composite validator can itself implement `Formentation.Validation` holding child plans, while core continues to carry exactly zero or one plan.

## D-026 — Content-derived presence for nested objects

*2026-07-25*

**Context.** Replace transitions materialized every data-nesting group into the candidate, so an absent optional object became `%{}` after an unrelated edit — the object-level counterpart of [[#D-012 — Schema validation defers while any decode fails|D-012]]'s scalar `:unset` vs `{:invalid, issue}` distinction. With a required child, the fabricated `%{}` activated a `required` issue the user never triggered; with a required object, it moved the issue from the group path to a child path. Resolves [GitHub issue #1](https://github.com/kioopi/formentation/issues/1); the approved detailed specification is [the issue comment](https://github.com/kioopi/formentation/issues/1#issuecomment-5075536504).

**Decision.** Nested data-nesting objects use content-derived presence during replace transitions. The object is emitted only when recursive materialization leaves at least one declared or preserved key; presence is decided after declared-child materialization and original unknown/unsupported preservation have run. Requiredness affects validation only and never manufactures instance data. Survivors: `{:set, v}` children, `:keep`'d originals, original unknown keys, original `Node.Unsupported` values, and `{:set, ""}` strings ([[#D-010 — Empty-string, null, and absent-key decode policies|D-010]]). Non-survivors: `required?`, the compiled group node, a raw nested params map, and submitted (not original) unknown keys. `Form` gains an internal `:absent | {:present, map()}` materialization result; the root is always a map. Phase 1 does not represent intentional empty-object presence; originally-present non-object values (`nil`, `"invalid"`) at a group path are dropped when no child survives. The JSON Schema validator is unchanged. Links: [[#D-009 — Form state separates transport from operation|D-009]], [[#D-012 — Schema validation defers while any decode fails|D-012]], [[#D-014 — Usage is a first-class interaction axis|D-014]], [[#D-016 — Participation is definition-driven, not transport-driven|D-016]].

**Consequences.** Presence is semantic state, not an artifact of the compiled tree. The internal presence result is the extension point that future collections, branches, and group-level presence transport must preserve or deliberately supersede — an empty object cannot be represented until such a signal exists. A required-but-absent object now reports `required` at its own path (hidden until submit under [[#D-014 — Usage is a first-class interaction axis|D-014]]) instead of leaking a child-level requirement.

## D-027 — Projection reads semantic state through a StateView protocol

*2026-07-25*

`%Phoenix.HTML.Form{}` stays the primary projection boundary: values, names,
IDs, input validations, per-field errors, `used_input?/1` params, and nested
forms all come from Phoenix. Three facts it cannot carry — whether an
arbitrary action means *submitted*, a source-owned issue-visibility policy,
and root/object issues that deliberately stay out of Phoenix's per-field
convention — dispatch through `Formentation.Phoenix.StateView` on
`form.source`.

The protocol is read-only and projection-focused: three callbacks
(`submitted?/2`, `issue_visibility/3`, `issues/2`), no decoding, mutation,
validation, LiveView events, branch transitions or collection operations.
`@fallback_to_any` keeps arbitrary `Phoenix.HTML.FormData` sources working
with the conservative behaviour the projector had before: `:submit` alone
means submitted, visibility defers to the Phoenix default, and issue
enumeration reports `:unavailable` rather than guessing.

Adapters normalize to `StateView.Issue` (`path` plus displayable `message`)
rather than manufacturing `%Formentation.Issue{}`, because external sources
own their error representations. Consequence: `Formentation.Phoenix.Projector`
names no concrete runtime-state struct and never interprets `form.action`
itself, so an Ash or Ecto adapter supplies a FormData view plus a state view
and the projector is unchanged.

> [!warning] Behaviour change: field-error visibility no longer comes from `used_input?/1`
> For a `%Formentation.Form{}` source, field-error visibility now comes from
> `Form.show_issues?/2` (via `StateView.issue_visibility/3`) instead of
> `Phoenix.Component.used_input?/1`. The two read different state:
> `used_input?/1` reads the *current* `form.params`, while `Form.usage`
> accumulates across transitions (`Map.merge`, never replace —
> `Form.transition/2`, `lib/formentation/form.ex:196`). They agree whenever a
> payload mentions every declared path — the normal LiveView round-trip,
> which is why the whole suite and all 6 browser tests stay green — and
> diverge when a payload *omits* a path entirely (an embedding host plucking
> a subtree, a partial change, a field removed from the DOM). Verified:
>
> ```
> t1  values %{"title" => "ab", "other" => "x"}  → used_input?=true   usage=:used  show_issues?=true   [:minLength]
> t2  values %{"other" => "y"}                   → used_input?=false  usage=:used  show_issues?=true   [:required]
> ```
>
> At t2 the old rule *hid* the `:required` error; the new rule *shows* it.
> This is intended, not a regression: `Formentation.Form` owns the complete
> D-014 visibility policy, and accumulated usage genuinely means "the user
> has interacted with this field" (see `Form.usage/2`'s own `@doc`). Pinned
> by `test/formentation/phoenix/used_input_contract_test.exs`.

## D-028 — Unsupported nodes are a preserve-only capability; blocking is derived at runtime

*2026-07-26*

**Context.** [[#D-015 — One struct per node kind|D-015]]'s `Node.Unsupported` and its compile-time warning diagnostic only ever answered a *definition*-level question — "which declared constructs can this form never edit?" There was no way to ask the *instance*-level question a form actually needs answered before letting a user submit: is a required preserve-only value currently missing, or does the data the form is preserving currently fail validation? Resolves [GitHub issue #3](https://github.com/kioopi/formentation/issues/3).

**Decision.** Unsupported nodes remain a **preserve-only definition capability** — no struct change, no `format_version` bump. Concrete submission blocking is derived, never stored, from the materialized candidate plus the source-neutral `Issue.source: :validation` issues attached to it ([[#D-025 — Instance validation dispatches through a source-neutral behaviour|D-025]]): `Formentation.Form.submission_blockers/1` and `Formentation.Form.submission_status/1` classify each `Formentation.Node.Unsupported` (enumerated statically by the new `Formentation.Info.unsupported_nodes/1`) against the candidate and `form.issues`, producing a `Formentation.SubmissionBlocker` when either a required preserve-only value is absent from an active parent, or the node owns an issue at or below its own path (segment-wise, via the new `Formentation.InstancePath.ancestor_or_self?/2` — never a string prefix). `submission_status/1`'s precedence is `:undecodable` → `{:blocked, blockers}` → `{:invalid, issues}` → `:ready`; blockers win over ordinary issues but nothing is discarded from `issues/1`. An issue at or below an unsupported path is unrepairable by the form and is therefore owned by the blocker; an issue at an ancestor or an unrelated sibling is **not** assigned causally to the unsupported node — doing so would require validator metadata ("which property caused this failure?") Formentation does not have. A map-source definition carries no `ValidationPlan`, so `:unsupported_invalid` can never fire there, but a directly-observed missing-required preserve-only value still produces a blocker, with `issues: []`. Rendering goes through [[#D-027 — Projection reads semantic state through a StateView protocol|D-027]]'s seam rather than around it: the `%Formentation.Form{}` `StateView` implementation translates each blocker into one normalized `StateView.Issue` at the owning node's path — capability text plus any owned validation messages — and drops the issues that blocker already speaks for, so they are not also enumerated bare. Blockers lead the enumeration, then the ordinary path sort. `Formentation.Phoenix.Projector` renders that list with the same generic rule it applies to any source's non-field issues, learns nothing about blockers, and would show an equivalent Ash or Ecto entry unchanged. Links: [[#D-015 — One struct per node kind|D-015]], [[#D-025 — Instance validation dispatches through a source-neutral behaviour|D-025]], [[#D-026 — Content-derived presence for nested objects|D-026]], [[#D-027 — Projection reads semantic state through a StateView protocol|D-027]].

**Consequences.** `Formentation.Info.unsupported_nodes/1` is the extension point a future stricter policy (e.g. an `unsupported: :error` compile option that refuses definitions needing full edit capability) can build on without touching runtime classification. No opaque-replacement escape hatch was added — an unsupported node still cannot be edited by this form, only concretely diagnosed. The causal limit means a root-level or cross-field validation issue continues to render as an ordinary `{:invalid, _}` entry even when an unsupported node sits nearby in the tree; sharpening that requires validator-side metadata this decision deliberately does not invent.

## D-029 — Definition and Form are the ordinary public model

*2026-07-26*

**Context.** Phase 1 proved the difficult end-to-end behaviour before
Formentation's public model was frozen. The resulting internals are deliberately
structured, but ordinary use still exposes too many stages: callers compile a
`Definition`, construct a `Form`, project it to a Phoenix form, pass the
definition beside that form, and encounter projector, render-plan, render-node,
and theme vocabulary. The stored definition also mixes semantic data objects
and presentation groups through
[[#D-006 — One `:group` kind, flagged for data nesting|D-006]], making both
`Form` and Phoenix interpret the same flag for different purposes. Collections
would deepen that coupling. The mixed representation also leaks presentation
into semantic introspection: when a UI group reorders fields, the current
compiler reorders the stored children and `Info.fields/1` returns that layout
order despite documenting declaration order.

**Decision.** Adopt
[[19-north-star-architecture|the north-star architecture]]:

- `Definition` and `Form` are the two ordinary public concepts.
- A static `Definition` and runtime `Form` remain separate.
- `Definition` owns separate semantic structure and presentation layout.
- `Form` is the sole ordinary runtime context and provides access to its
  definition.
- Existing `new/3` and `validate/2` remain the ordinary construction and
  change-event operations. Submission exposes the application decision through
  the complete `submission_status/1`, including blockers; lower-level
  transition machinery may remain advanced.
- `Info.fields/1` returns semantic declaration order. Presentation traversal
  independently returns layout order. Correcting the current reordered-group
  result is an intentional pre-`0.1.0` behaviour change.
- Phoenix fields keep accepting `%Phoenix.HTML.Form{}`. In normal usage that
  form is projected from `%Formentation.Form{}`, and the component derives its
  definition from `form.source` rather than receiving a duplicate
  `definition` assign. Phoenix `as` and `id` remain caller-owned.
- Derivation recovers the projection root as well as the definition. A nested
  projected form keeps the root `%Formentation.Form{}` as its source, so
  deriving only the definition would render the whole form under a nested name.
- Arbitrary `Phoenix.HTML.FormData` plus an explicit definition and state view
  remains a permanent low-level integration path. First-class state
  integrations should eventually wrap their backing state in
  `%Formentation.Form{}`.
- Projection/preparation remains independently testable but is not a mandatory
  user-visible lifecycle stage.
- Definition adapters and state adapters are distinct extension categories.
- Phoenix is a renderer. A UI is a component-library integration. “Theme”, if
  retained, means visual configuration within a UI rather than the UI adapter
  itself.
- UI contracts and a stable prepared-view contract remain deferred until a
  second implementation proves them.

Breaking representation and API changes are allowed before `0.1.0`. The
alignment follows
[[phase-1-north-star-alignment|the Phase 1 north-star alignment plan]] before
Milestone B collections. Implicit typed-source dispatch is not part of this
gate; explicit `adapter:` selection remains sufficient until extensibility work
creates a real need. Built-in sources gain stable symbolic keys — `:map` and
`:json_schema` — accepted by `compile/2` as well as by the façade, so the
ordinary compile-once-and-reuse path never has to name an adapter
implementation module. That is explicit selection, not inference.

**Consequences.** D-006 remains accurate history and current implementation
documentation until the cutover, but is no longer the target representation.
Both adapters will produce split semantic and presentation structures;
`Form` will consume semantic queries; Phoenix preparation will traverse layout
and resolve semantic references. The old mixed root tree and `nests_data?` will
then be removed with a definition-format bump. `Projector`, `RenderPlan`, and
the built-in reference component set may remain structured internals without
being ordinary public nouns. All existing correctness invariants—raw-input
preservation, source-owned validation, used-input state, nested presence,
preservation, blockers, path safety, accessibility, and browser transport—are
mandatory acceptance criteria for the migration.

## D-030 — Renderer, UI, theme, and transport responsibilities are separate

*2026-07-26*

**Context.** D-029 establishes Phoenix as a renderer and defers a public UI
contract until independent implementations can prove it. The detailed planning
exposed several durable ownership decisions that are not contingent on the
eventual struct or behaviour names. The current Phase 1 vocabulary also uses
“projector,” “renderer,” and “theme” for overlapping concerns. Most
importantly, the reference checkbox proves that markup participates in decoding
transport: its hidden `false` input implements D-011. Treating a UI as “only
markup” without a prepared transport contract would let another component set
silently change form semantics.

**Decision.** Adopt
[[20-renderer-ui-model|the renderer and UI model]] as the canonical ownership
note:

- A **renderer** owns integration with an output environment and prepares
  concrete occurrences, bindings, names, IDs, visible issues, transport facts,
  localization/formatting facts, capabilities, and fallbacks. Phoenix is the
  first renderer.
- A **UI integration** maps a prepared view onto one component library or
  application design system. It owns concrete components and markup
  composition, not semantic traversal, decoding, validation, branch selection,
  or submission policy.
- A **theme** is visual configuration within one UI: tokens, density, colour
  mode, spacing, sizing, or a component-library theme name. It is not a
  component registry or form adapter.
- Widget resolution has three distinct levels: semantic role, abstract
  interaction widget, and concrete UI component.
- A prepared view is source-neutral but may be renderer/environment-specific.
  Phoenix preparation may expose `%Phoenix.HTML.FormField{}` and
  Phoenix/LiveView transport facts; it must not expose JSON Schema, map, Ash, or
  native-state internals.
- A UI does not choose transport or decoding semantics. Renderer preparation
  supplies a typed transport contract—primary/auxiliary controls, names,
  cardinality, raw values, and unchecked/absent/blank/null behaviour—and the UI
  emits it faithfully.
- Renderer preparation uses an application-supplied translation facility to
  turn visible structured issues into presentation-ready localized content.
  Editable `control_value` remains separate from localized/read-only
  `display_value`; rerendering never replaces an invalid raw attempt with
  formatted output.
- The baseline UI contract is implementable with stateless Phoenix function
  components and ordinary HTML POST. LiveComponent-, hook-, upload-, or
  browser-state widgets use a separate advanced tier.
- A public prepared-view/UI contract must be earned by the built-in UI and a
  substantially different editable UI that compiles in a separate Mix project.
  Executable module-graph checks, owned by the UI package because this
  repository's policy cannot see separately compiled code, forbid source
  adapters, private definition representation, private semantic query helpers,
  and private preparation structs.
- Read-only review/confirmation rendering is an additional proof consumer,
  especially for display formatting and container mapping, but does not replace
  the second editable UI.
- Shared conformance asserts typed facts, structural DOM/accessibility,
  render-to-params-to-decode round trips, and browser behaviour. It does not
  require exact HTML goldens across UIs.
- Compiler/runtime resource budgets and preparation cost are engine-owned
  correctness concerns, not UI capabilities.

The exact prepared structs or queries, UI descriptor, component callbacks,
capability vocabulary, override precedence, transport structs, localization
representation, and interactive event API remain Phase 3 prototype decisions.

**Consequences.** [[15-glossary|The glossary]] and
[[14-naming|naming note]] use the new vocabulary. D-020 remains the historical
record of why Phase 1 did not freeze a configurable contract, but its
`Formentation.Phoenix.Theme.Reference` name is transitional. The current
`Formentation.Phoenix.Projector` performs render preparation and **was renamed**
in [[18-decisions#D-041 — Projected Phoenix forms are the ordinary rendering input|D-041]]
(2026-08-05) to `Formentation.Phoenix.RenderPreparation` and
`Formentation.Phoenix.ReferenceComponents`, so “projection” is available for
`Form` → `%Phoenix.HTML.Form{}`. Phase 3 must build the second UI and review
consumer concurrently with the contract, publish the round-trip conformance
suite, define capability-failure developer experience, and establish resource
limits/performance evidence before exposing a stable prepared view.

## D-031 — Phoenix preparation consumes presentation descriptors

*2026-07-26*

**Context.** [[#D-029 — Definition and Form are the ordinary public model|D-029]]
requires semantic structure and presentation layout to become separate
contracts before the stored `Definition` representation is split. After the
semantic query work, `Formentation.Phoenix.Projector` was still interpreting
the current mixed tree directly: it started from `Info.root/1`, matched raw
node structs for layout, and used the `nests_data?` storage flag to decide
whether a group was a fieldset or a nested Phoenix form. Resolves
[GitHub issue #17](https://github.com/kioopi/formentation/issues/17).

**Decision.** Add a temporary presentation query seam under
`Formentation.Info`: `presentation_root/1` returns the root layout descriptor
and `presentation_at/2` returns `{:ok, descriptor}`, `:not_found`, or
`:unsupported` for a semantic instance path. The descriptor vocabulary lives
under `Formentation.Info.Layout` and is deliberately small:
`Object` for root/nested semantic-object layout boundaries, `Field` for scalar
field references, and `Group` for presentation-only grouping. Object and field
descriptors carry normalized `Formentation.InstancePath`s; group descriptors
carry layout identity only. The compatibility implementation derives these
descriptors by walking the current mixed tree on demand, with an explicit
semantic-path cursor. It skips unsupported nodes in renderable traversal but
keeps unsupported semantic paths distinguishable through lookup.

`Formentation.Phoenix.Projector` now dispatches on those descriptors and
resolves semantic facts through `Info` at each descriptor's path. Presentation
facts used by projection are label/help, widget hint, hidden-control intent,
layout identity, and child order. Semantic facts such as value type, role,
fixed options, read-only participation, validation attributes, unsupported
classification, and diagnostic template path still come from semantic queries
or Phoenix FormData. Nested Phoenix descent is triggered by an object
descriptor being exactly one segment below the current object context, never by
parsing a group id. The `Phoenix.HTML.FormData` implementation for
`Formentation.Form` now verifies nested-object targets with
`Info.semantic_kind/2` instead of `nests_data?`.

**Consequences.** The public rendering surface is unchanged:
`Projector.project/2`, `project_at/3`, `RenderPlan`, `RenderNode`, component
assigns, reference-theme markup, names, IDs, visibility, summaries,
diagnostics, hidden/read-only omission, and unsupported omission keep their
existing behaviour. Presentation order is now independently test-pinned from
semantic declaration order: a definition can enumerate fields semantically as
`["a", "c"]` while Phoenix renders the layout order `["c", "a"]`. No second
stored tree, format-version bump, UI registry, or Phase 3 contract was added.
The one intentional adapter behavior change is that `Source.Map` now rejects
duplicate property names with `:duplicate_property`, because duplicate semantic
references cannot satisfy the descriptor invariant. The later split-storage
work replaces the compatibility query implementation without another projector
rewrite.

## D-032 — Submit returns the application decision

*2026-07-26*

**Context.** A2 of
[[phase-1-north-star-alignment|the Phase 1 north-star alignment gate]] exposed a
bug in the demo submission policy: it treated "no ordinary issues and a decoded
candidate" as success. That is not the same as readiness. A required
unsupported preserve-only node can leave `candidate/1 == {:ok, map}` and
`issues/1 == []` while `submission_status/1` is `{:blocked, blockers}`.
Resolves [GitHub issue #19](https://github.com/kioopi/formentation/issues/19).

**Decision.** `Formentation.Form.submit/2` is the ordinary application-facing
submission operation and returns exactly:

```elixir
{:ok, candidate :: map(), submitted_form :: Form.t()}
| {:error, submitted_form :: Form.t()}
```

It first performs the same pure full-form `:submit` transition as before, then
classifies only through `submission_status(submitted_form)`. Only `:ready`
returns the `:ok` branch. `:undecodable`, `{:blocked, blockers}`, and
`{:invalid, issues}` all return `{:error, submitted_form}` for redisplay. The
failure tuple does not duplicate issues, blockers, or status; callers inspect
the returned form through `submission_status/1`, `issues/1`, and
`submission_blockers/1` when they need detail. `validate/2` remains the
form-returning change-event operation, and `transition/2` remains the advanced
form-returning primitive.

**Consequences.** This is an intentional pre-`0.1.0` breaking correction: no
legacy form-returning `submit/2`, compatibility shim, companion result API, or
stored submission-result field remains. Demo LiveViews pattern-match the public
result directly and clear any previous success output on every error branch.
Ordinary docs now teach the tuple as permission to persist; `candidate/1` is
materialization output, not a readiness decision. The failure tuple's smaller
shape deliberately means a caller or projection that needs the reason asks
`submission_status/1`/`submission_blockers/1` again; repeated classification is
accepted here to keep one canonical status representation.

## D-033 — Phase 1 layout covers each supported occurrence exactly once

*2026-07-26*

**Context.** Issue #18 splits stored semantics from stored presentation layout.
The required safety invariant is soundness: every presentation object or field
reference must resolve to exactly one semantic occurrence of the expected kind.
The implementation could stop there and allow a supported semantic field to be
omitted from layout, or to appear more than once. That would make “which
semantic fields are shown?” a real layout-specific question. Today, however,
Milestone A renders every supported scalar occurrence exactly once; even
`hidden?` is a presentation mode that emits a hidden control, not omission.
Unsupported preserve-only occurrences are the only semantic occurrences with no
renderable scalar reference.

**Decision.** For Phase 1 built-in adapters, native presentation layout is a
total, unique coverage of supported semantic object and field occurrences:

- every presentation reference resolves by semantic occurrence identity;
- no supported semantic occurrence may be referenced more than once;
- every supported semantic object and scalar field emitted by a built-in
  adapter must be represented exactly once in layout;
- unsupported occurrences remain semantic-only and are never referenced by
  presentation controls;
- hiding remains a presentation fact, not layout omission.

This is an invariant of the native definition finalizer and therefore an
architecture commitment for Milestone A, not a renderer convention.

**Consequences.** For now, the answer to “which supported fields are shown?” is
“all of them exactly once,” with presentation deciding order, grouping, labels,
help, widget preference, and hidden-control mode. Phase 3 may introduce
conditional visibility, optional prepared views, repeated layouts, or explicit
review/edit projections, but those require a new decision that weakens or
specializes this invariant. The invariant also gives adapters and future query
indexes a simple lookup contract: a supported semantic occurrence has at most
one layout descriptor in the built-in editable layout.

## D-034 — Phoenix renderer DOM identities are typed and injective

*2026-08-03*

**Context.** The Phase 1 reference components inherited Phoenix's
underscore-joined field ids and derived help, error, and radio-option ids by
string suffix. That creates collisions: `notes_help` can collide with the help
for `notes`, and `a_b` can collide with a nested `a.b` occurrence. A prefix
for new group ids cannot solve the general problem because source field names
remain arbitrary strings. Collections also require occurrence identity rather
than a template-only layout identity. Resolves [GitHub issue #29](https://github.com/kioopi/formentation/issues/29).

**Decision.** `Formentation.Phoenix.DOMIdentity` mints every renderer-owned
DOM id from a non-empty render namespace, a closed owner kind, a closed element
part, and typed occurrence identity. Its documented stable format is
`ftn--namespace--kind--part--identity...`. Binary tokens use a byte-wise,
fixed-width `-XX` escape, so `--` is structural only; leading digits are
escaped to preserve the distinction between string and integer instance-path
segments. Fields use absolute instance paths, objects their occurrence paths,
and groups their layout id plus enclosing object occurrence path. The finalized
definition invariant rejects duplicate layout ids across presentation objects,
groups, and fields; the enclosing occurrence path then separates repeated
collection items. Field parts are control, composite-widget container, help,
errors, and indexed radio options; object/group parts are container and help.
No hash, random value, counter, traversal index, or occupied-id allocation
participates in uniqueness.

**Consequences.** DOM identity is renderer-owned rather than a side effect of
Phoenix transport naming: `Phoenix.HTML.FormField.name` remains unchanged, and
its `id` is no longer the authoritative identity for renderer markup. Exact ID
spelling is a public compatibility contract so applications can use it in
tests, selectors, and styles. The primitive itself is internal pending the
Phase 3 prepared-view contract. [[18-decisions#D-035 — Phoenix rendering prepares and consumes DOM identities|D-035]]
records its adoption by the Phoenix renderer. [Issue #7](https://github.com/kioopi/formentation/issues/7)
can now add group help without inventing a parallel group-id scheme.

## D-035 — Phoenix rendering prepares and consumes DOM identities

*2026-08-03*

**Decision.** Phoenix projection resolves one namespace per render: explicit
`dom_namespace`, then `form.id || form.name`, otherwise an actionable error.
`FieldDOM`/`GroupDOM` carry exact ids; reference components consume them without
suffix derivation; radio summaries target their rendered container; and Phoenix
transport names remain unchanged.

**Consequences.** Submitted names still compose under a parent namespace such
as `asset[payload][...]` (use-case req. 5), while renderer-owned DOM ids are
collision-proof and occurrence-scoped. This completes [issue #30](https://github.com/kioopi/formentation/issues/30).

## D-036 — Group help uses prepared Phoenix identities

*2026-08-03*

**Context.** Presentation objects and presentation groups already owned help,
but Phoenix preparation dropped it. D-034 and D-035 had already made exact
container and help identities available on `GroupDOM`; a group-specific suffix
or naming formula would duplicate and weaken that contract.

**Decision.** `RenderNode.Group` carries help text from both presentation
object and presentation-group descriptors. The reference theme renders it as
escaped `.ftn-group-help` text immediately after the legend and associates the
fieldset with the exact prepared `GroupDOM.help` id. `fields/1` preserves root
help in the plan but intentionally renders only root children; explicit
`field path={[]}` renders the root group and its help. Built-in source
vocabularies do not gain presentation-group help keys, and group-level error
summary links remain separate work. As with field help, an empty binary help
value remains a rendered, associated help element.

**Consequences.** The compiler-to-renderer information-preservation invariant
now includes group help without changing the stored definition format, field
names, or DOM identity grammar. A future root/page-help API and group-summary
linking work can build on the preserved content and prepared container ids.

## D-037 — Documentation generation is a `mix ci` gate

*2026-08-03*

**Context.** The project rule "keep `mix docs` warning-free" was a manual habit
with nothing enforcing it, so a broken reference or a link to a moved file could
land and only surface at release time — while every other quality property
(formatting, credo, types, duplication, architecture, vault wikilinks) was
already a gate.

**Decision.** `mix ci` runs `mix docs --warnings-as-errors` after
`vault.links` and before `test`. Because `mix ci` runs in `MIX_ENV=test`,
`ex_doc` becomes a `[:dev, :test]` dependency, and `docs.filter_modules` now
selects modules by compile source — only those under `lib/` are documented —
instead of naming the demo modules explicitly. That keeps the gated doc surface
identical to the `mix docs` a maintainer runs in `:dev`, where
`elixirc_paths/1` also compiles `demo/` and, under `:test`, `test/support/`.

**Consequences.** Documentation breakage fails the same gate as a compiler
warning, so the manual check disappears from the workflow rules. `mix ci` gets
slower by one doc build, and `doc/` is written on every run (already
gitignored). Filtering by compile source means a new non-shipping module under
`demo/` or `test/support/` is excluded automatically, with no filter list to
maintain; a module that should be documented must live in `lib/`.

## D-038 — Semantic value type and abstract widget are orthogonal prepared facts

*2026-08-04*

**Context.** Integer and general-number fields share the `:number_input`
interaction family, but their useful soft-keyboard hints differ. Preserving
only the resolved widget at the Phoenix prepared-node boundary made both render
as `inputmode="numeric"`, even though the number codec accepts signs,
fractions, and exponents. `role` cannot carry this distinction: option sets and
explicit declarations may overwrite it. This narrows D-021's original numeric
keyboard hint. Resolves [GitHub issue #8](https://github.com/kioopi/formentation/issues/8).

**Decision.** Every `RenderNode.Field` carries the normalized semantic
`value_type` alongside its resolved `widget`. Integer and number still share
`:number_input`; the reference theme selects `inputmode="numeric"` only for
that widget with `value_type: :integer`, and `inputmode="decimal"` only for
that widget with `value_type: :number`. Both remain `type="text"`; the codec
is the sole authority for accepted grammar. Numeric semantic value types also
drop `min`/`max`/`step` from `:number_input` and explicit `:text_input` text
controls, and from textareas or selects, where those attributes are
unsupported. Prepared options retain declared scalar values; themes canonicalize
both option and current control values to strings when emitting and comparing
`selected`/`checked` state.

**Consequences.** Custom themes can distinguish integer from number without
consulting a definition or source adapter, while widget intent still wins: a
numeric field rendered as text, select, or hidden input receives no numeric
input mode. This does not preserve `role` or `required?` at the prepared-node
boundary; [GitHub issue #37](https://github.com/kioopi/formentation/issues/37)
owns preserving those semantic facts and deciding the schema-requiredness
contract. No definition format change is required.
Unsupported non-scalar option declarations are a source-validation concern
owned by [GitHub issue #38](https://github.com/kioopi/formentation/issues/38).

## D-039 — `mix test.dev` is the development inner loop

*2026-08-04*

**Context.** Development commands were ad-hoc strings — `mix format <file> &&
PORT=4447 mix test <file>` and variants. Every variant is a distinct command to
approve, and the `PORT` prefix was cargo cult: nothing in the project reads
`PORT`, and non-browser tests start the demo endpoint with `server: false`, so
the suite binds no socket at all.

**Decision.** One command, `mix test.dev`, formats the project and then runs
`mix test`, adding `--stale` only when the caller named no test target. Naming a
target suppresses `--stale`, because combining them selects the intersection —
empty whenever the named file is not itself stale, which exits 0 having run
nothing. `--failed` is treated the same as a named target: `mix test` itself
refuses to combine `--failed` with `--stale`, so suppressing `--stale` there
too is not optional. The task lives in `test/support/`, so it never ships in
the package, and `cli/0` runs it in `MIX_ENV=test`.

**Consequences.** The workflow rule in `CLAUDE.md` names one command instead of
a pattern to improvise on. Filename-based test selection was rejected: a naive
`lib/x.ex` → `test/x_test.exs` map misses 29 of 49 lib modules, so it would
report green having run nothing, and the whole suite ran in 4.6 seconds anyway
(`mix test` alone, 672 tests, measured at `1e4482e`). Both the count and the
timing move as the suite grows — by this commit it is 704 tests, running
standalone in ~4-5s and folding into a `mix ci` run measured at 28.5s total —
so treat either figure as a snapshot, not a bound. That `--stale` selects
nearly the whole suite for a change to a central module is a coupling signal
worth investigating separately.

## D-040 — Browser tests bind an ephemeral port

*2026-08-04*

**Context.** The browser lane hardcoded `127.0.0.1:4002`, the only socket the
suite ever binds. Two concurrent browser runs collided, and the fix people
reached for was an environment-variable prefix on the command.

**Decision.** `Formentation.FreePort.pick/0` binds port 0, reads back the port
the kernel assigned, and releases it; `test/test_helper.exs` configures the
endpoint with that port before boot. Pre-boot rather than `http: [port: 0]` plus
`Bandit.PhoenixAdapter.server_info/2`, because `Phoenix.Endpoint` caches `url/0`
from the `:url` config at init and would otherwise report port 0 unless also
driven through `config_change/2`.

**Consequences.** Concurrent browser runs no longer collide and no command needs
a `PORT` prefix. `base_url` and `test/browser/demo_http_smoke_test.exs` need no
change, both reading the endpoint's own `url/0`. A small window remains between
releasing the probe socket and the endpoint binding; losing that race fails
loudly at boot rather than silently.

## D-041 — Projected Phoenix forms are the ordinary rendering input

*2026-08-05*

**Decision.** `Formentation.Phoenix.fields/1` and `field/1` accept a typed
`Phoenix.HTML.Form`. When that form is projected from `Formentation.Form`, its
definition and projection-root path are recovered from the native projection;
the caller supplies neither a duplicate definition nor renderer-owned name or
ID. A nested projected form renders only its own object subtree and resolves
`field/1` paths relative to that root. Any other FormData source remains a
permanent advanced route and must provide `definition:` explicitly. Render
preparation, render plans/nodes, and reference components are internal
implementation seams: documented for IEx users but excluded from public ExDoc.

**Consequences.** A native form with missing or malformed projection metadata
fails rather than falling through to the generic route, and a mismatched native
`definition:` cannot override the source definition. `StateView` remains the
source-neutral contract for the generic route. This supersedes the naming
obligation recorded in
[[18-decisions#D-030 — Renderer, UI, theme, and transport responsibilities are separate|D-030]]:
`Formentation.Phoenix.Projector` is now `RenderPreparation` and
`Formentation.Phoenix.Theme.Reference` is now `ReferenceComponents`, so
“projection” is available for `Form` → `%Phoenix.HTML.Form{}` as intended. It
narrows [[18-decisions#D-019 — Projection is Phoenix-generic|D-019]]:
preparation branches on whether a source is native, but only to recover
*metadata* (definition and projection root) — submission, issue visibility,
and non-field issues still cross the `StateView` seam unchanged. It renames
the subject of [[18-decisions#D-020 — The reference theme is a markup set, not a contract|D-020]]
without changing it. No UI registry, component selection behaviour, or stable
prepared-view API is introduced.

Two consequences are observable in markup. A nested plan's DOM namespace is
the nested form's joined id (`asset_payload_address`) rather than the root's,
so the same field's renderer-owned id depends on which form rendered it while
its Phoenix name does not; each plan stays internally consistent. And because
the plan root of a nested form *is* the projected object, `fields/1` renders
that object's children without its fieldset, legend, or group help — those are
rendered by `field path={[]}` on the same form. The submit-gated error summary
is scoped to the projection subtree and rendered only at the projection root
unless `summary={true}`/`summary={false}` says otherwise, so composing under
`<.inputs_for>` yields one `role="alert"` region rather than two.

## D-042 — Map source validates scalar options at compile boundary; hard-errors on invalid option declarations

*2026-08-06*

**Context.** `Formentation.Source.Map` previously copied `:one_of` options lists without validating list element types or verifying that `:one_of` was a list. This allowed malformed declarations like `one_of: [%{a: 1}]` or `one_of: "oops"` to compile without error and fail only during downstream rendering. Meanwhile, `Formentation.Definition.Semantic.Field` declares `@type option :: String.t() | number() | boolean()`.

**Decision.** The Map source validates `:one_of` option declarations at the compilation boundary:
- Valid option values must be scalars (`String.t()`, `number()`, or `boolean()`). Accepted values are retained verbatim without stringification, sorting, or deduplication.
- Invalid member types (e.g. maps, tuples, nested lists, atoms, or `nil`) or non-list `:one_of` declarations other than explicit `nil` produce an `:invalid_declaration` error diagnostic. An explicit `one_of: nil` is treated as absent and emits an `:unsupported_keyword` warning.
- Hard-error compilation failure (`{:error, diagnostics}`) is used for malformed `:one_of` declarations in the Map source (matching `fetch_examples`), rather than field-level degradation (`Semantic.Unsupported` used by JSON Schema for `enum` violations). Map declarations are author code, so a malformed `:one_of` declaration represents an author bug that should fail compilation explicitly rather than silently degrading.

**Consequences.** Malformed option sets fail compilation immediately at the source boundary with structured diagnostics pointing to the exact indexed origin path (`{:map_source, source_path ++ [:one_of, index]}`). Valid numbers and booleans remain first-class scalar options on Map source fields. The supported option set is currently source-dependent: Map accepts strings, numbers, and booleans, while JSON Schema accepts strings only; reconciling that difference is out of scope for this decision.

## D-043 — Semantic `role` and schema `required?` join `value_type` as flat prepared facts

*2026-08-07*

**Context.** [[#D-038 — Semantic value type and abstract widget are orthogonal prepared facts|D-038]] added `value_type` to `RenderNode.Field` but explicitly deferred `role` and `required?`, leaving that to [GitHub issue #37](https://github.com/kioopi/formentation/issues/37). `Formentation.Definition.Semantic.Field` already carries both facts pre-preparation; only `role` is read in passing (for widget inference) and neither reaches the prepared struct. A custom theme therefore cannot distinguish an `:email`-role field from a plain string, or tell whether a field is genuinely schema-required, without reaching back into the source `Definition` — which the renderer/UI boundary ([[20-renderer-ui-model|Renderer and UI model]]) forbids.

**Decision.** `RenderNode.Field` gains two more flat fields, `role` and `required?`, populated directly from `Semantic.Field` during preparation — the same additive, non-nested shape D-038 used for `value_type`. `required?` is the schema fact only; it is documented on the struct as presentation/accessibility-only (asterisks, `aria-required`, etc.) and must never be used by a theme to emit or infer the native HTML `required` attribute. The HTML constraint attribute continues to come solely from `validations[:required]`, governed unchanged by [[#D-010 — Empty-string, null, and absent-key decode policies|D-010]]'s existing policy of deriving HTML validation attributes from schema plus input policy, never from requiredness alone. The reference theme carries a conformance test asserting it never derives the HTML `required` attribute from `required?`, the same enforcement pattern [[#D-011 — Booleans use the hidden-input transport contract|D-011]] established for the checkbox hidden-input contract.

**Consequences.** Custom themes can read semantic role and schema requiredness directly off the prepared node, matching D-038's promise for `value_type`, without consulting a definition or source adapter. D-010's invariant is preserved project-wide: no theme, reference or custom, can regress "required string with schema-valid empty value blocks submission" by conflating the two `required` facts, because the presentational fact and the HTML-constraint fact keep separate names and a test backstops the boundary. Explicitly deferred, and recorded as open questions in [[20-renderer-ui-model|Renderer and UI model]]: grouping `value_type`/`role`/`required?` into a dedicated "prepared meaning" sub-struct once a second UI implementation exists to pressure-test the shape, and a separate presentational override (e.g. `mark_as_required?`) that would let a theme mark a field as required in the UI independent of both `required?` and `validations[:required]`. No codec grammar, HTML constraint policy, or D-010 change is made by this decision.

## D-044 — Object-level error-summary entries link to their prepared fieldset

*2026-08-07*

**Context.** [[#D-036 — Group help uses prepared Phoenix identities|D-036]] left
group-level error-summary linking as explicitly separate work. Since then, root
and object-level issues have reached the summary through
[[#D-027 — Projection reads semantic state through a StateView protocol|D-027]]'s
`StateView.issues/2`, but every one rendered as a plain, unlinked line —
`id: nil` regardless of whether a fieldset existed to link to. [GitHub issue
#34](https://github.com/kioopi/formentation/issues/34) reopened that gap: an
`InstancePath` alone cannot say whether a fieldset was actually rendered at
that path, or what DOM namespace it used, because
[[#D-041 — Projected Phoenix forms are the ordinary rendering input|D-041]]
makes that depend on which projected form rendered it — the same absolute
object path can carry different correct DOM ids, or none, depending on
whether it is reached through the root form, a nested projected form, or an
explicit `dom_namespace:` override.

**Decision.** `RenderNode.Group` carries explicit provenance: `kind`
(`:object` | `:presentation_group`, always set during preparation, never
inferred from DOM-id text, legend content, or child shape) and
`occurrence_path` (the occurrence's exact `InstancePath` for an `:object`
group, `nil` for a presentation group). `RenderPreparation.Summary` builds an
occurrence-path → `%{id, label}` target index once per plan by walking the
*prepared* tree's `root.children` — never `root` itself, since `fields/1`
never renders the projection root's own fieldset, native or nested — indexing
every `:object` group by its exact `occurrence_path` and reading the id from
its already-prepared `dom.container` rather than reconstructing one from the
issue's path. A non-field issue whose path matches links to that target,
labelled with the group's `legend`; a `:presentation_group` is walked for its
descendant objects but is never a link target itself. The lookup is an exact
match with no ancestor fallback, matching
[[#D-028 — Unsupported nodes are a preserve-only capability; blocking is derived at runtime|D-028]]'s
existing `InstancePath.ancestor_or_self?/2` precedent of deciding
path relationships in one shared place rather than approximating them per
call site. An `:object` group's fieldset carries `tabindex="-1"`, the same
non-tab-stop focus-target convention
[[#D-034 — Phoenix renderer DOM identities are typed and injective|D-034]]'s
radio-group container already used, so a linked anchor always resolves to a
focusable target; a `:presentation_group` fieldset carries no `tabindex`.

**Consequences.** An object-level issue is now indistinguishable in kind from
a field-level one from the theme's perspective: both are `RenderPlan.SummaryEntry`
structs with an `id`/`label`/`message`, both resolve to exactly one rendered,
focusable element. A root-of-form or nested-projection-root issue, and an
issue for an object with no rendered node of its own, remain unlinked — that
degradation is intentional, not a gap. Presentation-only groups stay outside
the summary-target surface entirely, since they own no semantic occurrence to
key an index on. No change to `StateView.Issue`, issue ordering, visibility,
or submission semantics; no new public API. `RenderNode.Group`'s two new
fields are additive and internal, gated out of published docs the same way
[[#D-035 — Phoenix rendering prepares and consumes DOM identities|D-035]]'s
`FieldDOM`/`GroupDOM` are.

## D-045 — Render preparation context owns identity and cursor movement

*2026-08-07*

**Context.** `RenderPreparation` had accumulated two separate concerns: resolving
whether a Phoenix form was native or generic, and moving the traversal cursor
while walking presentation descriptors. Keeping those writes in the projector
made it possible for `path`, `root_path`, and `root_instance_path` to drift,
and extracting resolution alone would leave the cursor's ownership split.

**Decision.** `RenderPreparation.Context` owns projection-context resolution,
root validation, namespace selection, and every cursor write. It deliberately
does not depend on `Phoenix.HTML.FormData`: `cursor_to/2` returns the relative
segments that the traversal must descend, and `enter/2` returns the direct
child segment. `RenderPreparation` remains responsible for descriptor traversal
and the actual Phoenix form descent.

`InstancePath` deliberately gains no `parent/1`. The root descriptor has empty
segments, and `cursor_to/2` relies on `Enum.drop([], -1) == []` reaching the
at-or-above-root branch; a parent helper would either lie about the root or
introduce a `nil` case into a cursor operation that already has the right
boundary semantics.

**Consequences.** Context state is a struct with one authoritative cursor path;
the native and generic branches share the same downstream context shape, and
the Phoenix dependency stays on the traversal side of the boundary. This is an
internal extraction with no rendering or public API behaviour change.

## D-046 — Adapter resolution failures raise; compilation failures stay diagnostics

*2026-08-07*

**Context.** [GitHub issue #27](https://github.com/kioopi/formentation/issues/27)
(Wave 3, North-star node A3) asked for stable symbolic adapter selectors
(`:map`, `:json_schema`) on `Formentation.compile/2` and a compile-and-initialize
façade, `Formentation.form/2`. Before this, a missing `:adapter` failed through
an incidental `KeyError` (`Keyword.pop!/2`), and an unsupported value failed
through an incidental `UndefinedFunctionError` once dispatch was attempted —
neither was an intentional public contract.

**Decision.** Adapter *selection* failures — a missing `:adapter`, an
unsupported bare atom, a non-atom term, or a module that cannot be loaded or
does not export `compile/2` — raise `ArgumentError` at the `compile/2`
boundary rather than producing a `Formentation.Diagnostic.t()`. No adapter has
run yet in these cases, so there is no declaration location or source
provenance to attach a diagnostic to, and folding configuration mistakes into
`{:error, diagnostics}` would make them indistinguishable from genuine
declaration-compilation failures. Once an adapter is accepted, its `compile/2`
result — success or `{:error, diagnostics}` — is authoritative and
unrescued; adapter exception totality remains a separate contract (see
[GitHub issue #6](https://github.com/kioopi/formentation/issues/6)).

Symbolic selection is a closed, explicit mapping (`:map` →
`Formentation.Source.Map`, `:json_schema` → `Formentation.JSONSchema`), not a
registry or source-shape inference — plain maps are inherently ambiguous
between a map declaration and a decoded JSON Schema, so the adapter stays
mandatory. Any other atom is accepted as a custom adapter module only when
`Code.ensure_compiled!/1` obtains it and `function_exported?(adapter, :compile, 2)`
holds; this is a callable-contract check, not a `@behaviour` metadata check,
so third-party modules need not retain behaviour metadata at runtime.

The resolution primitive is `Code.ensure_compiled!/1`, and the bang matters.
Resolution cannot continue without the adapter, and only the bang variant
tells the compiler so: it marks the module a **required** dependency, so one
still being produced by the same `Kernel.ParallelCompiler` run is waited for.
The two non-bang alternatives are both wrong here, in different ways.
`ensure_loaded?/1` does not wait at all, so an adapter defined in the caller's
own project is rejected intermittently. `ensure_compiled/1` marks the module
*optional* and is documented to answer `{:error, :unavailable}` for one that
is merely not available **yet** — Elixir's own docs name the
`ensure_compiled/1` → raise shape as an anti-pattern for exactly this reason.
The difference is observable, not theoretical: inside a compile cycle,
`ensure_compiled/1` answers `{:error, :unavailable}` for a module that
`ensure_compiled!/1` resolves successfully, so a resolver built on the
non-bang variant turns a transient compiler state into a permanent-looking
"unsupported adapter" error — the very class of false failure this decision
exists to remove. Both paths are pinned by regression tests.

`Formentation.form/2` treats `data:` and `defaults:` as an explicit
initialization-owned allowlist, stripped before compiler options reach the
adapter, and delegates to `compile/2` (for adapter resolution) and
`Formentation.Form.new/3` (for initialization) rather than reimplementing
either. On a compiler error it returns `{:error, diagnostics}` and never
calls `Form.new/3`; on success it forwards `Form.new/3`'s result — including
any `FunctionClauseError` from invalid `data:` — unrescued.

**Consequences.** `Formentation.compile/2` and `Formentation.form/2` now fail
deterministically and legibly on adapter misconfiguration, replacing
accidental exception types with an intentional one. Built-in adapter usage no
longer needs to name an implementation module (`adapter: :map` instead of
`adapter: Formentation.Source.Map`), while module adapters remain fully
supported for both built-in and third-party sources. `Formentation.form/2`
gives single-shot callers a compile-once-and-initialize path without
duplicating `Form.new/3`'s default/apply/revalidate logic; callers who need
compile-once/reuse continue to use `compile/2` followed by `Form.new/3`
directly. No change to validation, decoding, submission, or persistence.

Two consequences worth naming explicitly, because neither is visible from the
public surface:

*Core now names both built-in adapters.* `.reach.exs` forbids `{:core, :source}`
and `{:core, :json_schema}`, and its comments previously read as "core never
names an adapter" — the boundary
[[#D-018 — Reach is the architecture gate|D-018]] and
[[#D-025 — Instance validation dispatches through a source-neutral behaviour|D-025]]
established. The closed selector mapping lives in core and therefore mentions
`Formentation.Source.Map` and `Formentation.JSONSchema` literally. The gate
still passes, but only because a module literal returned as a value is not a
call edge that Reach can see — not because the invariant is untouched. The
rule's comments were corrected to record this as a deliberate, name-only
exception; the substantive prohibition (core must never *invoke* an adapter
function directly) is unchanged, and no cycle is introduced.

*The accepted adapter set is wider than "modules that look like adapters".*
Because the check is `exports compile/2` rather than `implements
Formentation.Source`, unrelated modules that happen to export `compile/2` —
`Regex` and `:re` among them — resolve successfully and then return a shape
that violates the documented three-element contract, surfacing as a
`MatchError`/`CaseClauseError` at the call site rather than a clear rejection.
This is accepted: the adapter is developer-supplied and never user input, and
validating adapter return shapes is adapter-totality work belonging to
[GitHub issue #6](https://github.com/kioopi/formentation/issues/6), not to
selection.

## Related notes

- [[19-north-star-architecture|North-star architecture]]
- [[20-renderer-ui-model|Renderer and UI model]]
- [[phase-1-north-star-alignment|Phase 1 — North-star alignment]]
- [[16-open-questions|Open questions]]
- [[13-roadmap|Roadmap]]
- [[00-use-case|Motivating use case]]
- [[Formentation|Back to the entry point]]
