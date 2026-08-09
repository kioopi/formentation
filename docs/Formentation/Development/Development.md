---
title: Development
aliases:
  - Development docs
tags:
  - formentation
  - index
  - roadmap
status: draft
---

# Development

The **phase-by-phase implementation plans** and their current status. Each phase is a vertical capability slice with a demonstrable, tested result. This index answers one question at a glance: *where is the actual work happening right now?*

The conceptual roadmap that frames these phases is [[13-roadmap|Planning/13 — Roadmap]].

## Phase status

| Phase | Status | Outcome |
| --- | --- | --- |
| [[phase-1-walking-skeleton\|1 — Walking skeleton]] | 🚧 In progress | A form compiled from two sources renders, validates, and submits end to end through Phoenix. |
| [[phase-1-north-star-alignment\|Phase 1 — North-star alignment]] | ✅ Done (2026-08-09) | Milestone A delivered split semantic/presentation structure, layout-invariant semantics, a complete submission decision, and the projected Phoenix path in `v0.2.0`. |
| [[phase-2-compiler-diagnostics\|2 — Compiler and diagnostics]] | 📋 Planned | Compilation becomes an ordered, explainable pipeline with verifiers, full provenance, and stable diagnostics. |
| [[phase-3-extensibility\|3 — Extensibility and UI integrations]] | 📋 Planned | Applications and UI packages can add semantics, codecs, prepared-view consumers, stateless and interactive widgets, and compiler passes through proven contracts. |
| [[phase-4-dynamic-schemas\|4 — Dynamic schemas]] | 📋 Planned | Conditional and compositional schemas project against changing data without losing state. |
| [[phase-5-ash-integration\|5 — Ash integration]] | 🔭 TBD | The same rendering concepts work with Ash declarations and `AshPhoenix.Form`. |

**Legend:** ✅ Done · 🚧 In progress · 📋 Planned · 🔭 TBD (sketch, direction only)

> [!warning] Phases 2–5 are sketches
> Their notes record direction and known hazards, not commitments; expect Phase 1 experience to revise them. See [[13-roadmap|the roadmap]].

Phase 3's rendering direction is developed in
[[20-renderer-ui-model|Planning/20 — Renderer and UI model]]. That note constrains
current Definition and Phoenix work but deliberately defers public prepared-view,
transport, UI, capability, localization, and interactive-widget contracts until
a built-in UI, a separately compiling second editable UI, and read-only review
rendering can prove the relevant boundaries.

## Current work

