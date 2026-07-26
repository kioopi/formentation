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
| [[phase-1-north-star-alignment\|Phase 1 — North-star alignment]] | 📋 Planned | Milestone A adopts split semantic/presentation structure, layout-invariant semantics, a complete submission decision, and the intended Phoenix projection path before collections. |
| [[phase-2-compiler-diagnostics\|2 — Compiler and diagnostics]] | 📋 Planned | Compilation becomes an ordered, explainable pipeline with verifiers, full provenance, and stable diagnostics. |
| [[phase-3-extensibility\|3 — Extensibility]] | 📋 Planned | Applications and UI packages can add semantics, codecs, widgets, UI integrations, and compiler passes safely. |
| [[phase-4-dynamic-schemas\|4 — Dynamic schemas]] | 📋 Planned | Conditional and compositional schemas project against changing data without losing state. |
| [[phase-5-ash-integration\|5 — Ash integration]] | 🔭 TBD | The same rendering concepts work with Ash declarations and `AshPhoenix.Form`. |

**Legend:** ✅ Done · 🚧 In progress · 📋 Planned · 🔭 TBD (sketch, direction only)

> [!warning] Phases 2–5 are sketches
> Their notes record direction and known hazards, not commitments; expect Phase 1 experience to revise them. See [[13-roadmap|the roadmap]].

## Current work

