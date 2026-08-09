---
title: Definition and Node
aliases:
  - Definition and Node
tags:
  - formentation
  - techdocs
status: current
---

# Definition

*As of 2026-08-08 (native semantic/presentation storage for the built-in
sources and native-backed semantic/presentation query seams, [[18-decisions#D-033 — Phase 1 layout covers each supported occurrence exactly once|D-033]]; module paths refreshed for the lib-tree restructure, [[18-decisions#D-047 — The lib tree is restructured to state the north-star architecture|D-047]]).*

`Formentation.Definition` is the compiler's product and the system's
common language: an immutable, source-independent tree of semantic
nodes plus compile-time diagnostics. It contains no runtime state — no
values, params, or errors — which is what makes it cacheable and safe
to inspect. See [[compile-pipeline|Compile pipeline]] for how one is
produced.

## The Definition container

```elixir
%Formentation.Definition{
  format_version: 3,
  semantic: %Formentation.Definition.Semantic.Object{...},
  semantic_index: %Formentation.Definition.Semantic.Index{...},
  presentation: %Formentation.Definition.Presentation.Object{...},
  validation: %Formentation.Definition.ValidationPlan{} | nil,
  diagnostics: [%Formentation.Diagnostic{...}]
}
```

`semantic` is the declaration tree. It owns occurrence identity, names,
template paths, value type, role, requiredness, constraints, options,
defaults, examples, read-only participation, unsupported declarations, and
semantic origins. Semantic nodes do not store labels, help text, widgets,
hidden intent, group membership, or instance paths.

`presentation` is the layout tree. It owns layout identity, ordered children,
presentation groups, label/help/widget/hidden facts, and presentation origins.
Presentation object and field nodes reference semantic occurrences by
`semantic_id`; they do not duplicate semantic field facts. The finalizer
requires every supported semantic occurrence to be referenced exactly once, so
the current Phase 1 layout is a total, non-duplicating projection of the
supported semantic tree.

`semantic_index` is the finalized lookup store keyed by semantic id and
template path. It is derived during finalization and lets runtime consumers
resolve presentation references without re-walking the semantic tree for every
field.

`validation` is an optional `Formentation.Definition.ValidationPlan`
— an executable module (implementing `Formentation.Definition.Validation`) paired
with the opaque artifact that module owns; `nil` when the source provides
no authoritative instance validation (the map source, currently).

## Native semantic structs

| Struct | Enforced keys | Own fields |
| --- | --- | --- |
| `Semantic.Object` | `id`, `template_path` | `name`, `required?`, `children`, `origins` |
| `Semantic.Field` | `id`, `name`, `template_path`, `value_type` | `role`, `required?`, `read_only?`, `constraints`, `options`, `default`, `examples`, `origins` |
| `Semantic.Unsupported` | `id`, `name`, `template_path` | `required?`, `origins` |

`Formentation.Definition.Semantic` now reads `Definition.semantic` when it exists. It
derives current `InstancePath`s from the tree position and node names for
query results, rather than storing an instance path on each semantic node.

## Native presentation structs

| Struct | Enforced keys | Own fields |
| --- | --- | --- |
| `Presentation.Object` | `id`, `semantic_id` | `label`, `help`, `children`, `origins` |
| `Presentation.Field` | `id`, `semantic_id` | `label`, `help`, `widget`, `hidden?`, `origins` |
| `Presentation.Group` | `id` | `label`, `help`, `children`, `origins` |

`Formentation.Info.presentation_root/1` and
`Formentation.Info.presentation_at/2` now read `Definition.presentation` when
it exists and resolve semantic IDs through `semantic_index`. Their public
descriptor contract is unchanged: object and field descriptors expose computed
semantic `InstancePath`s, and presentation groups expose layout identity only.

## Presentation traversal descriptors

`Formentation.Info.presentation_root/1` and
`Formentation.Info.presentation_at/2` are the presentation-query seam.
They read the native presentation tree and semantic index, then return typed
descriptors under `Formentation.Info.Layout`:

- `Object` — root or nested semantic-object layout boundary, carrying a
  normalized `InstancePath`.
- `Field` — scalar field reference, carrying a normalized `InstancePath`
  plus presentation-owned label, help, widget hint, hidden intent, and
  origins.
- `Group` — presentation-only grouping, carrying layout identity and
  children but no semantic path.

Presentation groups never add instance-path segments. A nested object
`details` contributes `["details"]`; a presentation group such as
`technical` inside it does not, so a field remains
`["details", "width"]`, never `["details", "technical", "width"]`.
`presentation_at/2` accepts only semantic root/object/field paths and
distinguishes `:not_found` from `:unsupported`.

## Unsupported nodes are a preserve-only capability

`Semantic.Unsupported` records a declared construct the compiler cannot
interpret — an array, a `$ref`, an unrecognised map-source `:kind` —
without discarding it: the node keeps its place in the tree, and its
value survives materialization untouched (D-009). The struct carries
nothing beyond the shared fields, because there is nothing more to say
about it at compile time; no struct field and no `format_version` bump
were needed to add runtime blocking, only a query.

`Formentation.Info.unsupported_nodes/1` enumerates every unsupported
node in a definition, in declaration order, descending through
semantic objects — the
*static*, definition-level capability question ("which declared constructs
can this form never edit?"), answerable before any instance exists and independent of
whether any concrete instance currently has trouble at that node.
Whether a *given* candidate is concretely blocked by one of these nodes
is a separate, runtime-derived question — see
[[form-state-and-transitions#Submission status is derived, not stored|Form state and transitions]].

## Participation flags (D-016)

`read_only?` sits on `Semantic.Field`, while `hidden?` sits on
`Presentation.Field`. Neither belongs to runtime form state, which is the
point of
[[18-decisions#D-016 — Participation is definition-driven, not transport-driven|D-016]]:
whether a field participates in a submission is a *declared* fact, not
something inferred from what the browser happened to send. A hidden
field decodes normally and merely renders as a hidden input; a
read-only field is excluded from the replace scope entirely — the
submitted value is discarded and the original is kept. Both layers
downstream read these declared facts rather than re-deriving the intent:
[[form-state-and-transitions|the state layer]] for the decode
operation, [[rendering|render preparation]] for the widget and control
attributes.

Only semantic objects and presentation containers have `children`. A semantic
field is a leaf by construction, and presentation group membership is layout
containment, never a field attribute.

## Related notes

- [[compile-pipeline|Compile pipeline]] — how definitions are produced
- [[source-adapters|Source adapters]] — who constructs these nodes
- [[paths-and-identity|Paths and identity]] — `template_path` and `id`
- [[form-state-and-transitions|Form state and transitions]] — who consumes them at runtime
- [[Techdocs|Back to the Techdocs index]]
