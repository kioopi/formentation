---
title: Formentation Algorithms and Invariants
tags:
  - formentation
  - algorithms
status: draft
---

# Algorithms and invariants

This note records algorithms whose correctness affects several layers. They deserve focused tests and should not be reimplemented ad hoc in adapters or renderers.

## Paths and identity

Represent distinct path types with structs or tagged tuples:

```elixir
%SchemaLocation{document_uri: uri, pointer: "/properties/name"}
%UIPath{pointer: "/name/ui:widget"}
%InstancePath{segments: ["addresses", 2, "postcode"]}
%TemplatePath{segments: ["addresses", :item, "postcode"]}
%FormPath{segments: ["addresses", 2, "postcode"]}
```

Form path segments are strings, never atoms. Schema property names are untrusted input, and converting them to atoms would leak memory; `Phoenix.HTML.Form` supports string field access. Structural markers such as `:item` in template paths are safe because they come from a fixed internal vocabulary.

Conversions are partial functions. A schema location does not always correspond to an instance path: `allOf`, condition predicates, and annotations can apply without introducing a property segment.

### Stable node IDs

Derive a node's static identity from canonical source identity plus its semantic position, not traversal order alone. A candidate input is:

```text
source-adapter | canonical-document-uri | schema-pointer | semantic-kind | occurrence
```

Do not include compiler or definition-format versions in node identity: the definition fingerprint already carries them, and including them here would rename every node on every upgrade, breaking golden tests and cross-version comparisons for unchanged declarations.

Hash this input for compactness while retaining the original origin for debugging. Duplicate semantic nodes derived from one source location require an explicit occurrence/discriminator.

Runtime collection item identity is separate and must not be folded into the static node ID.

## Reference graph construction

Use a registry keyed by canonical schema resource and location.

1. Register a document/resource before visiting children.
2. When encountering a reference, resolve its canonical target through the validator/resolver adapter.
3. Add an edge to the target rather than copying the target subtree.
4. Track the active resolution stack to identify cycles.
5. Permit cycles represented as graph edges; reject only cycles forbidden by source semantics or processing policy.
6. Enforce maximum documents, bytes, reference edges, and traversal depth.

Traversal functions need a choice between `follow_refs?: false`, follow-once, and budgeted expansion.

## Pass ordering

Build a directed graph from phase order plus `before`/`after` constraints.

1. Validate unique pass names.
2. Add edges implied by fixed phase order.
3. Add explicit dependency edges.
4. Topologically sort with stable tie-breaking by registered name, not map enumeration.
5. If a cycle remains, return a diagnostic containing the shortest useful cycle.

The output order becomes part of the compiler fingerprint.

## Configuration resolution

For every configurable decision:

1. collect candidates with value, origin, precedence, and compatibility predicate;
2. discard inapplicable candidates while retaining rejection reasons for explanation;
3. find the highest-precedence compatible candidates;
4. if exactly one value remains, choose it;
5. if equivalent values remain, choose deterministically and retain origins;
6. if conflicting values remain without an ordering rule, emit a conflict diagnostic;
7. store the winner and relevant superseded candidates.

Do not implement UI configuration as a recursive `Map.merge/3`; arrays, ordering, inheritance, and semantic conflicts need domain-specific handling.

## Role and widget inference

Role inference should use a ranked rule registry. More specific semantic facts beat general type defaults:

```text
explicit role
custom vocabulary/format rule
const or enum role
format rule
content encoding/media type
type plus constraints
primitive type default
unsupported
```

Widget resolution follows role selection and renderer/UI compatibility. An
explicit unsupported widget should produce a diagnostic rather than silently
selecting a different widget unless an explicit fallback policy permits and
explains the substitution.

## Conditional projection

Compile conditions into a small expression AST with declared dependencies. At runtime:

1. read only the paths required by the predicate when possible;
2. evaluate predicates using decoded values and the validator adapter;
3. use three-valued results `true | false | unknown` for incomplete input;
4. apply a configured `unknown` policy without discarding state;
5. record the branch-selection reason in the prepared view;
6. prepare the selected subtree;
7. preserve inactive branch data unless the state engine explicitly transitions it.

For `oneOf`, do not treat the first branch as a discriminator. See [[06-runtime-projection#Branch selection|Branch selection]].

## `allOf`, `anyOf`, and `oneOf`

Avoid syntactic merging that changes JSON Schema evaluation semantics.

- `allOf` is conjunction, not necessarily object-map merge.
- `anyOf` permits multiple valid branches.
- `oneOf` requires exactly one valid branch and can be ambiguous during editing.

The semantic IR may derive a combined presentation only when a verified transformation proves it safe for the supported subset. Otherwise preserve composition nodes and project them explicitly.

## Issue mapping

Map validator output in two stages:

1. normalize provider-specific errors to `Formentation.Issue` with instance path, keyword/schema location, code, details, and branch context;
2. associate normalized issues with semantic/runtime nodes.

Special cases:

- `required` may point to the parent object; derive the missing child path from structured keyword data;
- `additionalProperties` may refer to a property not represented by a node;
- composition errors need summarization to avoid duplicating every branch's failure;
- collection errors need stable item association even after reorder;
- object/global errors attach to a group or form summary.

Never parse human error strings to recover paths if the validator provides structured output.

## Default initialization

JSON Schema `default` is annotation data. If the application enables default initialization:

1. walk the semantic definition before user params exist;
2. apply only defaults valid against their local schema;
3. distinguish absent from explicit `null`;
4. avoid creating optional parent objects unless policy permits it;
5. record applied defaults and origins;
6. never reapply a default over an invalid raw submitted value.

Initialization returns new state; rendering does not mutate state.

## Fingerprinting

Canonicalize only stable declarative inputs. Include:

- definition format and compiler versions;
- normalized source documents and UI hints;
- adapter and dialect identity;
- ordered passes and extension versions;
- relevant compiler options;
- capability contract when compatibility is compiled in.

Exclude:

- runtime values and issues;
- process IDs and timestamps;
- anonymous function identities;
- unordered map enumeration.

## Traversal

Start with explicit recursive functions that carry `%TraversalContext{}`. A common walker API should eventually support pre-order, post-order, reference policy, and budgets.

[Iterex](https://github.com/ash-project/iterex) may become useful if traversal must pause/resume, lazily expand very large graphs, or expose an external cursor. It is not required for ordinary form-sized graphs.

## Related notes

- [[05-compiler-pipeline|Compiler pipeline]]
- [[06-runtime-projection|Runtime projection]]
- [[09-diagnostics-provenance-introspection|Diagnostics and provenance]]
- [[11-testing-strategy|Testing strategy]]
- [[phase-4-dynamic-schemas|Phase 4]]
