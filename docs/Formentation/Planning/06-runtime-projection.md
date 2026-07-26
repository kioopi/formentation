---
title: Formentation Runtime Projection
tags:
  - formentation
  - runtime
  - liveview
status: draft
---

# Runtime projection

Runtime projection combines a static [[03-conceptual-model#Form definition|definition]] with current form state and context to produce a concrete render plan.

It exists because many form decisions cannot be made when the schema is compiled:

- which conditional branch is active;
- how many collection items exist;
- which errors apply to a particular item;
- whether a field is visible or disabled for the current actor;
- which choice branch currently validates;
- which DOM and Phoenix field names belong to this form instance.

## Inputs and output

```elixir
Formentation.project(definition, form_view,
  renderer: MyApp.FormRenderer,
  context: %{actor: actor, locale: "de"}
)
```

The result is either a render plan with warnings or a structured projection error.

```elixir
%Formentation.RenderPlan{
  definition_fingerprint: "...",
  root: %Formentation.RenderNode{},
  active_branches: %{},
  item_identities: %{},
  diagnostics: []
}
```

## Projection algorithm

1. Establish a runtime cursor containing the semantic node, instance path, form field, current value, ancestors, and context, plus the **root** Phoenix form and the **root** state source handed to the projector (never a nested form built during traversal). The instance path is always absolute — presentational grouping is transparent to it and never alters it ([[18-decisions#D-027 — Projection reads semantic state through a StateView protocol|D-027]]).
2. Evaluate visibility and branch predicates using the current decoded value and validator adapter.
3. Materialize concrete children for groups and collections.
4. Resolve runtime presentation decisions that legitimately depend on value or context.
5. Associate field and global issues with nodes.
6. allocate stable runtime identities for collection items and DOM nodes.
7. Emit a render-node tree containing no source-specific traversal work.

The render plan should contain enough data that the HEEx renderer does not need to revisit JSON Schema.

## Branch selection

Branch selection is one of the hardest behaviours.

For `oneOf`, validation may produce:

- exactly one matching branch;
- no matching branch while the user is midway through editing;
- multiple matching branches, which violates `oneOf` but is still a plausible intermediate form state.

The projector needs a policy, not an assumption. Possible signals, in order of preference, are:

1. an explicit UI discriminator;
2. retained user branch selection;
3. exactly one currently valid branch;
4. a uniquely best partial match, only if the validator exposes reliable evaluation information;
5. a configured fallback branch plus an ambiguity diagnostic.

Never choose permanently based only on branch order without documenting that policy.

## Hidden and inactive data

Visibility is presentation state, not automatically data-deletion policy.

When a conditional branch becomes inactive, the default should be to retain its parameters and values in form state until submission policy decides otherwise. Clearing hidden data during render creates surprising loss and can cause LiveView feedback loops.

Submission may support explicit policies:

- retain and validate according to the original schema;
- prune data not evaluated by the active schema;
- clear fields on an explicit user transition;
- delegate entirely to the backing action or changeset.

These policies belong to the state/submission engine, not the renderer.

## Collections

Schema array indexes and runtime item identity are different concepts. A displayed index can change after reordering, but LiveView and nested form state need stable identity.

Prefer, in order:

1. a backing record primary key;
2. an explicit client-generated persistent item key;
3. a state-engine-generated stable token;
4. positional index only for immutable/simple collections.

The render plan should carry both `instance_path: ["addresses", 2]` and a stable item identity.

## Dependencies and partial reprojection

During compilation, conditional nodes should record which instance paths can affect them. A LiveView integration can then reproject only affected subtrees after a change.

This is an optimization. The initial implementation should reproject the full visible tree and establish correctness first. The plan and dependency indexes should make later partial projection possible without changing semantics.

## Runtime context

Context may include actor, tenant, locale, feature flags, or read-only/disabled policy. Context-dependent functions are an escape hatch and can reduce determinism.

Rules:

- declare which context keys a condition reads;
- never put secrets into render-plan diagnostics;
- do authorization in the underlying application/action as well;
- treat UI hiding as convenience, not security;
- avoid arbitrary callbacks where a serializable predicate would suffice.

## Rendering boundary

The projector chooses a semantic widget key and produces component-ready assigns. The renderer decides how that key becomes HEEx.

For example:

```elixir
%RenderNode{
  kind: :field,
  role: :date,
  widget: :date_input,
  field: %Phoenix.HTML.FormField{},
  label: "Birth date",
  issues: [...],
  options: %{}
}
```

No schema traversal is needed in the component.

## Projection purity

Projection should be referentially transparent for the same definition, state view, context, and capabilities. Adding/removing collection items or changing a selected branch are explicit state transitions outside projection.

## Related notes

- [[05-compiler-pipeline|Compiler pipeline]]
- [[07-phoenix-integration|Phoenix integration]]
- [[10-algorithms#Conditional projection|Conditional projection algorithm]]
- [[phase-1-walking-skeleton|Phase 1]]
- [[phase-4-dynamic-schemas|Phase 4]]

