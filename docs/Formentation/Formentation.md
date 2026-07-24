---
title: Formentation
aliases:
  - Formentation project
tags:
  - formentation
  - index
status: draft
---

# Formentation

Formentation is a declarative form-definition and rendering system for Elixir and Phoenix.

Its purpose is larger than rendering a JSON Schema as HTML. Formentation turns one or more declarative sources into an inspectable, source-independent description of a form. Runtime engines then combine that description with values, parameters, errors, and context to produce a render plan. Phoenix is the first intended presentation environment; JSON Schema and a plain Elixir data source are the first declaration sources — two from the start, so that source-independence is tested rather than assumed ([[18-decisions#D-004 — Two declaration sources from the start|D-004]]).

The project serves a concrete customer need first: expert-defined JSON payloads living beside relational data, entered and updated through generated forms. See [[00-use-case|Motivating use case]].

> [!summary] Central idea
> The project's centre is a static, introspectable `FormDefinition`—not JSON Schema, not `Phoenix.HTML.FormData`, and not a component library.

This arrangement permits the same definition to drive:

- Phoenix components and multiple UI themes;
- generated rudimentary UI configuration;
- documentation and form diagrams;
- support and accessibility reports;
- schema and UI-configuration diagnostics;
- JSON-backed form state;
- eventually, an existing `AshPhoenix.Form` or another Phoenix-compatible source of form state.

## Vault structure

This vault is organized into four areas, each introduced by an index note of the same name:

- [[Planning]] — the conceptual and design documentation (the numbered notes). *Why* the project exists and the intended architecture. Largely forward-looking.
- [[Development]] — the phase-by-phase implementation plans and their status. *Where the work is happening.*
- [[Techdocs]] — current-state technical documentation: architecture, data structures, and data flows of what is **actually built**. For developers working *on* Formentation.
- [[Userguide]] — practical documentation for developers *using* Formentation: setup, sources, configuration, adapters. Covers only shipped features.

Techdocs and Userguide describe the system as it exists today and grow alongside the code; Planning and Development describe the design and the plan. Loose exploratory notes that have not earned a place in the planning docs live outside the vault under `docs/discussion/`.

## Suggested reading path

1. [[00-use-case|Motivating use case]] records the concrete problem the project serves.
2. [[01-philosophy|Project philosophy]] explains why the project exists.
3. [[02-design-principles|Design principles]] turns the philosophy into engineering rules.
4. [[03-conceptual-model|Conceptual model]] defines the important kinds of data.
5. [[031-form-definition|Form definition]] examines the central data structure — the compiled, source-independent definition — in depth.
6. [[17-end-to-end-example|End-to-end example]] follows one small form through every layer.
7. [[04-architecture|Architecture]] shows the major components and boundaries.
8. [[05-compiler-pipeline|Compiler pipeline]] and [[06-runtime-projection|runtime projection]] describe the two principal engines.
9. [[07-phoenix-integration|Phoenix integration]] explains `FormData`, components, and LiveView concerns.
10. [[08-extension-model|Extension model]] defines how the system can support application-specific semantics and UI libraries.
11. [[09-diagnostics-provenance-introspection|Diagnostics, provenance, and introspection]] describes the project's explainability model.
12. [[10-algorithms|Algorithms and invariants]] records important implementation algorithms.
13. [[11-testing-strategy|Testing strategy]] describes how to test the whole system without relying only on HTML snapshots.
14. [[12-ecosystem-and-dependencies|Ecosystem and dependencies]] records inspirations and dependency decisions.
15. [[13-roadmap|Roadmap]] leads into a detailed implementation note for every phase.

Supporting notes include [[14-naming|naming]], [[15-glossary|the glossary]], [[16-open-questions|open design questions]], and [[18-decisions|the decision log]].

## Roadmap at a glance

| Phase | Outcome |
| --- | --- |
| [[phase-1-walking-skeleton\|1 — Walking skeleton]] | A form compiled from two sources renders, validates, and submits end to end through Phoenix. |
| [[phase-2-compiler-diagnostics\|2 — Compiler and diagnostics]] | Compilation becomes an ordered, explainable pipeline with verifiers, full provenance, and stable diagnostics. |
| [[phase-3-extensibility\|3 — Extensibility]] | Applications and UI packages can add semantics, codecs, widgets, themes, and compiler passes safely. |
| [[phase-4-dynamic-schemas\|4 — Dynamic schemas]] | Conditional and compositional schemas can be projected against changing data without losing state. |
| [[phase-5-ash-integration\|5 — Ash integration]] | The same rendering concepts can work with Ash declarations and `AshPhoenix.Form`. |

## Working project statement

> Formentation compiles declarative descriptions of forms into a stable semantic definition, projects that definition against runtime state, and renders it through replaceable presentation systems.

The statement intentionally does not promise complete support for every JSON Schema keyword or every UI toolkit. See [[02-design-principles#Anything, not everything|Anything, not everything]].

## Current naming

“Formentation” is a useful working name: it contains “form,” suggests formation and transformation, and does not bind the project to JSON Schema. It is not a standard English word, which may help distinctiveness but may also require explanation. Alternatives and naming checks are recorded in [[14-naming|Naming]].

## Project status

These notes describe an intended architecture and incremental implementation plan. They are not yet an API stability promise. Important unresolved decisions are listed in [[16-open-questions|Open questions]].

Implementation began on 2026-07-21. As of 2026-07-23, [[phase-1-walking-skeleton|Phase 1]] runs end to end for a static render: both source adapters compile to a `Definition`, `Formentation.Form` holds runtime state and applies replace transitions, `Phoenix.HTML.FormData` projects that state, and the projector plus reference theme render it as accessible HTML — [[17-end-to-end-example|the end-to-end example]] is pinned as a reviewed snapshot. The remaining Phase 1 work is the LiveView lifecycle (step 7) and collections (Milestone B). [[Development]] carries the phase-status table; [[Techdocs]] documents what is built and [[Userguide]] how to use it.

