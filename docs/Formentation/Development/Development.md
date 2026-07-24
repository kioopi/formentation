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
| [[phase-2-compiler-diagnostics\|2 — Compiler and diagnostics]] | 📋 Planned | Compilation becomes an ordered, explainable pipeline with verifiers, full provenance, and stable diagnostics. |
| [[phase-3-extensibility\|3 — Extensibility]] | 📋 Planned | Applications and UI packages can add semantics, codecs, widgets, themes, and compiler passes safely. |
| [[phase-4-dynamic-schemas\|4 — Dynamic schemas]] | 📋 Planned | Conditional and compositional schemas project against changing data without losing state. |
| [[phase-5-ash-integration\|5 — Ash integration]] | 🔭 TBD | The same rendering concepts work with Ash declarations and `AshPhoenix.Form`. |

**Legend:** ✅ Done · 🚧 In progress · 📋 Planned · 🔭 TBD (sketch, direction only)

> [!warning] Phases 2–5 are sketches
> Their notes record direction and known hazards, not commitments; expect Phase 1 experience to revise them. See [[13-roadmap|the roadmap]].

## Current work

Phase 1 is mid-flight. Completed within it so far: the map-source static pipeline, the JSON Schema adapter, the annotations mini-slice, step 4 (state and codecs, decided on paper as [[18-decisions#D-009 — Form state separates transport from operation|D-009]]–[[18-decisions#D-014 — Usage is a first-class interaction axis|D-014]] and then implemented), the per-kind `Node` split ([[18-decisions#D-015 — One struct per node kind|D-015]]), the non-submitting-fields mini-slice ([[18-decisions#D-016 — Participation is definition-driven, not transport-driven|D-016]]), step 5, the `Phoenix.HTML.FormData` projection ([[18-decisions#D-017 — Phoenix integration ships in-tree behind a namespace boundary|D-017]]), step 6, the projector, public components, and reference theme — Phoenix-generic projection ([[18-decisions#D-019 — Projection is Phoenix-generic|D-019]]) and the reference theme as a markup set rather than a contract ([[18-decisions#D-020 — The reference theme is a markup set, not a contract|D-020]]) — and step 7, the LiveView lifecycle: thin `validate/2`/`submit/2` wrappers, the `_persistent_id` transport strip, and a repo-root `demo/` application (both LiveViews, `mix demo`) serving as both the `Phoenix.LiveViewTest` fixture and a browser-checked example ([[18-decisions#D-021 — LiveView integration is wrappers plus a demo, not framework machinery|D-021]]). The active next step is **step 8, Milestone B (collections)** (of the [[phase-1-walking-skeleton#Implementation strategy|implementation strategy]]).

Supplementary to the numbered steps: an opt-in, demo-driven browser-real test suite (PhoenixTest + Playwright, [[18-decisions#D-022 — Browser-real tests are an opt-in, demo-driven Playwright suite|D-022]]) now covers truths `Phoenix.LiveViewTest` cannot observe — real `_unused_` marker gating, number-widget raw-text preservation under an actual browser, and error-summary focus movement — and surfaced the pump-inspection demo's native-validation toggle ([[18-decisions#D-023 — The demo keeps native validation, behind a toggle|D-023]]). It runs via `mix test.browser`, stays out of `mix ci` by design, and is not itself a phase-1 step; see [[browser-testing|Techdocs/Browser testing]].

> [!info] Where the granular execution records live
> The per-slice classic-TDD specs and plans that drive each step live **outside this vault**, under `docs/superpowers/specs/` and `docs/superpowers/plans/`. The phase notes here summarize them; those files carry the step-by-step detail.

## Documentation state

As of 2026-07-24, step 7 (LiveView)'s documentation debt has been paid: [[Userguide]] gained [[using-with-liveview|its LiveView page]] (handlers, the params pluck, the `to_form(action:)` rule, running `mix demo`, and now the browser-test instructions and native-validation toggle below), and [[Techdocs]]' LiveView-shaped gaps were refreshed with as-of markers updated accordingly. The follow-on browser-testing work is also now documented: [[browser-testing|Techdocs/Browser testing]] (the mise toolchain, the `PLAYWRIGHT_E2E`-gated config, and what each seed test pins), [[18-decisions#D-022 — Browser-real tests are an opt-in, demo-driven Playwright suite|D-022]] and [[18-decisions#D-023 — The demo keeps native validation, behind a toggle|D-023]] in the decision log, and the closed [[16-open-questions#Rendering|step-7 open question]] on whether to adopt browser-real tests.

## Related

- [[13-roadmap|Planning/13 — Roadmap]]
- [[Planning]]
- [[Formentation|Vault entry note]]
