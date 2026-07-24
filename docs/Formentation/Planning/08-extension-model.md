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

These add widgets, containers, themes, or renderer support for semantic nodes.

They may reject unsupported semantic configurations, but they do not reinterpret source validation.

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

## Renderer and theme capabilities

A renderer should publish a capability value rather than relying on `function_exported?` checks scattered throughout compilation:

```elixir
%Formentation.Renderer.Capabilities{
  node_kinds: MapSet.new([:field, :group, :collection, :choice]),
  roles: MapSet.new([:text, :integer, :date, :boolean]),
  widgets: MapSet.new([:text_input, :number_input, :date_input, :checkbox]),
  features: MapSet.new([:errors, :help, :add_remove]),
  constraints: %{max_nesting: 20}
}
```

Compatibility checks can occur during compilation when a target renderer is known, or immediately before projection otherwise.

Themes should be data-first where practical:

```elixir
%Formentation.Theme{
  name: :plain,
  role_defaults: %{date: :date_input, text: :text_input},
  components: %{date_input: &Components.date_input/1},
  classes: %{field: "...", error: "..."}
}
```

Actual Phoenix function components may require modules/functions that are not conveniently serializable; the introspectable descriptor should still identify them.

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
- pass determinism and ordering;
- custom node serialization or inspection policy;
- renderer behaviour for unsupported nodes.

The second independent theme and first application extension should be treated as architecture tests. If they require internal pattern matching or compiler forks, the extension boundaries are not ready.

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
- [[12-ecosystem-and-dependencies#Spark|Spark]]
- [[phase-3-extensibility|Phase 3]]

