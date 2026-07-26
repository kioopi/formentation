---
title: Formentation Extension Model
tags:
  - formentation
  - extensions
  - architecture
status: draft
---

# Extension model

The extension model should make Formentation capable of application-specific behaviour without allowing every extension to mutate everything.

This follows Ash's “Anything, not Everything” principle and takes structural inspiration from [Spark](https://github.com/ash-project/spark), while beginning with ordinary Elixir data and behaviours.

## Extension categories

### Declaration-source extensions

These translate an external vocabulary into compiler input.

Examples:

- JSON Schema;
- Ash resources and actions;
- an application-specific form manifest.

They own source parsing and source locations, not rendering.

### Schema-vocabulary extensions

These recognize custom JSON Schema vocabularies or annotations. Their validation semantics must integrate with the selected validator or be clearly annotation-only.

Example: an application keyword `x-money-currency` may add semantic metadata, but a Phoenix widget must not decide whether the JSON instance is valid.

### Semantic compiler extensions

These add roles, codecs, compiler passes, verifiers, or custom node kinds.

Example: map `format: "money"` plus currency metadata to role `:money` and codec `MyApp.MoneyCodec`.

### Presentation extensions

These add abstract widgets or layout vocabulary to the definition, or provide
renderer/UI support for already-normalized semantics.

They may reject unsupported semantic configurations, but they do not reinterpret source validation.

The presentation-side extension categories are distinct:

- a **presentation extension** contributes source-neutral layout vocabulary or
  abstract widget intent;
- a **renderer extension** contributes support for an output environment;
- a **UI integration** maps prepared views to a component library;
- a **theme** configures the visual appearance of one UI.

Presentation declarations must not place arbitrary component modules in a
definition. UI integrations must not traverse source declarations or recreate
form semantics. See [[20-renderer-ui-model|Renderer and UI model]].

## Extension descriptor

Start with a plain struct:

```elixir
%Formentation.Extension{
  name: :money,
  version: 1,
  passes: [MyMoney.DeriveRole],
  verifiers: [MyMoney.VerifyCurrency],
  codecs: %{money: MyMoney.Codec},
  node_kinds: [],
  metadata: %{}
}
```

The descriptor makes extension contributions introspectable. It also provides inputs to definition fingerprints and compatibility reports.

## Renderer and UI capabilities

A renderer and UI should publish composed capability values rather than relying
on `function_exported?` checks scattered throughout compilation or
preparation:

```elixir
%Formentation.Phoenix.UI{
  id: :plain,
  contract_version: 1,
  widgets: MapSet.new([:text_input, :number_input, :date_input, :checkbox]),
  containers: MapSet.new([:root, :object, :group, :collection]),
  features: MapSet.new([:errors, :help, :add_remove]),
  metadata: %{}
}
```

This shape is illustrative. Phase 3 must determine which capabilities belong
to the renderer, UI, individual components, or a composed descriptor.

Compatibility checks may occur:

- against static requirements when a target UI is known;
- during preparation for runtime-visible branches, collection items, and local
  overrides.

Reusable definitions must not require a target UI at compilation time. Missing
capabilities must produce a structured failure or an explicit, inspectable
fallback; they must never silently remove a field.

Resource budgets are separate from capability claims. Compiler and renderer
safety policy must limit such dimensions as semantic/presentation nesting,
total nodes, options, diagnostics, visible occurrences, collection items,
decoded bytes, and preparation work. A UI may advertise a narrower supported
range, but it cannot weaken those engine-owned limits.

Themes should be data-first where practical, but are deliberately narrower than
the UI descriptor:

```elixir
%MyAppWeb.FormUI.Theme{
  name: :compact,
  color_mode: :dark,
  density: :compact,
  tokens: %{control_size: :sm}
}
```

Actual Phoenix function components may require module/function references that
are not serializable. Those references belong to render configuration or the UI
descriptor, not the semantic definition. The descriptor should still identify
them for inspection and contract-version checks.

## Codecs

A codec boundary could provide:

```elixir
@callback decode(raw :: term(), context :: Codec.Context.t()) ::
  {:ok, term()} | {:error, [Formentation.Issue.t()]}

@callback encode(value :: term(), context :: Codec.Context.t()) :: term()
```

Codec selection belongs in the definition. Execution belongs in the state engine. Codecs must preserve raw input on failure and should avoid locale-dependent ambiguity unless locale is explicit.

## Custom predicates

Prefer an explicit condition AST for common rules. Permit custom predicate modules as an escape hatch:

```elixir
@callback evaluate(term(), RuntimeContext.t()) :: boolean() | :unknown
@callback dependencies(term()) :: [Formentation.InstancePath.t()]
```

Requiring dependencies makes future partial reprojection possible.

## Ordering and conflicts

Compiler extensions must declare pass ordering. Duplicate names, cycles, and conflicting exclusive capabilities are configuration errors.

When two extensions make decisions about the same key, resolution must follow documented precedence. If there is no declared precedence, emit a conflict diagnostic instead of relying on registration order.

## Extension safety

Extensions execute application code and are trusted in the Elixir process. Nevertheless, the core should protect its own invariants:

- validate pass output;
- namespace extension metadata;
- prevent duplicate node IDs;
- require structured diagnostics;
- include extension identities in fingerprints;
- offer conformance tests.

## Conformance suite

Provide reusable tests for:

- deterministic capabilities;
- codec round-trips where meaningful;
- raw-input preservation on decode error;
- accessible widget markup;
- correct field/error association;
- semantic invariance across UI selection;
- whole-form and subtree prepared-view agreement;
- rendered-control to params to decode round trips;
- blank-option, unchecked, omitted, repeated, and compound transport shapes;
- pass determinism and ordering;
- custom node serialization or inspection policy;
- UI behaviour for unsupported nodes and widget requirements;
- explicit capability fallbacks;
- browser-real behaviour for focus, hooks, and transport conventions.

The second independent UI and first application extension should be treated as
architecture tests. If they require source traversal, internal pattern
matching, or compiler/projector forks, the extension boundaries are not ready.
A second set of CSS classes on the reference components is not an independent
UI. The second UI should compile as a separate Mix project and CI should reject
references to source adapters, `Formentation.Node.*`, private definition
representation, and private preparation structs.

## Optional Spark DSL

[Spark](https://github.com/ash-project/spark) can later provide an excellent compile-time authoring experience: sections/entities, extension composition, transformers, verifiers, generated `Info` functions, documentation, autocomplete, and source annotations.

It should be considered when applications want declarations such as:

```elixir
defmodule MyApp.Forms do
  use Formentation.Dsl

  formats do
    format "money" do
      role :money
      codec MyApp.MoneyCodec
      widget :money_input
    end
  end
end
```

The DSL must compile into the same descriptors available through ordinary Elixir data. Core runtime usage should not require Spark.

## Related notes

- [[02-design-principles|Design principles]]
- [[05-compiler-pipeline|Compiler pipeline]]
- [[09-diagnostics-provenance-introspection|Diagnostics and introspection]]
- [[20-renderer-ui-model|Renderer and UI model]]
- [[12-ecosystem-and-dependencies#Spark|Spark]]
- [[phase-3-extensibility|Phase 3]]
