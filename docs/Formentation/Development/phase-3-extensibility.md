---
title: Phase 3 — Extensibility and Themes
tags:
  - formentation
  - roadmap
  - phase-3
  - extensions
status: planned
phase: 3
---

# Phase 3 — Extensibility and themes

## Goal

Allow applications and independent UI packages to extend Formentation without copying the compiler or pattern-matching on unstable internals.

The phase is complete only when two concrete proofs exist:

1. a second visual theme/renderer mapping implemented outside the core reference theme;
2. an application extension adding a semantic role, codec, widget, compiler rule, verifier, and diagnostics.

## Risk being retired

The risk is an extension story that looks clean in behaviours but requires internal knowledge in practice. The second implementations reveal accidental assumptions about markup, state, paths, component assigns, and compiler ordering.

## Scope

Add public contracts for:

- extension descriptors;
- compiler passes and verifiers approved for third-party use;
- semantic roles and custom node kinds;
- codecs;
- predicates with declared dependencies;
- renderers, widgets, containers, and themes;
- capability publication and compatibility verification;
- extension conformance tests.

Do not yet promise permanent 1.0 stability. Mark experimental callbacks and version descriptors so migration can be managed.

## Deliverables

### Extension registry

- explicit extension descriptor with name/version;
- deterministic registration and duplicate handling;
- namespaced extension metadata;
- contribution lists for passes, verifiers, codecs, roles, nodes, and presentation components;
- inclusion in definition fingerprint and support report.

### Capability model

- renderer capability struct;
- required capabilities derived from definitions;
- compile-time or pre-projection compatibility verifier;
- strict versus fallback policy;
- structured explanation of missing capability and possible replacement.

### Renderer/theme contract

- abstract widget keys distinct from roles;
- component registry and assign contract;
- group, collection, field, choice, help/error, and unsupported-node containers;
- accessible markup obligations;
- documented customization through data, components, and limited slots;
- no source-schema traversal in components.

### Codec and custom predicate contracts

- typed callback results and path-aware issues;
- explicit encode/decode context;
- dependency declarations for predicates;
- deterministic behaviour guidelines;
- state-engine lookup by semantic role or explicit codec key.

### Conformance suites

Reusable ExUnit helpers for:

- extensions;
- passes/verifiers;
- codecs;
- widgets/themes;
- source adapters if the boundary is mature enough.

### Proof extensions

- a second theme with meaningfully different markup or styling conventions;
- a `money` or similarly rich domain extension;
- a sample application showing explicit override of one widget and one container;
- compatibility report demonstrating failure when the extension is used with a renderer that lacks its widget.

### Optional DSL decision spike

Prototype the same extension configuration with plain data/builders and [Spark](https://github.com/ash-project/spark). Evaluate:

- compile-time source annotations;
- generated documentation and autocomplete;
- extension composition;
- transformer/verifier integration;
- dependency and learning cost;
- runtime/dynamic configuration needs.

The output is a decision record, not necessarily a Spark dependency.

## Implementation strategy

### Step 1: Extract from the reference theme

Inventory every hard-coded role, widget, component, and wrapper. Move only the concepts needed by both the original and second theme into public contracts.

### Step 2: Build the second theme concurrently

Do not finalize the contract and then ask a second theme to use it. Evolve them together so the contract remains implementable.

### Step 3: Build one vertical domain extension

A `money` example should include:

- source annotation/format recognition;
- role derivation;
- currency verification;
- raw amount decoding;
- a widget;
- renderer capability;
- explanation chain;
- submitted error translation.

This exercises all extension categories and reveals where validation semantics must remain separate.

### Step 4: Publish conformance tests

Move common expectations from core tests into reusable helpers. Make failures explain which extension contract was broken.

### Step 5: Version extension descriptors

Include a contract/API version separate from an extension's package version. Reject incompatible versions with a diagnostic before running passes.

### Step 6: Decide on Spark later in the phase

Evaluate Spark only after plain descriptors have shown their shape. Any DSL must compile to those descriptors and remain optional for runtime schemas.

## Testing strategy

### Registry tests

- deterministic registration;
- duplicate name/version errors;
- namespaced metadata;
- pass ordering across extensions;
- fingerprint changes;
- incompatible contract version diagnostics.

### Capability tests

- exact supported combination succeeds;
- missing widget/feature produces actionable diagnostic;
- permissive fallback is explicit and explained;
- explicit unsupported widget does not silently disappear in strict mode;
- capability values are deterministic.

### Codec conformance

- success/failure shapes;
- raw input preservation;
- path prefixing in nested collections;
- encode/decode canonical round-trip where promised;
- no raising for ordinary user errors.

### Theme/widget conformance

- required assigns;
- escaping;
- label/input/help/error association;
- fieldsets and legends;
- form error summary links;
- collection controls and stable IDs;
- unsupported-node rendering policy.

### Cross-product tests

Run core definitions against both themes and the domain extension against supporting and non-supporting renderers. Keep the matrix intentionally small but meaningful.

## Definition of done

- [ ] A second theme is implemented without modifying core compiler or projector code.
- [ ] A domain extension adds role, codec, widget, pass, verifier, and explanation through public contracts.
- [ ] Renderer capabilities are machine-readable and verified before component execution.
- [ ] Missing support produces a structured diagnostic with origin and hint.
- [ ] Extension contributions affect deterministic fingerprints.
- [ ] Conformance suites are documented and used by both proof implementations.
- [ ] UI extensions cannot silently redefine JSON Schema validation semantics.
- [ ] Public customization covers whole-form, container, and individual widget needs without requiring traversal forks.
- [ ] A documented decision is made about adopting, deferring, or rejecting a Spark DSL at this stage.

## Notes of caution

- Behaviours are not sufficient if implementations must read private structs.
- Do not use a single unconstrained `render(node, opts)` callback as the entire extension model.
- Theme classes and component functions can make definitions non-serializable; keep presentation registry references out of the stable semantic fingerprint where appropriate, or fingerprint by named identity.
- A permissive fallback must remain visible in diagnostics.
- Custom predicates must report dependencies or opt out of partial projection.
- Avoid global application configuration that prevents two themes or extension sets from coexisting.
- Do not publish a Spark DSL that is the only way to construct extension descriptors.

## Exit and next phase

With proven extension boundaries, [[phase-4-dynamic-schemas|Phase 4]] can add conditional and compositional features without hard-coding every branch interaction into the renderer.

## Related notes

- [[08-extension-model|Extension model]]
- [[05-compiler-pipeline|Compiler pipeline]]
- [[12-ecosystem-and-dependencies#Spark|Spark]]
- [[11-testing-strategy#Extension conformance tests|Extension conformance tests]]
- [[13-roadmap|Back to the roadmap]]

