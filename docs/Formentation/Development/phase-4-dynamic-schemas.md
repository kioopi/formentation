---
title: Phase 4 — Dynamic and Compositional Schemas
tags:
  - formentation
  - roadmap
  - phase-4
  - json-schema
status: planned
phase: 4
---

# Phase 4 — Dynamic and compositional schemas

## Goal

Support useful conditional and compositional schema behaviour during interactive editing while preserving values, errors, branch identity, and correct validation semantics.

This is the phase in which the static-definition/dynamic-projection split does its most important work.

## Risk being retired

The risk is that JSON Schema composition cannot be converted into a deterministic form without either changing validation meaning or producing unstable user interfaces. The objective is not to make every composition automatically beautiful; it is to represent, project, explain, and diagnose it correctly.

## Initial feature subset

Introduce features incrementally:

1. `if` / `then` / `else` with bounded predicates;
2. `dependentRequired` and selected dependent-schema use cases;
3. `oneOf` with explicit UI discriminator support;
4. `anyOf` in modes where multiple branch sections can be presented;
5. safe, verified presentation combination for selected `allOf` patterns;
6. tuple/prefix-item arrays if not already supported;
7. recursive definitions with bounded rendering policy.

For each feature, distinguish validation support, definition support, automatic
preparation support, and reference-UI support.

## Deliverables

### Condition AST

A source-independent expression representation supporting:

- validation against a compiled schema predicate;
- equality/presence predicates needed by explicit UI rules;
- Boolean composition;
- three-valued evaluation `true | false | unknown`;
- dependency extraction;
- provenance and explanation.

Custom predicate modules remain an escape hatch and must declare dependencies.

### Composition nodes

- explicit `oneOf`, `anyOf`, `allOf`, and conditional representation;
- branch IDs stable across projection;
- branch labels/titles and UI metadata;
- no unverified syntactic object merging;
- retained source/evaluation locations.

### Branch state policy

- explicit user discriminator where configured;
- retained selection across validation cycles;
- exactly-one-valid inference;
- ambiguous/no-match policy;
- inactive data retention by default;
- state-engine submission/pruning policy separate from render visibility.

### Projection

- dependency-aware condition evaluation;
- concrete active-branch render nodes;
- branch-level diagnostics and explanations;
- collection/branch stable identity;
- full reprojection correctness first;
- optional partial reprojection prototype after dependencies are reliable.

### Renderer components

- branch selector/discriminator;
- conditional group container;
- ambiguous/no-valid-branch feedback;
- multiple active sections for supported `anyOf` mode;
- recursive-node placeholder or bounded expansion controls.

### Developer tooling

- explanation of why a branch is active;
- dependency graph query;
- warning when automatic branch choice is ambiguous;
- visualization/debug output for conditions and branches;
- support matrix updated per feature and mode.

## Implementation strategy

### Step 1: Build condition evaluation independently

Compile predicates and test three-valued evaluation without rendering. Use the validator adapter for schema predicates rather than duplicating validation.

### Step 2: Add explicit-discriminator `oneOf`

This is the most controllable interactive form. The UI declaration identifies a discriminator and branch mapping. Preserve the selected branch in form state.

### Step 3: Add validator-guided selection

Only after explicit selection works, attempt exactly-one-valid inference. Treat zero or multiple matches as first-class intermediate states.

### Step 4: Add conditions

Implement `if`/`then`/`else` and dependencies using the same condition/projection machinery. Verify inactive-value policy with LiveView tests.

### Step 5: Approach `allOf` conservatively

Define a verifier for safe presentation combination. When proof is unavailable, preserve branches and render grouped conjunction or require UI guidance.

### Step 6: Add optimization after instrumentation

Measure full projection. Implement subtree reprojection only if it matters and dependency declarations are complete. A custom predicate without dependencies forces full projection.

### Step 7: Evaluate Crux for restricted UI rules

[Crux](https://github.com/ash-project/crux) may help simplify Boolean UI predicates, detect contradictions, or build decision trees. Do not translate general JSON Schema into SAT. Adopt it only if the restricted condition AST produces a demonstrated need.

## Testing strategy

### Condition tests

- true/false/unknown for absent and malformed values;
- Boolean composition;
- dependency extraction;
- source provenance;
- custom predicate dependency contract;
- no evaluation of unrelated values where avoidable.

### Branch tests

- explicit discriminator selects the intended branch;
- selection persists when branch content is temporarily invalid;
- exactly one valid branch is inferred;
- zero valid and multiple valid branches remain representable;
- `oneOf` ambiguity is not hidden;
- `anyOf` permits multiple matches according to presentation mode;
- branch IDs remain stable.

### State-preservation tests

- switching away and back retains values by default;
- hidden values are not deleted during render/projection;
- explicit clearing policy acts only on a state transition;
- errors are associated with active/inactive branches according to documented policy;
- submit pruning and validation are separate operations.

### Composition semantic tests

Use official JSON Schema test-suite cases where compatible with the validator. Ensure Formentation's UI transformations do not change validator outcomes.

### LiveView tests

- conditional field appears/disappears after changes;
- no focus/DOM identity churn beyond the affected subtree;
- ambiguous branch UI is actionable;
- nested conditional collections work within budgets;
- recursive expansion is bounded.

### Property tests

- projection terminates for bounded generated composition graphs;
- every rendered branch exists in the definition;
- dependency-driven reprojection matches full projection when implemented;
- inactive-data policy never mutates state during projection.

## Definition of done

- [ ] The supported modes of `if`/`then`/`else`, dependencies, and composition are documented separately from validator support.
- [ ] A condition AST provides three-valued evaluation, dependencies, provenance, and explanation.
- [ ] `oneOf` works with an explicit discriminator and handles zero/multiple matches honestly.
- [ ] Branch switching preserves inactive data by default.
- [ ] Preparation and rendering never syntactically merge `allOf` without a
      verified safe transformation.
- [ ] Branch-level errors are summarized without overwhelming users with raw validator branch failures.
- [ ] LiveView lifecycle tests cover condition and branch transitions.
- [ ] Recursion, depth, branch count, and projection work have enforced budgets.
- [ ] Partial reprojection, if shipped, is proven equivalent to full projection for the same inputs.
- [ ] A recorded decision explains whether Crux is useful for the restricted condition domain.

## Notes of caution

- A schema can be valid but have no pleasant automatic form.
- “Best matching branch” heuristics are dangerous unless explainable and reversible.
- Do not use `oneOf` branch order as permanent user state.
- Hidden UI does not change server authorization or validation.
- Composition error trees can be enormous; normalize and summarize without discarding structured detail.
- Remote or recursive predicates need strict budgets.
- Applying defaults in inactive branches can create values that unexpectedly activate other conditions.
- Preserve the difference between absent, null, invalid raw text, and decoded values.

## Exit and next phase

The phase ends when dynamic behaviour is correct and explainable for a declared subset. [[phase-5-ash-integration|Phase 5]] then tests whether the architecture can reuse these rendering semantics with an independent, highly capable form engine.

## Related notes

- [[06-runtime-projection|Runtime projection]]
- [[10-algorithms#Conditional projection|Conditional projection algorithm]]
- [[12-ecosystem-and-dependencies#Crux|Crux]]
- [[11-testing-strategy#LiveView lifecycle tests|LiveView testing]]
- [[13-roadmap|Back to the roadmap]]