Phase 1 is mid-flight. Completed within it so far: the map-source static pipeline, the JSON Schema adapter, the annotations mini-slice, step 4 (state and codecs, decided on paper as [[18-decisions#D-009 — Form state separates transport from operation|D-009]]–[[18-decisions#D-014 — Usage is a first-class interaction axis|D-014]] and then implemented), the per-kind `Node` split ([[18-decisions#D-015 — One struct per node kind|D-015]]), the non-submitting-fields mini-slice ([[18-decisions#D-016 — Participation is definition-driven, not transport-driven|D-016]]), step 5, the `Phoenix.HTML.FormData` projection ([[18-decisions#D-017 — Phoenix integration ships in-tree behind a namespace boundary|D-017]]), step 6, the projector, public components, and reference theme — Phoenix-generic projection ([[18-decisions#D-019 — Projection is Phoenix-generic|D-019]]) and the reference theme as a markup set rather than a contract ([[18-decisions#D-020 — The reference theme is a markup set, not a contract|D-020]]) — and step 7, the LiveView lifecycle: thin `validate/2`/`submit/2` wrappers, the `_persistent_id` transport strip, and a repo-root `demo/` application (both LiveViews, `mix demo`) serving as both the `Phoenix.LiveViewTest` fixture and a browser-checked example ([[18-decisions#D-021 — LiveView integration is wrappers plus a demo, not framework machinery|D-021]]).

[[phase-1-north-star-alignment|The Phase 1 north-star alignment gate]] is
closed. It delivered the split definition, a semantic-only `Form`, the
submission decision, the `form/2` façade with symbolic selectors, and
projected-form rendering; all ship in `v0.2.0`. **Phase 1 Milestone B
(collections) is now the active work.**

Supplementary to the numbered steps: an opt-in, demo-driven browser-real test suite (PhoenixTest + Playwright, [[18-decisions#D-022 — Browser-real tests are an opt-in, demo-driven Playwright suite|D-022]]) now covers truths `Phoenix.LiveViewTest` cannot observe — real `_unused_` marker gating, number-widget raw-text preservation under an actual browser, and error-summary focus movement — and surfaced the pump-inspection demo's native-validation toggle ([[18-decisions#D-023 — The demo keeps native validation, behind a toggle|D-023]]). It runs via `mix test.browser`, stays out of `mix ci` by design, and is not itself a phase-1 step; see [[browser-testing|Techdocs/Browser testing]].

✅ Done (2026-07-25) — also supplementary, an architecture refactor orthogonal to the numbered steps: instance validation dispatch is now source-neutral. The core-owned `Formentation.Definition.Validation` behaviour and `Formentation.Definition.ValidationPlan` (module + opaque artifact) replace the opaque `Definition.validator` field that `Form` used to dispatch by name straight to `Formentation.Source.JSONSchema.Validator`; `Form` now calls `plan.module.validate(plan.artifact, instance)` and names no adapter, `Issue.source` is `:decode | :validation`, `format_version` bumped 1→2, and the `core↔json_schema` layer cycle [[18-decisions#D-018 — Reach is the architecture gate|D-018]] baselined is removed. See [[18-decisions#D-025 — Instance validation dispatches through a source-neutral behaviour|D-025]] and the refreshed [[Techdocs|Techdocs]] notes ([[definition-and-node|Definition and Node]], [[form-state-and-transitions|Form state and transitions]], [[source-adapters|Source adapters]], [[diagnostics-and-origins|Diagnostics and origins]]).

✅ Done (2026-07-25) — also supplementary, a runtime bugfix orthogonal to the numbered steps: nested data-nesting objects now use **content-derived presence** during replace transitions ([GitHub issue #1](https://github.com/kioopi/formentation/issues/1)). `Form` no longer fabricates an empty `%{}` for a group whose children are all absent — an object is emitted only when recursive materialization leaves at least one declared or preserved key, via an internal `:absent | {:present, map()}` result. This stops an unrelated edit from activating a `required` issue at a fabricated child path. See [[18-decisions#D-026 — Content-derived presence for nested objects|D-026]] and the refreshed [[form-state-and-transitions|Form state and transitions]] note.

✅ Done (2026-07-25) — also supplementary, a projection-boundary refactor orthogonal to the numbered steps: `Formentation.Phoenix.Projector` no longer names a concrete runtime-state struct or reads `form.action` directly. Three semantic facts Phoenix cannot carry — whether a source considers a form submitted, a source-owned issue-visibility policy, and root/object-level issues — now dispatch through the new read-only `Formentation.Phoenix.StateView` protocol on `form.source` (`submitted?/2`, `issue_visibility/3`, `issues/2`), with `@fallback_to_any` reproducing the previous Phoenix-generic behaviour (`Any`) and a complete implementation for `Formentation.Form`. A notable behaviour change: field-error visibility for a `%Formentation.Form{}` source now comes from `Form.show_issues?/2` (accumulated usage) rather than `Phoenix.Component.used_input?/1` (current-params usage) — the two diverge when a later payload omits a previously-used path, and the new rule is the intended one. See [[18-decisions#D-027 — Projection reads semantic state through a StateView protocol|D-027]] (amending [[18-decisions#D-019 — Projection is Phoenix-generic|D-019]] in place) and the refreshed [[rendering|Techdocs/Rendering]] and [[end-to-end-data-flow|Techdocs/End-to-end data flow]] notes.

✅ Done (2026-07-26) — also supplementary, a runtime feature orthogonal to the numbered steps: unsupported (preserve-only) nodes now have a **concrete, derived submission status** ([GitHub issue #3](https://github.com/kioopi/formentation/issues/3)). `Formentation.Info.unsupported_nodes/1` statically enumerates preserve-only nodes; `Formentation.Form.submission_blockers/1` and `Formentation.Form.submission_status/1` classify each against the materialized candidate and source-neutral validation issues into `Formentation.Form.SubmissionBlocker`s (`:unsupported_required` | `:unsupported_invalid`), with precedence `:undecodable` → `{:blocked, blockers}` → `{:invalid, issues}` → `:ready`; ownership uses the new `Formentation.InstancePath.ancestor_or_self?/2`. Nothing is stored on `%Form{}`, no `format_version` bump, no struct change, no strict compile mode, and no opaque-replacement escape hatch. Blockers reach the submit-gated error summary through the [[18-decisions#D-027 — Projection reads semantic state through a StateView protocol|D-027]] state view, which translates each into one normalized issue at the owning node's path and drops the issues it already speaks for; the projector renders them with its generic non-field rule and learns nothing about blockers. See [[18-decisions#D-028 — Unsupported nodes are a preserve-only capability; blocking is derived at runtime|D-028]] and the refreshed [[definition-and-node|Definition and Node]], [[form-state-and-transitions|Form state and transitions]], and [[rendering|Rendering]] notes.

✅ Done (2026-07-26) — the Phase 1 north-star alignment gate now has its presentation-consumer seam ([GitHub issue #17](https://github.com/kioopi/formentation/issues/17)). `Formentation.Info.presentation_root/1` and `presentation_at/2` expose typed object, field-reference, and group descriptors over the current mixed tree. Descriptor object/field references carry normalized `InstancePath`s; presentation group IDs remain layout identity and are not addressable as instance paths. `Formentation.Phoenix.Projector` now consumes those descriptors and resolves field/object facts through `Info`, while the Phoenix FormData nested-object check uses semantic classification instead of the mixed `nests_data?` flag. Behavioural output remains the existing `RenderPlan`/`RenderNode` and reference-theme markup. See [[18-decisions#D-031 — Phoenix preparation consumes presentation descriptors|D-031]] and the refreshed [[definition-and-node|Definition and Node]] and [[rendering|Rendering]] notes.

✅ Done (2026-07-26) — A2 of the Phase 1 north-star alignment gate now has an application-facing submission decision ([GitHub issue #19](https://github.com/kioopi/formentation/issues/19)). `Formentation.Form.submit/2` performs the pure `:submit` transition and then returns `{:ok, candidate, submitted_form}` only for `submission_status/1 == :ready`; undecodable, blocked, and invalid submissions return `{:error, submitted_form}` for redisplay. The demo no longer combines `issues/1` and `candidate/1` as a readiness predicate, and failed submits clear stale decoded-candidate output. See [[18-decisions#D-032 — Submit returns the application decision|D-032]] and the refreshed [[form-state-and-transitions|Form state and transitions]] and [[using-with-liveview|Using Formentation with LiveView]] notes.

✅ Done (2026-07-27) — the split-definition implementation
([GitHub issue #18](https://github.com/kioopi/formentation/issues/18)) now has
native semantic and presentation storage, direct native emission from both
built-in adapters, a finalized semantic index, and native-backed
`Formentation.Definition.Semantic` / `Formentation.Info.Layout` query seams. The
temporary mixed `Definition.root` compatibility tree and `Formentation.Node.*`
storage structs are gone; `Info.node_at/2` / `Info.fields/1` return native
semantic nodes while presentation queries return presentation descriptors. See
[[definition-and-node|Definition]], [[rendering|Rendering]], and
[[18-decisions#D-033 — Phase 1 layout covers each supported occurrence exactly once|D-033]].

> [!info] Where the granular execution records live
> The per-slice classic-TDD specs and plans that drive each step live **outside this vault**, under `docs/superpowers/specs/` and `docs/superpowers/plans/`. The phase notes here summarize them; those files carry the step-by-step detail.

## Documentation state

As of 2026-07-24, step 7 (LiveView)'s documentation debt has been paid: [[Userguide]] gained [[using-with-liveview|its LiveView page]] (handlers, the params pluck, the `to_form(action:)` rule, running `mix demo`, and now the browser-test instructions and native-validation toggle below), and [[Techdocs]]' LiveView-shaped gaps were refreshed with as-of markers updated accordingly. The follow-on browser-testing work is also now documented: [[browser-testing|Techdocs/Browser testing]] (the mise toolchain, the `PLAYWRIGHT_E2E`-gated config, and what each seed test pins), [[18-decisions#D-022 — Browser-real tests are an opt-in, demo-driven Playwright suite|D-022]] and [[18-decisions#D-023 — The demo keeps native validation, behind a toggle|D-023]] in the decision log, and the closed [[16-open-questions#Rendering|step-7 open question]] on whether to adopt browser-real tests.

As of 2026-07-25, the source-neutral validation dispatch refactor's documentation debt is paid: [[definition-and-node|Definition and Node]], [[form-state-and-transitions|Form state and transitions]], [[source-adapters|Source adapters]], and [[diagnostics-and-origins|Diagnostics and origins]] are refreshed for `Formentation.Definition.Validation`/`Formentation.Definition.ValidationPlan`, `Definition.validation`, and `Issue.source: :decode | :validation`, with as-of markers updated accordingly, and [[18-decisions#D-025 — Instance validation dispatches through a source-neutral behaviour|D-025]] records the decision (amending [[18-decisions#D-018 — Reach is the architecture gate|D-018]] in place). The user-facing [[declaring-with-json-schema|JSON Schema guide]] (now `source: :validation`), [[end-to-end-data-flow|End-to-end data flow]], [[test-and-verification-architecture|Test and verification architecture]] (the removed core→json_schema exception and baseline), and the [[16-open-questions|map-source parity open question]] were corrected to match.

Also as of 2026-07-25, the nested-object presence fix ([[18-decisions#D-026 — Content-derived presence for nested objects|D-026]]) is documented: [[form-state-and-transitions|Form state and transitions]] gained a "Nested-object presence" paragraph under the materialization/deferral section, with its as-of marker refreshed.

Also as of 2026-07-25, the StateView projection-boundary refactor ([[18-decisions#D-027 — Projection reads semantic state through a StateView protocol|D-027]], amending [[18-decisions#D-019 — Projection is Phoenix-generic|D-019]] in place) is documented: [[06-runtime-projection|Planning/06 — Runtime projection]]'s algorithm now names the root Phoenix form and root state source and states the instance path is always absolute; [[07-phoenix-integration|Planning/07 — Phoenix integration]] gained a "State view" subsection; the [[16-open-questions|state-view open question]] records the narrower, projection-boundary answer alongside its 2026-07-22 per-field-read-model answer; [[rendering|Techdocs/Rendering]] and [[end-to-end-data-flow|Techdocs/End-to-end data flow]] are corrected — the error-summary gate is `StateView.submitted?/2` and degradation follows `issues/2` answering `:unavailable`, not source type — with as-of markers refreshed. The decision log's D-027 entry carries a clearly-marked note on the `show_issues?/2` vs. `used_input?/1` behaviour change, pinned by `test/formentation/phoenix/used_input_contract_test.exs`.
Also as of 2026-07-26, the unsupported-node submission-blocker feature ([GitHub issue #3](https://github.com/kioopi/formentation/issues/3), [[18-decisions#D-028 — Unsupported nodes are a preserve-only capability; blocking is derived at runtime|D-028]]) is documented: `Formentation.Node.Unsupported`'s moduledoc now states the preserve-only/static-vs-concrete distinction; [[definition-and-node|Definition and Node]] gained an "Unsupported nodes are a preserve-only capability" section covering `Info.unsupported_nodes/1`; [[form-state-and-transitions|Form state and transitions]] gained a "Submission status is derived, not stored" section covering `submission_status/1`/`submission_blockers/1`, the precedence order, ownership via `InstancePath.ancestor_or_self?/2`, the causal limit, and the validation-less fallback; [[rendering|Rendering]]'s error-summary section now describes how the `%Formentation.Form{}` state view translates blockers into normalized issues and what the projector does with them; [[declaring-with-json-schema|the JSON Schema guide]] and [[declaring-with-the-map-source|the map-source guide]] each gained a callout that unsupported declarations are preserve-only and submitted params are not an escape hatch; and [[limitations|What isn't supported yet]]'s arrays section now distinguishes the static compile-time warning from concrete, runtime-derived submission blocking and records that no `unsupported: :error` compile option exists yet. All touched notes' as-of markers were refreshed to 2026-07-26.

Also as of 2026-07-26, the presentation traversal migration ([GitHub issue #17](https://github.com/kioopi/formentation/issues/17), [[18-decisions#D-031 — Phoenix preparation consumes presentation descriptors|D-031]]) is documented: [[definition-and-node|Definition and Node]] now describes the temporary `Formentation.Info.Layout` descriptor vocabulary and the `presentation_root/1`/`presentation_at/2` query seam; [[rendering|Rendering]] now states that the projector consumes those descriptors rather than walking the mixed root tree, that layout order can differ from semantic declaration order, and that nested Phoenix descent is driven by semantic-object descriptors. The public Userguide did not change because the component API, names, IDs, markup, and transport behaviour stayed the same.

Also as of 2026-08-03, collision-proof DOM identity adoption ([GitHub issue #30](https://github.com/kioopi/formentation/issues/30), [[18-decisions#D-035 — Phoenix rendering prepares and consumes DOM identities|D-035]]) is documented: [[rendering|Rendering]], [[end-to-end-data-flow|End-to-end data flow]], [[browser-testing|Browser testing]], and the rendering user guides now distinguish Phoenix transport names from renderer-owned ids, explain namespace resolution, and match the reviewed HTML fixture and browser selectors.

Also as of 2026-08-03, group help is preserved through Phoenix preparation and
rendered with prepared group identities ([GitHub issue #7](https://github.com/kioopi/formentation/issues/7)). Nested-object and native presentation-group help render as escaped, fieldset-associated text; whole-form `fields/1` deliberately keeps root help structural, while `field path={[]}` renders the root subtree. See [[18-decisions#D-036 — Group help uses prepared Phoenix identities|D-036]] and [[rendering|Rendering]].

Also as of 2026-08-04, numeric rendering preserves normalized semantic value type in each prepared Phoenix field ([GitHub issue #8](https://github.com/kioopi/formentation/issues/8)). Integer and general-number fields remain in the shared `:number_input` interaction family, but the reference theme now renders `numeric` and `decimal` input modes respectively while retaining the raw-value-safe `type="text"` fallback. The cross-widget `min`/`max`/`step` leak for numeric fields is fixed, and [[rendering|Techdocs/Rendering]], [[rendering-with-phoenix|the Phoenix rendering guide]], and [[18-decisions#D-038 — Semantic value type and abstract widget are orthogonal prepared facts|D-038]] record the resulting contract.

✅ Done (2026-08-05) — north-star P1+P2+P3: projected Phoenix forms are the
ordinary rendering input ([GitHub issue #28](https://github.com/kioopi/formentation/issues/28)).
`Formentation.Phoenix.fields/1` and `field/1` take a form alone when it is
projected from `Formentation.Form`; the definition and projection root are
recovered from the native projection by the single decoder
`Formentation.Phoenix.ProjectedForm`, and a nested form renders only its own
object subtree with `field/1` paths resolved relative to that root. Any other
`FormData` source remains a permanent advanced route supplying `definition:`.
`Projector` → `RenderPreparation` and `Theme.Reference` → `ReferenceComponents`
fulfil the rename D-030 required before `0.1.0`; render preparation, plans,
nodes, and reference components are now excluded from public ExDoc while
keeping their moduledocs for IEx. See
[[18-decisions#D-041 — Projected Phoenix forms are the ordinary rendering input|D-041]]
and the refreshed [[rendering|Rendering]], [[phoenix-form-data|Phoenix FormData]],
and [[end-to-end-data-flow|End-to-end data flow]] notes.
Both names were later superseded by `Formentation.Phoenix.Render.Preparation`
and `Formentation.Phoenix.UI.Reference` in
[[18-decisions#D-047 — The lib tree is restructured to state the north-star architecture|D-047]].

As of 2026-07-26, the project direction is additionally frozen in
[[19-north-star-architecture|North-star architecture]],
[[phase-1-north-star-alignment|the alignment plan]], and
[[18-decisions#D-029 — Definition and Form are the ordinary public model|D-029]].
These are target/planning documents; they deliberately do not
rewrite current-state `Techdocs` or `Userguide` ahead of implementation.

✅ Done (2026-08-07) — also supplementary, an accessibility feature orthogonal
to the numbered steps: object-level error-summary entries now link to their
rendered fieldset instead of always rendering unlinked ([GitHub issue
#34](https://github.com/kioopi/formentation/issues/34)). `RenderNode.Group`
carries explicit `kind`/`occurrence_path` provenance so semantic objects and
presentation groups stay distinguishable even though both render as
fieldsets; `RenderPreparation.Summary` builds an occurrence-path → target
index from the prepared tree (never the plan's own root, so a root-of-form or
nested-projection-root issue stays unlinked by design) and links a matching
issue using the group's already-prepared container id and legend, with no
ancestor fallback. An `:object` fieldset now carries `tabindex="-1"`, the
radio-group convention, so a linked anchor always resolves to a focusable
target; a presentation-only group carries none, since it owns no semantic
occurrence to link. See
[[18-decisions#D-044 — Object-level error-summary entries link to their prepared fieldset|D-044]]
and the refreshed [[rendering|Rendering]] note.
`RenderNode.Group` and `RenderPreparation.Summary` were later renamed under
`Formentation.Phoenix.Render.Node` and `.Render.Preparation` by
[[18-decisions#D-047 — The lib tree is restructured to state the north-star architecture|D-047]].

✅ Done (2026-08-07) — Wave 3 / North-star node A3: stable symbolic source
selectors and a compile-and-initialize façade ([GitHub issue
#27](https://github.com/kioopi/formentation/issues/27)). `Formentation.compile/2`
accepts `adapter: :map` / `adapter: :json_schema` alongside module adapters,
resolved by one private boundary shared with the new `Formentation.form/2`,
which compiles and initializes a `Form` in one call. Adapter-selection
mistakes (missing, unsupported, or invalid `:adapter`) now raise `ArgumentError`
instead of an incidental `KeyError`/`UndefinedFunctionError`; adapter
compilation failures remain `{:error, diagnostics}` and are never rescued.
`form/2` treats `data:`/`defaults:` as an explicit initialization allowlist
and forwards all other options to the adapter unchanged. See
[[18-decisions#D-046 — Adapter resolution failures raise; compilation failures stay diagnostics|D-046]]
and the refreshed [[compile-pipeline|Compile pipeline]] note.

## Related

- [[13-roadmap|Planning/13 — Roadmap]]
- [[19-north-star-architecture|Planning/19 — North-star architecture]]
- [[20-renderer-ui-model|Planning/20 — Renderer and UI model]]
- [[phase-1-north-star-alignment|Phase 1 — North-star alignment]]
- [[Planning]]
- [[Formentation|Vault entry note]]
