---
title: Formentation Testing Strategy
tags:
  - formentation
  - testing
status: draft
---

# Testing strategy

Formentation should be tested as a compiler, a runtime state system, and a renderer. HTML snapshots alone cannot establish correctness, and unit tests alone will miss path and lifecycle integration failures.

## Testing layers

### Semantic fixtures

Maintain a small corpus of named declaration fixtures. Each fixture should identify:

- source dialect;
- supported and intentionally unsupported constructs;
- expected semantic nodes;
- expected diagnostics;
- representative valid and invalid instances;
- optional UI hints;
- required renderer capabilities.

Fixtures should be readable and focused. A single “everything schema” is useful as a smoke test but poor at locating failures.

### Compiler unit tests

Test each source-mapping function, transformer, verifier, and index builder with structured assertions.

Prefer:

```elixir
assert %Node.Field{role: :date} = Info.node_at(definition, ["birth_date"])
```

over a complete `inspect(definition)` snapshot. Use snapshots selectively for diagnostics and explanations where human-readable stability is itself a feature.

Properties worth testing:

- deterministic compilation;
- stable IDs for unchanged declarations;
- no duplicate nodes or indexes;
- verifiers do not mutate definitions;
- rebuilding indexes yields equivalent indexes;
- all decision origins point to known sources or rules;
- pass ordering is stable and cycles are diagnosed;
- budgets terminate adversarial recursive inputs.

### Validator adapter contract tests

Every validator adapter should pass the same suite:

- valid/invalid instance agreement for the supported dialect subset;
- structured instance and schema locations;
- required-property normalization;
- reference and recursive-reference cases;
- composition branch context;
- remote resolution policy;
- no reliance on parsing formatted messages.

Where two validators are supported, differential tests can reveal adapter mistakes. Differences allowed by dialect or output format must be documented rather than normalized away incorrectly.

### Codec tests

Test raw parameter preservation, successful conversion, failure issues, nesting, arrays, absence versus empty string, null policy, and locale behaviour.

Round-trip properties are useful where encoding is canonical:

```elixir
encode(decode(encode(value))) == encode(value)
```

Do not demand `decode(encode(value)) == value` for lossy browser representations unless the codec contract promises it.

### Projection tests

Projection tests use a compiled definition plus a fake state view. Assert:

- visible node sequence;
- active branch and reason;
- issue association;
- stable collection identity;
- no mutation of state;
- deterministic output for equivalent inputs;
- `unknown` condition behaviour;
- preservation of inactive branch data.

A fake state view keeps these tests independent of Phoenix.

### Phoenix and component tests

Use Phoenix component rendering tests and HTML parsing rather than raw string comparison for most assertions.

Verify:

- input names and IDs;
- labels, help text, and error associations;
- nested `inputs_for` behaviour;
- hidden collection identifiers;
- translated errors;
- escaping of untrusted schema annotations;
- theme capability fallbacks;
- accessible fieldsets, legends, and summaries.

Keep a small number of intentional rendered snapshots for human review of each reference theme.

### LiveView lifecycle tests

End-to-end LiveView tests should cover:

- initial render;
- validation after raw param changes;
- failed decoding without input loss;
- adding, removing, and reordering collection items;
- conditional branch changes;
- submit success and failure;
- focus and DOM stability where testable;
- preserving values in inactive branches according to policy.

### Extension conformance tests

Publish reusable test modules for source adapters, codecs, compiler passes, renderers, themes, and widgets. See [[08-extension-model#Conformance suite|Extension conformance suite]].

### Ash integration tests

Use real Ash resources/actions for embedded resources, `manage_relationship`, create/update differences, sparse lists, unions, nested errors, and add/remove operations. The renderer should consume the existing Ash form lifecycle instead of emulating it.

## Golden files

Golden files are appropriate for:

- normalized diagnostics;
- `Info.explain` output;
- support reports;
- generated default UI hints;
- selected definition projections with volatile fields removed.

Every golden update should be reviewed semantically. Avoid snapshots containing map-order noise, generated IDs, or entire opaque structs.

## Property and generative testing

[StreamData](https://hexdocs.pm/stream_data/StreamData.html) can generate bounded schema/value fragments for invariants:

- compilation always terminates within configured budgets;
- path encode/decode round-trips;
- stable identifiers do not depend on map insertion order;
- issue prefix/group operations preserve all issues;
- projection never invents a semantic node;
- renderer plans refer only to supported widgets after successful verification.

Generating arbitrary complete JSON Schema is not necessary. Generate a documented supported grammar and add regression fixtures for discoveries.

## Compatibility matrix

Track tests by:

- supported JSON Schema dialect;
- Elixir/OTP versions;
- Phoenix HTML and LiveView versions;
- validator adapter;
- reference theme;
- strictness mode.

Avoid claiming dialect-wide support when only selected keywords are covered. The matrix should link to a machine-readable feature registry if one is created.

## Performance testing

Benchmark separately:

- source loading/resolution;
- cold compilation;
- cached definition lookup;
- full projection;
- branch-only projection when implemented;
- component rendering;
- large collection state transitions.

Include adversarial depth, breadth, and reference graphs. Performance tests must retain correctness assertions so a faster fallback does not silently omit nodes.

## Test architecture rules

- Test through `Info` APIs when possible.
- Assert structured codes and paths before formatted messages.
- Keep source fixtures independent of renderer fixtures.
- Give every production bug a minimal regression fixture.
- Run extension contract suites in extension repositories.
- Treat the second theme and Ash adapter as architectural integration tests.

## Related notes

- [[09-diagnostics-provenance-introspection|Diagnostics and introspection]]
- [[10-algorithms|Algorithms and invariants]]
- [[13-roadmap|Roadmap]]
- Every phase note contains its phase-specific test plan.

