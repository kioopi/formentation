---
title: Techdocs
aliases:
  - Technical documentation
tags:
  - formentation
  - index
  - techdocs
status: draft
---

# Techdocs

**Current-state technical documentation** — a developer's-eye view of what Formentation *actually is right now*, not what it is planned to become. Architecture, data structures and their responsibilities, algorithms, data flows, and adapter boundaries, at a level above the moduledocs. For developers working *on* Formentation. The consumer-facing counterpart is [[Userguide]].

> [!important] Scope — only what exists
> Every note here describes code that is implemented and on the main line of development. Planned or in-flight layers do not appear until they land. When a note must reference something on the roadmap, it says so explicitly and links to [[Planning]] or [[Development]]. If a note is hard to write because a connecting piece is missing, that gap is a finding worth recording — not a reason to document the missing piece as if it existed.

> [!note] Freshness
> Because these notes track live code, they can go stale silently. Each note should carry an *as-of* marker (commit or date), and keep to architecture altitude — data structures, flows, and boundaries change less often than line-level detail, which belongs in moduledocs. Reviewing these notes is part of finishing a block of work; see the vault-maintenance guidance in `CLAUDE.md`.

## Contents

Start with [[end-to-end-data-flow|End-to-end data flow]] for the shape of the whole system; the notes after it are layer-by-layer deep dives.

0. [[end-to-end-data-flow|End-to-end data flow]] — one form followed through every layer that exists, and what crosses each boundary. **Written.**
1. [[compile-pipeline|Compile pipeline]] — architecture overview: how a declaration becomes a queryable `Definition`, and where that pipeline ends. **Written.**
2. [[definition-and-node|Definition and Node]] — the static `Definition` container and the semantic `Node` tree. **Written.**
3. [[source-adapters|Source adapters]] — the `Formentation.Source` behaviour, its two implementations, and the differential property that keeps them equivalent. **Written.**
4. [[paths-and-identity|Paths and identity]] — `TemplatePath` · `InstancePath` · `NodeId` · `JSONPointer`, the four coordinate spaces a node lives in. **Written.**
5. [[diagnostics-and-origins|Diagnostics and origins]] — the `Diagnostic`/`Issue` split, what produces diagnostics, and the simplified provenance model. **Written.**
6. [[form-state-and-transitions|Form state and transitions]] — the runtime state model, transport normalization, and the decode policy. **Written.**
7. [[phoenix-form-data|The FormData projection]] — how form state becomes an ordinary Phoenix form source. **Written.**
8. [[rendering|Rendering]] — the projector's data flow, render-node shapes, widget resolution, the reference theme's markup and accessibility contract, and the Phoenix-generic boundary. **Written.**
9. [[test-and-verification-architecture|Test and verification architecture]] — the kinds of test in the suite, what each pins, and the static gates in `mix ci`. **Written.**
10. [[browser-testing|Browser testing]] — the opt-in Playwright suite: the mise toolchain, the `PLAYWRIGHT_E2E`-gated config, what each seed test pins, and the native-validation toggle it depends on. **Written.**

## Related

- [[Userguide]] — the same system from a consumer's perspective
- [[Planning]] — the intended design these notes are measured against
- [[Formentation|Vault entry note]]
