---
title: Phase 2 — Compiler Pipeline and Diagnostics
tags:
  - formentation
  - roadmap
  - phase-2
  - compiler
status: planned
phase: 2
---

# Phase 2 — Compiler pipeline and diagnostics

## Goal

Turn the direct prototype compiler into a deliberate, ordered, observable compilation system with transformers, read-only verifiers, provenance, support reports, explanation APIs, and definition caching.

This phase also pays back the introspection debt deliberately taken on in [[phase-1-walking-skeleton|Phase 1]] ([[18-decisions#D-003 — Simplified provenance first|D-003]]): origin tags grow into the full `Decision`/derivation model, `Info.explain/3` becomes public API, and fingerprints, support reports, and generated UI hints arrive here.

## Risk being retired

As source features and UI hints grow, one recursive function can accumulate hidden ordering, destructive merges, inconsistent warnings, and duplicated derivation logic. This phase prevents that complexity from becoming the permanent architecture.

## Scope

This phase is about compiler structure and developer experience, not dramatically expanding the JSON Schema feature set. Add only schema features needed to prove compiler stages, such as references or one additional annotation family.

## Deliverables

### Compiler phases

Formalize:

- load/parse boundary;
- normalize/resolve;
- semantic construction;
- derive;
- decorate;
- verify;
- finalize/index/fingerprint.

Document which data each phase may read and write.

### Pass and verifier contracts

- named pass behaviour;
- stable phase and before/after declarations;
- topological ordering with useful cycle errors;
- read-only verifier behaviour;
- structured pass warnings/errors;
- compiler context and budgets.

### Provenance

- origin table or derivation graph;
- provenance for schema facts, inference, UI hints, theme defaults, overrides, and extensions;
- related origins on conflicts;
- formatter showing source URI/pointer and derivation steps.

### Diagnostics

- stable classes, codes, severities, hints, details, and related locations;
- strict/standard/permissive policy;
- warning promotion and code-specific suppression;
- instance issues remain separate;
- provider-specific errors normalized at adapter boundaries.

### Introspection

Expand `Formentation.Info` with dependency, required-capability, support-report, diagnostic, origin, and explanation queries. Document it as a public compatibility surface.

### Caching and telemetry

- deterministic fingerprint inputs;
- a pluggable/simple cache boundary;
- cache invalidation through compiler/extension version changes;
- telemetry for compilation duration, cache hit/miss, node count, and diagnostic counts without submitted values.

### Development tooling

- human-readable definition tree;
- compiler trace listing passes and produced decisions;
- support report grouped by feature and severity;
- generated rudimentary UI hints for the supported subset (deferred from Phase 1);
- optional Mix task to compile/check application-owned schema files.

## Implementation strategy

### Step 1: Inventory the Phase 1 compiler

List every place that normalizes, derives, overrides, validates, or indexes. Extract phase boundaries based on existing work, not the idealized diagram alone.

### Step 2: Introduce pass descriptors

Convert one derivation at a time. Preserve output equivalence through existing fixtures. Begin with fixed built-in passes before loading third-party extensions.

### Step 3: Make verification read-only

Move all late “repair” logic into named transformers. Freeze or compare definitions around verifiers in tests to ensure they do not mutate through hidden state.

### Step 4: Add provenance references

Avoid inflating every node with repeated origin structs if profiling shows concern. A definition-level origin table with compact references can retain full information.

### Step 5: Stabilize diagnostic codes

Codes are more stable than English messages. Write a registry or documentation table and use structured fields in tests.

### Step 6: Add caching last

Only cache after determinism and fingerprint tests are strong. First use process-local or application-provided storage; distributed cache serialization is out of scope.

## Testing strategy

### Pass tests

- individual input/output;
- deterministic output;
- no duplicate application;
- declared phase and ordering;
- structured warning/error propagation;
- unchanged definitions when a pass is inapplicable.

### Ordering tests

- phase edges;
- before/after edges;
- stable tie-breaking;
- unknown dependency diagnostics;
- smallest useful cycle report;
- extension registration order does not change a fully constrained result.

### Verifier tests

- success, warning, and error results;
- no mutation;
- renderer capability mismatch;
- orphan UI path;
- conflicting decisions;
- invalid indexes and duplicate IDs.

### Provenance tests

- every explained decision has an origin;
- override explanations include superseded candidates;
- source pointer and document identity survive `$ref`;
- diagnostic related locations identify both sides of a conflict;
- no runtime values enter compiler diagnostics.

### Fingerprint/cache tests

- equivalent canonical inputs have equal fingerprints;
- meaningful source/config/extension changes alter the fingerprint;
- map insertion order, process, and time do not;
- cache hit returns an equivalent definition and warnings;
- compiler version invalidates old entries.

### Golden tests

Review diagnostic formatting, support reports, explanation chains, and compiler traces.

## Definition of done

- [ ] Built-in compiler work runs through documented ordered phases.
- [ ] All passes and verifiers have focused tests.
- [ ] Ordering cycles and unknown dependencies produce structured diagnostics.
- [ ] A developer can ask why a field has its role, widget, label, and required state.
- [ ] Conflicting UI/source decisions identify all relevant origins.
- [ ] Strictness changes policy without changing diagnostic production.
- [ ] Fingerprints are deterministic and cache behaviour is tested.
- [ ] `Formentation.Info` is documented as the preferred query API.
- [ ] A support report can be generated without rendering.
- [ ] Telemetry contains no raw submitted values by default.

## Notes of caution

- Do not turn every function into a pass.
- Avoid exposing the entire mutable/compiler state API as public.
- Passes should not perform hidden network I/O; source loading is explicit.
- Diagnostic message wording may change, but codes and structured fields need migration discipline.
- Be wary of module names and anonymous functions in deterministic fingerprints.
- Do not add Spark merely because the architecture resembles it; evaluate it in [[phase-3-extensibility|Phase 3]] when external extension tooling is real.
- A warning suppression system can hide valuable information; keep suppressed diagnostics introspectable when possible.

## Exit and next phase

The phase ends with a compiler that can grow safely. [[phase-3-extensibility|Phase 3]] then exposes selected seams to applications and independent renderer/theme packages.

## Related notes

- [[05-compiler-pipeline|Compiler pipeline]]
- [[09-diagnostics-provenance-introspection|Diagnostics and introspection]]
- [[10-algorithms#Pass ordering|Pass ordering]]
- [[12-ecosystem-and-dependencies#Spark|Spark inspiration]]
- [[13-roadmap|Back to the roadmap]]

