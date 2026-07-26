---
title: Diagnostics, Provenance, and Introspection
tags:
  - formentation
  - diagnostics
  - introspection
status: draft
---

# Diagnostics, provenance, and introspection

Schema-driven software is difficult to debug when it can only say “invalid form configuration.” Formentation should treat explainability as architecture, not polish.

> [!note] Implementation status
> This note describes the target model. [[phase-1-walking-skeleton|Phase 1]] implements provenance as compact origin tags only — enough for diagnostics to point at the right source location. Derivation chains, `Decision` structs with superseded candidates, and `Info.explain/3` arrive with [[phase-2-compiler-diagnostics|Phase 2]], when the compiler pipeline gives them structure and they gain their first consumers. See [[18-decisions#D-003 — Simplified provenance first|D-003]].

## Diagnostic classes

A compiler diagnostic might contain:

```elixir
%Formentation.Diagnostic{
  severity: :error,
  class: :renderer_incompatibility,
  code: :unsupported_widget,
  message: {"renderer does not support widget %{widget}", [widget: :range]},
  origin: %Formentation.Origin{},
  related: [%Formentation.Origin{}],
  details: %{},
  hint: "Choose :number_input or install a range widget extension"
}
```

Suggested classes:

- `:source_loading`;
- `:invalid_declaration`;
- `:unsupported_declaration`;
- `:configuration_conflict`;
- `:renderer_incompatibility`;
- `:extension_failure`;
- `:security_policy`;
- `:internal`.

Severity is separate from class because strictness policy may promote a warning without changing its meaning.

## Submitted-instance issues

An instance issue is expected user-facing data:

```elixir
%Formentation.Issue{
  source: :validation,
  code: :minimum,
  instance_path: ["age"],
  schema_location: %SchemaLocation{pointer: "/properties/age/minimum"},
  message: {"must be at least %{minimum}", [minimum: 18]},
  details: %{minimum: 18},
  branch: nil
}
```

Sources include `:decode`, `:validation`, `:submission`, and possibly a backing engine. Keep message templates translation-ready and do not reduce an issue to a string until presentation.

## Provenance

Origins should form a derivation trail rather than a single label. A decision may be derived from a schema annotation by a named compiler rule, then overridden by UI configuration.

```elixir
%Origin{
  kind: :inference,
  rule: :date_format_role,
  parent: %Origin{
    kind: :json_schema,
    document_uri: "https://example.test/person",
    pointer: "/properties/birth_date/format"
  }
}
```

For an Elixir DSL, provenance can include module, file, line, and property location. [Spark source annotations](https://github.com/ash-project/spark/blob/main/documentation/how_to/use-source-annotations.md) demonstrate the value of retaining this information for errors, tooling, and debugging.

## Explainability

The explanation API should answer targeted questions:

```elixir
Formentation.Info.explain(definition, ["birth_date"], :role)
Formentation.Info.explain(definition, ["birth_date"], :widget)
Formentation.Info.explain(definition, ["address"], :visibility)
```

A result should be structured, with a human formatter:

```elixir
%Formentation.Explanation{
  value: :date_input,
  steps: [
    {:schema_annotation, "format", "date", origin},
    {:rule, :date_format_role, :date},
    {:ui_default, :date, :date_input}
  ]
}
```

This can power development UI, logs, tests, documentation, or an Obsidian-like definition report.

## The Info API

Likely queries include:

```elixir
Formentation.Info.root(definition)
Formentation.Info.fields(definition)
Formentation.Info.node(definition, node_id)
Formentation.Info.node_at(definition, instance_template_path)
Formentation.Info.required?(definition, path)
Formentation.Info.role(definition, path)
Formentation.Info.dependencies(definition, path)
Formentation.Info.origins(definition, path)
Formentation.Info.diagnostics(definition)
Formentation.Info.required_capabilities(definition)
Formentation.Info.support_report(definition, capabilities)
```

The API should accept both a definition and, eventually, a module containing a compiled definition if an optional DSL persists it at compile time. This resembles Ash/Spark `Info` modules without requiring generated functions initially.

## Aggregation and traversal

[Splode](https://hexdocs.pm/splode/Splode.html) is useful prior art for categorizing errors, assigning paths, aggregating leaf errors, normalizing unknown values, serializing errors, and traversing nested errors into a path-indexed result.

Formentation should borrow these properties. A hard Splode dependency is optional: compiler diagnostics may integrate well with it, while high-volume user-input issues are better represented as lightweight values.

Useful functions:

```elixir
Formentation.Issues.at(issues, ["addresses", 0, "postcode"])
Formentation.Issues.prefix(issues, ["addresses", 0])
Formentation.Issues.group_by_path(issues)
Formentation.Diagnostics.format(diagnostics, style: :ansi)
```

## Strictness policy

Different deployments need different failure policies. Define policy separately from diagnostic production:

- `:strict` — unsupported rendering and orphan UI hints are errors;
- `:standard` — unsafe ambiguity is an error, graceful fallback is a warning;
- `:permissive` — preserve unsupported nodes and render a configured fallback where possible.

Applications should be able to promote or suppress specific diagnostic codes. Suppression should not erase diagnostics from introspection unless explicitly requested.

## Privacy and observability

Diagnostics may be logged; submitted values may be sensitive. Compiler diagnostics usually do not need instance data. Runtime issues should avoid embedding complete values by default.

Telemetry events can include diagnostic codes, counts, paths with configurable redaction, compiler duration, cache hits, and projection duration. Never emit raw form values automatically.

## Related notes

- [[03-conceptual-model#Decision|Decisions]]
- [[05-compiler-pipeline#Verify|Compiler verification]]
- [[07-phoenix-integration#Error mapping|Phoenix error mapping]]
- [[10-algorithms#Issue mapping|Issue mapping algorithm]]
- [[11-testing-strategy|Testing strategy]]
