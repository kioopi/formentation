---
title: Formentation Design Principles
tags:
  - formentation
  - design
status: draft
---

# Design principles

These principles are intended to guide API and implementation decisions. Where two attractive designs conflict, prefer the one that follows more of these principles.

## The semantic definition is the centre

JSON Schema is a source adapter. Phoenix is a runtime and presentation adapter. A theme is a presentation policy. None owns the central model.

Public APIs should make it natural to compile, inspect, project, and render a `Formentation.Definition` independently.

## Anything, not everything

Borrowing the phrase from the [Ash design principles](https://github.com/ash-project/ash/blob/main/documentation/topics/about_ash/design-principles.md), the core should be capable of supporting application-specific behaviour without containing every behaviour.

Consequences:

- ship a small, useful semantic vocabulary;
- define typed extension points;
- publish renderer capabilities;
- report unsupported constructs explicitly;
- avoid a universal widget callback receiving an unstructured bag of options.

## Declarative, introspectable, derivable

Important choices must become data. A widget inference rule that exists only as control flow is difficult to inspect. A `%Decision{value: :select, source: ...}` can be queried, tested, explained, serialized, and used by other tools.

The definition should support a stable [[09-diagnostics-provenance-introspection#The Info API|Info API]]. Consumers should not need to duplicate source-processing logic.

## Static and dynamic concerns remain separate

Compilation answers questions that depend only on declarations and configured extensions. Projection answers questions that depend on current values, errors, action, locale, permissions, or renderer capabilities.

Do not compile a conditional schema according to initial values. Do not resolve `$ref` during every render. See [[05-compiler-pipeline|Compiler pipeline]] and [[06-runtime-projection|Runtime projection]].

## Validation semantics have a single owner

The selected JSON Schema validator owns JSON Schema validity. Formentation translates validator output and derives form semantics; it should not maintain a subtly different validator in its renderer.

HTML attributes such as `required`, `min`, and `pattern` are progressive user-interface aids. They do not replace server-side validation, and they should be emitted only when their meaning is compatible with the schema.

## Paths are typed concepts

Do not use one loosely typed list to represent all locations. At minimum distinguish:

- schema location;
- instance path;
- UI-configuration location;
- Phoenix field path/name;
- runtime collection item identity;
- DOM identifier.

Conversions should be explicit and tested. See [[10-algorithms#Paths and identity|Paths and identity]].

## Provenance survives derivation

Compilation must not erase where information came from. Schema annotations, UI hints, theme defaults, inference rules, call-site overrides, and extensions should all be identifiable in the resolved decision.

This enables actionable diagnostics and explanation. See [[09-diagnostics-provenance-introspection|Diagnostics, provenance, and introspection]].

## Behaviours only at real seams

Use behaviours where independently implemented modules must be replaceable:

- declaration source adapters;
- validator adapters;
- compiler passes and verifiers;
- codecs;
- semantic widgets and renderers;
- possibly runtime state engines.

Use ordinary pure functions for fixed internal steps. A behaviour for every helper makes navigation and evolution harder.

## Extensions declare capabilities

An extension should publish what it adds. A renderer should publish what it supports. Compatibility can then be verified before rendering.

An extension that adds a widget must not silently redefine validation. Separate schema-vocabulary, semantic-compilation, and presentation extensions. See [[08-extension-model|Extension model]].

## Prefer explicit decisions over destructive merges

Schema annotations, inference, themes, UI hints, and call-site overrides form precedence layers. Do not discard losing values immediately. Retain enough information to explain the winning value and diagnose conflicting configuration.

## Determinism and purity by default

Given the same declarations, extensions, and compiler options, compilation should produce an equivalent definition and fingerprint. Compiler passes should be pure unless an explicit source loader or resolver boundary performs I/O.

This improves caching, reproducibility, testability, and LiveView behaviour.

## Bounded processing

Untrusted or simply unfortunate schemas can contain deep recursion, large graphs, remote references, and expensive branch structures. Resolution and traversal require explicit budgets, cycle handling, and remote-fetch policy.

## Stable public queries, evolvable structs

Provide `Formentation.Info` functions for common access. Structs can be visible for debugging and extension development, but their complete layout should not become the only public API.

## Pragmatism first

Start with one end-to-end useful path. Add abstraction when implementation experience reveals duplication, hidden divergence, or a real extension requirement. Preserve upgrade paths by versioning the definition and diagnostics.

## Related notes

- [[01-philosophy|Project philosophy]]
- [[03-conceptual-model|Conceptual model]]
- [[08-extension-model|Extension model]]
- [[13-roadmap|Roadmap]]
- [[Formentation|Back to the entry point]]

