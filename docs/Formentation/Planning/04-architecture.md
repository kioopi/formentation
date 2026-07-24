---
title: Formentation Architecture
tags:
  - formentation
  - architecture
status: draft
---

# Architecture

Formentation is best understood as a compiler plus runtime projection system, with adapters on both sides.

```mermaid
flowchart TD
    A["Declaration sources"] --> B["Source adapters"]
    B --> C["Compiler and verifiers"]
    C --> D["FormDefinition"]
    D --> E["Runtime projector"]
    F["Form state"] --> E
    E --> G["RenderPlan"]
    G --> H["Renderer and theme"]
```

## Architectural layers

### Source adapters

Source adapters know the vocabulary and location system of their source. The JSON Schema adapter understands dialects, references, schema locations, annotations, and validation keywords. The plain Elixir data source lives in core with no dependencies and doubles as the reference adapter and cheapest fixture format ([[18-decisions#D-004 — Two declaration sources from the start|D-004]]). A future Ash adapter would use Ash introspection APIs.

Source adapters should not render components or implement LiveView events.

Candidate behaviour:

```elixir
@callback load(source :: term(), options :: keyword()) ::
  {:ok, Formentation.Compiler.Input.t()}
  | {:error, [Formentation.Diagnostic.t()]}
```

Remote I/O belongs behind an explicit resolver/loader abstraction so that compilation can otherwise remain deterministic.

### Compiler

The compiler normalizes declarations into semantic nodes, applies named transformations, resolves configuration precedence, and builds indexes. It returns a versioned definition and warnings or structured errors.

```elixir
Formentation.compile(source,
  adapter: Formentation.JSONSchema,
  ui: ui_schema,
  extensions: [...],
  renderer: MyApp.FormRenderer
)
```

The `renderer:` option is optional and exists only for early capability verification. It must add diagnostics, never change the compiled semantics — otherwise the same schema would compile to different definitions per renderer, and the definition would stop being presentation-independent. Whether themes may influence compilation at all is [[16-open-questions#Rendering|an open question]].

See [[05-compiler-pipeline|Compiler pipeline]].

### Verifiers

Verifiers inspect the compiled definition without mutating it. They check cross-node invariants, source/UI compatibility, renderer support, unique identities, and extension requirements.

This separation is inspired by [Spark transformers](https://hexdocs.pm/spark/Spark.Dsl.Transformer.html) and [Spark verifiers](https://hexdocs.pm/spark/Spark.Dsl.Verifier.html).

### Definition and Info API

The definition is the project's durable in-memory product, examined in depth in [[031-form-definition|Form definition]]. `Formentation.Info` provides stable queries while allowing internal representation to evolve.

Definitions should include a format version and a deterministic fingerprint. Persistence or serialization can be considered later; do not promise safe long-term serialization before module references and extension metadata are understood.

### Runtime state view

The projector requires values, parameters, errors, and nested-form access. The first integration can adapt a `%Phoenix.HTML.Form{}` and a JSON-backed `Formentation.Form`.

Avoid requiring a broad state-engine behaviour before both JSON-backed and Ash-backed use cases have been exercised. Start with the smallest read interface the projector actually needs.

### Projector

The projector evaluates runtime conditions, selects active alternatives, materializes collection items, maps instance paths to form fields, resolves runtime widget choices, and produces a render plan.

The projector does not emit HEEx and does not mutate submitted data merely because a field is hidden. See [[06-runtime-projection|Runtime projection]].

### Renderer and theme

The Phoenix renderer consumes a render plan and component registry. A theme supplies presentation defaults, component mappings, classes, and layout conventions. Renderers and themes advertise capabilities that can be checked during compilation or projection.

See [[08-extension-model#Renderer and theme capabilities|Renderer and theme capabilities]].

## Package boundaries

The conceptual packages are:

| Package or namespace | Responsibility |
| --- | --- |
| `formentation` | Definition, compiler contracts, introspection, diagnostics, projection concepts. |
| `formentation_json_schema` | JSON Schema source adapter and validator integration. |
| `formentation_phoenix` | `FormData` support, Phoenix components, themes, LiveView helpers. |
| `formentation_ash` | Ash declaration and `AshPhoenix.Form` integration. |

These should begin as namespaces in one repository unless independent release cycles or dependency graphs become painful. Prematurely publishing four Hex packages would increase maintenance without proving the boundaries.

The core must not depend on Phoenix. The JSON Schema adapter must not depend on Ash. The Phoenix package may depend on core and optionally expose integrations without requiring Ash.

## Compile-time versus runtime

Schemas can be known at compile time, application startup, or request time. The architecture should support all three without forcing one.

- **Compile time:** fast runtime and early diagnostics, but remote sources and dynamic configuration are awkward.
- **Startup:** good for application-owned schemas and cache warming.
- **Request time:** necessary for tenant/user-provided schemas, but requires budgets, caching, and safe failure handling.

The compiler API should therefore be an ordinary runtime function. An optional macro or Spark DSL may invoke it at compile time later.

## Cache boundaries

Cache the static definition using a fingerprint of:

- canonicalized declaration inputs;
- source adapter and supported dialect;
- compiler version;
- extension identities and relevant options;
- selected capability contract, if renderer-specific verification is included.

Do not cache render plans globally: they contain runtime values, active branches, and concrete collection identity.

## Failure boundaries

The system should distinguish:

1. source loading and reference resolution failures;
2. invalid declaration failures;
3. unsupported but valid declaration diagnostics;
4. runtime decoding failures;
5. submitted-instance validation issues;
6. renderer capability failures;
7. unexpected internal failures.

See [[09-diagnostics-provenance-introspection|Diagnostics, provenance, and introspection]].

## Architectural invariants

- Rendering never changes validation meaning.
- Validation never chooses visual components.
- Projection never destroys hidden data by default.
- Every rendered input maps to a semantic node and runtime field path.
- Every externally visible compiler decision is explainable.
- Every extension participates through declared contracts and capabilities.
- Source-specific paths do not leak as the only path representation.

## Related notes

- [[03-conceptual-model|Conceptual model]]
- [[031-form-definition|Form definition]]
- [[05-compiler-pipeline|Compiler pipeline]]
- [[06-runtime-projection|Runtime projection]]
- [[07-phoenix-integration|Phoenix integration]]
- [[10-algorithms|Algorithms and invariants]]
- [[Formentation|Back to the entry point]]

