---
title: Planning
aliases:
  - Planning docs
tags:
  - formentation
  - index
status: draft
---

# Planning

The **conceptual and design documentation** for Formentation: why the project exists, the shape of its data, and the boundaries between its parts. These notes describe the *intended* architecture — they are largely forward-looking and are the reference the implementation is measured against, not a record of what is built. For what actually exists today, see [[Techdocs]].

The recommended reading order lives in the [[Formentation|vault entry note]]. This index groups the notes by kind.

> [!important] Current architectural direction
> [[19-north-star-architecture|19 — North-star architecture]] defines the
> intended public model and ownership boundaries before `0.1.0`. It is
> authoritative where an older forward-looking planning note still describes
> the mixed Phase 1 prototype.
> [[20-renderer-ui-model|20 — Renderer and UI model]] extends that direction
> for prepared views, widget transport, localization, component-library
> integrations, capabilities, customization, limits, and visual themes without
> prematurely freezing the Phase 3 contracts.

## Foundations

- [[00-use-case|00 — Motivating use case]]
- [[01-philosophy|01 — Project philosophy]]
- [[02-design-principles|02 — Design principles]]
- [[03-conceptual-model|03 — Conceptual model]]
- [[031-form-definition|031 — Form definition]]
- [[17-end-to-end-example|17 — End-to-end example]]
- [[19-north-star-architecture|19 — North-star architecture]]

## Architecture and engines

- [[04-architecture|04 — Architecture]]
- [[05-compiler-pipeline|05 — Compiler pipeline]]
- [[06-runtime-projection|06 — Runtime projection]]
- [[07-phoenix-integration|07 — Phoenix integration]]
- [[08-extension-model|08 — Extension model]]
- [[09-diagnostics-provenance-introspection|09 — Diagnostics, provenance, introspection]]
- [[10-algorithms|10 — Algorithms and invariants]]
- [[20-renderer-ui-model|20 — Renderer and UI model]]

## Process and reference

- [[11-testing-strategy|11 — Testing strategy]]
- [[12-ecosystem-and-dependencies|12 — Ecosystem and dependencies]]
- [[13-roadmap|13 — Roadmap]]
- [[14-naming|14 — Naming]]
- [[15-glossary|15 — Glossary]]
- [[16-open-questions|16 — Open questions]]
- [[18-decisions|18 — Decision log]]

## Related

- [[Development]] — phase-by-phase implementation plans
- [[Formentation|Vault entry note]]