Phase 1 is mid-flight. Completed within it so far: the map-source static pipeline, the JSON Schema adapter, the annotations mini-slice, step 4 (state and codecs, decided on paper as [[18-decisions#D-009 — Form state separates transport from operation|D-009]]–[[18-decisions#D-014 — Usage is a first-class interaction axis|D-014]] and then implemented), the per-kind `Node` split ([[18-decisions#D-015 — One struct per node kind|D-015]]), the non-submitting-fields mini-slice ([[18-decisions#D-016 — Participation is definition-driven, not transport-driven|D-016]]), step 5, the `Phoenix.HTML.FormData` projection ([[18-decisions#D-017 — Phoenix integration ships in-tree behind a namespace boundary|D-017]]), step 6, the projector, public components, and reference theme — Phoenix-generic projection ([[18-decisions#D-019 — Projection is Phoenix-generic|D-019]]) and the reference theme as a markup set rather than a contract ([[18-decisions#D-020 — The reference theme is a markup set, not a contract|D-020]]) — and step 7, the LiveView lifecycle: thin `validate/2`/`submit/2` wrappers, the `_persistent_id` transport strip, and a repo-root `demo/` application (both LiveViews, `mix demo`) serving as both the `Phoenix.LiveViewTest` fixture and a browser-checked example ([[18-decisions#D-021 — LiveView integration is wrappers plus a demo, not framework machinery|D-021]]).

The active next step is now
[[phase-1-north-star-alignment|the Phase 1 north-star alignment gate]], accepted
in [[18-decisions#D-029 — Definition and Form are the ordinary public model|D-029]].
It separates semantic structure from presentation layout and
converges the public API before **step 8, Milestone B (collections)** resumes.
Its Wave 0 begins with the planning documents and then adds two executable
layout-invariance characterizations before the first query-order change.
The current implementation remains accurately documented in `Techdocs` and
`Userguide` until the corresponding alignment changes land.

Supplementary to the numbered steps: an opt-in, demo-driven browser-real test suite (PhoenixTest + Playwright, [[18-decisions#D-022 — Browser-real tests are an opt-in, demo-driven Playwright suite|D-022]]) now covers truths `Phoenix.LiveViewTest` cannot observe — real `_unused_` marker gating, number-widget raw-text preservation under an actual browser, and error-summary focus movement — and surfaced the pump-inspection demo's native-validation toggle ([[18-decisions#D-023 — The demo keeps native validation, behind a toggle|D-023]]). It runs via `mix test.browser`, stays out of `mix ci` by design, and is not itself a phase-1 step; see [[browser-testing|Techdocs/Browser testing]].

✅ Done (2026-07-25) — also supplementary, an architecture refactor orthogonal to the numbered steps: instance validation dispatch is now source-neutral. The core-owned `Formentation.Validation` behaviour and `Formentation.ValidationPlan` (module + opaque artifact) replace the opaque `Definition.validator` field that `Form` used to dispatch by name straight to `Formentation.JSONSchema.Validator`; `Form` now calls `plan.module.validate(plan.artifact, instance)` and names no adapter, `Issue.source` is `:decode | :validation`, `format_version` bumped 1→2, and the `core↔json_schema` layer cycle [[18-decisions#D-018 — Reach is the architecture gate|D-018]] baselined is removed. See [[18-decisions#D-025 — Instance validation dispatches through a source-neutral behaviour|D-025]] and the refreshed [[Techdocs|Techdocs]] notes ([[definition-and-node|Definition and Node]], [[form-state-and-transitions|Form state and transitions]], [[source-adapters|Source adapters]], [[diagnostics-and-origins|Diagnostics and origins]]).

✅ Done (2026-07-25) — also supplementary, a runtime bugfix orthogonal to the numbered steps: nested data-nesting objects now use **content-derived presence** during replace transitions ([GitHub issue #1](https://github.com/kioopi/formentation/issues/1)). `Form` no longer fabricates an empty `%{}` for a group whose children are all absent — an object is emitted only when recursive materialization leaves at least one declared or preserved key, via an internal `:absent | {:present, map()}` result. This stops an unrelated edit from activating a `required` issue at a fabricated child path. See [[18-decisions#D-026 — Content-derived presence for nested objects|D-026]] and the refreshed [[form-state-and-transitions|Form state and transitions]] note.

✅ Done (2026-07-25) — also supplementary, a projection-boundary refactor orthogonal to the numbered steps: `Formentation.Phoenix.Projector` no longer names a concrete runtime-state struct or reads `form.action` directly. Three semantic facts Phoenix cannot carry — whether a source considers a form submitted, a source-owned issue-visibility policy, and root/object-level issues — now dispatch through the new read-only `Formentation.Phoenix.StateView` protocol on `form.source` (`submitted?/2`, `issue_visibility/3`, `issues/2`), with `@fallback_to_any` reproducing the previous Phoenix-generic behaviour (`Any`) and a complete implementation for `Formentation.Form`. A notable behaviour change: field-error visibility for a `%Formentation.Form{}` source now comes from `Form.show_issues?/2` (accumulated usage) rather than `Phoenix.Component.used_input?/1` (current-params usage) — the two diverge when a later payload omits a previously-used path, and the new rule is the intended one. See [[18-decisions#D-027 — Projection reads semantic state through a StateView protocol|D-027]] (amending [[18-decisions#D-019 — Projection is Phoenix-generic|D-019]] in place) and the refreshed [[rendering|Techdocs/Rendering]] and [[end-to-end-data-flow|Techdocs/End-to-end data flow]] notes.

✅ Done (2026-07-26) — also supplementary, a runtime feature orthogonal to the numbered steps: unsupported (preserve-only) nodes now have a **concrete, derived submission status** ([GitHub issue #3](https://github.com/kioopi/formentation/issues/3)). `Formentation.Info.unsupported_nodes/1` statically enumerates preserve-only nodes; `Formentation.Form.submission_blockers/1` and `Formentation.Form.submission_status/1` classify each against the materialized candidate and source-neutral validation issues into `Formentation.SubmissionBlocker`s (`:unsupported_required` | `:unsupported_invalid`), with precedence `:undecodable` → `{:blocked, blockers}` → `{:invalid, issues}` → `:ready`; ownership uses the new `Formentation.InstancePath.ancestor_or_self?/2`. Nothing is stored on `%Form{}`, no `format_version` bump, no struct change, no strict compile mode, and no opaque-replacement escape hatch. Blockers reach the submit-gated error summary through the [[18-decisions#D-027 — Projection reads semantic state through a StateView protocol|D-027]] state view, which translates each into one normalized issue at the owning node's path and drops the issues it already speaks for; the projector renders them with its generic non-field rule and learns nothing about blockers. See [[18-decisions#D-028 — Unsupported nodes are a preserve-only capability; blocking is derived at runtime|D-028]] and the refreshed [[definition-and-node|Definition and Node]], [[form-state-and-transitions|Form state and transitions]], and [[rendering|Rendering]] notes.

> [!info] Where the granular execution records live
> The per-slice classic-TDD specs and plans that drive each step live **outside this vault**, under `docs/superpowers/specs/` and `docs/superpowers/plans/`. The phase notes here summarize them; those files carry the step-by-step detail.

## Documentation state

As of 2026-07-24, step 7 (LiveView)'s documentation debt has been paid: [[Userguide]] gained [[using-with-liveview|its LiveView page]] (handlers, the params pluck, the `to_form(action:)` rule, running `mix demo`, and now the browser-test instructions and native-validation toggle below), and [[Techdocs]]' LiveView-shaped gaps were refreshed with as-of markers updated accordingly. The follow-on browser-testing work is also now documented: [[browser-testing|Techdocs/Browser testing]] (the mise toolchain, the `PLAYWRIGHT_E2E`-gated config, and what each seed test pins), [[18-decisions#D-022 — Browser-real tests are an opt-in, demo-driven Playwright suite|D-022]] and [[18-decisions#D-023 — The demo keeps native validation, behind a toggle|D-023]] in the decision log, and the closed [[16-open-questions#Rendering|step-7 open question]] on whether to adopt browser-real tests.

As of 2026-07-25, the source-neutral validation dispatch refactor's documentation debt is paid: [[definition-and-node|Definition and Node]], [[form-state-and-transitions|Form state and transitions]], [[source-adapters|Source adapters]], and [[diagnostics-and-origins|Diagnostics and origins]] are refreshed for `Formentation.Validation`/`Formentation.ValidationPlan`, `Definition.validation`, and `Issue.source: :decode | :validation`, with as-of markers updated accordingly, and [[18-decisions#D-025 — Instance validation dispatches through a source-neutral behaviour|D-025]] records the decision (amending [[18-decisions#D-018 — Reach is the architecture gate|D-018]] in place). The user-facing [[declaring-with-json-schema|JSON Schema guide]] (now `source: :validation`), [[end-to-end-data-flow|End-to-end data flow]], [[test-and-verification-architecture|Test and verification architecture]] (the removed core→json_schema exception and baseline), and the [[16-open-questions|map-source parity open question]] were corrected to match.

Also as of 2026-07-25, the nested-object presence fix ([[18-decisions#D-026 — Content-derived presence for nested objects|D-026]]) is documented: [[form-state-and-transitions|Form state and transitions]] gained a "Nested-object presence" paragraph under the materialization/deferral section, with its as-of marker refreshed.

Also as of 2026-07-25, the StateView projection-boundary refactor ([[18-decisions#D-027 — Projection reads semantic state through a StateView protocol|D-027]], amending [[18-decisions#D-019 — Projection is Phoenix-generic|D-019]] in place) is documented: [[06-runtime-projection|Planning/06 — Runtime projection]]'s algorithm now names the root Phoenix form and root state source and states the instance path is always absolute; [[07-phoenix-integration|Planning/07 — Phoenix integration]] gained a "State view" subsection; the [[16-open-questions|state-view open question]] records the narrower, projection-boundary answer alongside its 2026-07-22 per-field-read-model answer; [[rendering|Techdocs/Rendering]] and [[end-to-end-data-flow|Techdocs/End-to-end data flow]] are corrected — the error-summary gate is `StateView.submitted?/2` and degradation follows `issues/2` answering `:unavailable`, not source type — with as-of markers refreshed. The decision log's D-027 entry carries a clearly-marked note on the `show_issues?/2` vs. `used_input?/1` behaviour change, pinned by `test/formentation/phoenix/used_input_contract_test.exs`.
Also as of 2026-07-26, the unsupported-node submission-blocker feature ([GitHub issue #3](https://github.com/kioopi/formentation/issues/3), [[18-decisions#D-028 — Unsupported nodes are a preserve-only capability; blocking is derived at runtime|D-028]]) is documented: `Formentation.Node.Unsupported`'s moduledoc now states the preserve-only/static-vs-concrete distinction; [[definition-and-node|Definition and Node]] gained an "Unsupported nodes are a preserve-only capability" section covering `Info.unsupported_nodes/1`; [[form-state-and-transitions|Form state and transitions]] gained a "Submission status is derived, not stored" section covering `submission_status/1`/`submission_blockers/1`, the precedence order, ownership via `InstancePath.ancestor_or_self?/2`, the causal limit, and the validation-less fallback; [[rendering|Rendering]]'s error-summary section now describes how the `%Formentation.Form{}` state view translates blockers into normalized issues and what the projector does with them; [[declaring-with-json-schema|the JSON Schema guide]] and [[declaring-with-the-map-source|the map-source guide]] each gained a callout that unsupported declarations are preserve-only and submitted params are not an escape hatch; and [[limitations|What isn't supported yet]]'s arrays section now distinguishes the static compile-time warning from concrete, runtime-derived submission blocking and records that no `unsupported: :error` compile option exists yet. All touched notes' as-of markers were refreshed to 2026-07-26.

As of 2026-07-26, the project direction is additionally frozen in
[[19-north-star-architecture|North-star architecture]],
[[phase-1-north-star-alignment|the alignment plan]], and
[[18-decisions#D-029 — Definition and Form are the ordinary public model|D-029]].
These are target/planning documents; they deliberately do not
rewrite current-state `Techdocs` or `Userguide` ahead of implementation.

## Related

- [[13-roadmap|Planning/13 — Roadmap]]
- [[19-north-star-architecture|Planning/19 — North-star architecture]]
- [[phase-1-north-star-alignment|Phase 1 — North-star alignment]]
- [[Planning]]
- [[Formentation|Vault entry note]]
