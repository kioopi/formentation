---
title: Definition and Node
aliases:
  - Definition and Node
tags:
  - formentation
  - techdocs
status: current
---

# Definition and Node

*As of 2026-07-26 (source-neutral validation dispatch; unsupported-node capability query, [[18-decisions#D-028 — Unsupported nodes are a preserve-only capability; blocking is derived at runtime|D-028]]).*

`Formentation.Definition` is the compiler's product and the system's
common language: an immutable, source-independent tree of semantic
nodes plus compile-time diagnostics. It contains no runtime state — no
values, params, or errors — which is what makes it cacheable and safe
to inspect. See [[compile-pipeline|Compile pipeline]] for how one is
produced.

## The Definition container

```elixir
%Formentation.Definition{
  format_version: 2,
  root: %Formentation.Node.Group{...},
  diagnostics: [%Formentation.Diagnostic{...}],
  validation: %Formentation.ValidationPlan{} | nil
}
```

`root` holds the current mixed node tree directly. `Formentation.Info`
keeps compatibility access to that tree through `root/1` and `node/2`,
but its semantic queries use a layout-transparent semantic traversal.
`validation` is an optional `Formentation.ValidationPlan`
— an executable module (implementing `Formentation.Validation`) paired
with the opaque artifact that module owns; `nil` when the source provides
no authoritative instance validation (the map source, currently).

## One struct per node kind (D-015)

Each node kind is its own struct; the struct name is the tag. The
shape of each struct documents its invariants — there is no `kind`
field and no unused-nil fields.

| Struct | Enforced keys | Own fields beyond the shared set |
| --- | --- | --- |
| `Node.Field` | `id`, `name`, `value_type`, `template_path` | `role`, `value_type`, `widget`, `group`, `options`, `default`, `examples`, `constraints`, `label`, `help`, `hidden?`, `read_only?` |
| `Node.Group` | `id`, `template_path`, `nests_data?` | `nests_data?`, `children`, `label`, `help` |
| `Node.Unsupported` | `id`, `name`, `template_path` | — |

Shared by all kinds: `id`, `name`, `template_path`, `required?`,
`origins`. `Formentation.Node` itself is a vocabulary module: the
`t()` union and the `origin()` provenance tag type
([[diagnostics-and-origins|Diagnostics and origins]]).

The node structs also carry temporary, internal `declaration_order`
evidence assigned before presentation grouping. It preserves semantic
declaration order while the mixed tree can still move children beneath
layout groups. It is not a stable representation contract; the split
Definition storage work owns its removal.

## Unsupported nodes are a preserve-only capability

`Node.Unsupported` records a declared construct the compiler cannot
interpret — an array, a `$ref`, an unrecognised map-source `:kind` —
without discarding it: the node keeps its place in the tree, and its
value survives materialization untouched (D-009). The struct carries
nothing beyond the shared fields, because there is nothing more to say
about it at compile time; no struct field and no `format_version` bump
were needed to add runtime blocking, only a query.

`Formentation.Info.unsupported_nodes/1` enumerates every unsupported
node in a definition, in declaration order, descending through
data-nesting groups and looking through presentation-only groups — the
*static*, definition-level capability question ("which declared constructs
can this form never edit?"), answerable before any instance exists and independent of
whether any concrete instance currently has trouble at that node.
Whether a *given* candidate is concretely blocked by one of these nodes
is a separate, runtime-derived question — see
[[form-state-and-transitions#Submission status is derived, not stored|Form state and transitions]].

## Participation flags (D-016)

`hidden?` and `read_only?` sit on `Node.Field` rather than on any
runtime structure, which is the whole point of
[[18-decisions#D-016 — Participation is definition-driven, not transport-driven|D-016]]:
whether a field participates in a submission is a *declared* fact, not
something inferred from what the browser happened to send. A hidden
field decodes normally and merely renders as a hidden input; a
read-only field is excluded from the replace scope entirely — the
submitted value is discarded and the original is kept. Both layers
downstream read these flags rather than re-deriving the intent:
[[form-state-and-transitions|the state layer]] for the decode
operation, [[rendering|the projector]] for the widget and control
attributes.

Only groups have `children` — a field is a leaf by construction, and a
group cannot carry a `value_type`. The splitting rule, recorded in
[[18-decisions#D-015 — One struct per node kind|D-015]]:
a kind gets its own struct when its *shape* differs, not when its
values differ. Scalar fields are one struct; future kinds with new
shapes (`:collection`, `:choice`) will be new structs.

## The two Group flavors (D-006)

`nests_data?` is an enforced key — every construction site declares
which flavor it builds:

- **Data-nesting** (`nests_data?: true`): an object-like container; it
  contributes a segment to instance paths and its `name` is a data key.
- **Presentational** (`nests_data?: false`): a fieldset over flat data;
  transparent to instance paths (`Info.node_at/2` looks through it),
  `name` is `nil`, and its id carries a `#group-id` suffix.

Whether these two flavors deserve separate structs is an open question
([[16-open-questions|open questions]]).

## Related notes

- [[compile-pipeline|Compile pipeline]] — how definitions are produced
- [[source-adapters|Source adapters]] — who constructs these nodes
- [[paths-and-identity|Paths and identity]] — `template_path` and `id`
- [[form-state-and-transitions|Form state and transitions]] — who consumes them at runtime
- [[Techdocs|Back to the Techdocs index]]
