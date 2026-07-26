---
title: Formentation Conceptual Model
tags:
  - formentation
  - architecture
  - model
status: draft
---

# Conceptual model

This note defines the project's main concepts. Names are provisional, but the distinctions should remain even if the modules are renamed.

## Declaration source

A declaration source supplies facts from which a form can be described.

Initial sources (two from the start, so source-independence is tested rather than assumed — [[18-decisions#D-004 — Two declaration sources from the start|D-004]]):

- a JSON Schema document;
- a plain Elixir data structure (`Formentation.Source.Map`, working name);
- a UI-hints or `uiSchema`-style document accompanying either.

Possible later sources:

- Ash resource and action metadata;
- a builder API;
- a Spark-powered compile-time DSL;
- application-specific metadata.

A source adapter translates source-specific vocabulary into compiler input while retaining source locations.

## Form definition

`Formentation.Definition` is a static, source-independent representation of form meaning. It contains a semantic node graph, indexes, dependency information, decisions, provenance, required capabilities, and compilation diagnostics.

It should be safe to cache and inspect. It must not contain current parameters, field errors, CSRF tokens, LiveView state, or generated DOM identifiers.

[[031-form-definition|Form definition]] examines this structure in depth: its layers, what it excludes, and what the abstraction enables.

## Semantic node

A node describes a meaningful part of the form. The exact Elixir representation may use a tagged struct or distinct structs.

Candidate node kinds:

| Kind | Meaning |
| --- | --- |
| `:field` | An editable or display-only scalar value. A scalar `enum`/`const` is a field with a fixed option set, not a choice ([[18-decisions#D-005 — Scalar enums are fields, not choice nodes|D-005]]). |
| `:group` | A presentation grouping or an object-like container — one kind, distinguished by a `nests_data?` flag ([[18-decisions|D-006]]). |
| `:collection` | A homogeneous or tuple-like sequence. |
| `:choice` | Structural alternatives such as `oneOf` or union selection between different subtrees. |
| `:conditional` | Content activated by a predicate. |
| `:reference` | A named or recursive reference boundary retained for introspection. |
| `:content` | Help text, headings, or non-input presentation content. |
| `:custom` | An extension-owned semantic node. |
| `:unsupported` | A preserved construct that cannot currently be rendered faithfully. |

A field should have a semantic role such as `:text`, `:integer`, `:date`, `:email`, `:boolean`, or `:money`. A role is not an HTML tag. Renderers map roles and explicit widget requests to components.

## Decision

A decision is a selected value plus the reason it won:

```elixir
%Formentation.Decision{
  key: :widget,
  value: :textarea,
  source: %Formentation.Origin{
    kind: :ui_schema,
    pointer: "/bio/ui:widget"
  },
  superseded: [
    {:text_input, %Formentation.Origin{kind: :inference, rule: :string_default}}
  ]
}
```

Not every scalar option requires this full representation in memory, but externally meaningful choices should remain explainable.

> [!note] Implementation status
> This is the target model. [[phase-1-walking-skeleton|Phase 1]] records only the winning value plus a compact origin tag such as `{:ui_hints, "/bio/ui:widget"}`; superseded candidates and derivation chains arrive with [[phase-2-compiler-diagnostics|Phase 2]]. See [[18-decisions#D-003 — Simplified provenance first|D-003]].

## Origin

An origin identifies where a declaration or derived decision came from. Depending on the source, it may include:

- source kind;
- document URI;
- JSON Pointer;
- Elixir module, file, and line;
- extension and rule names;
- parent origin for derived facts.

See [[09-diagnostics-provenance-introspection#Provenance|Provenance]].

## Diagnostic and issue

A diagnostic concerns declaration processing or system capability: invalid configuration, unsupported schema, contradictory UI hints, or unavailable widgets.

An issue concerns a particular submitted instance: a required value is missing, a number is too small, or a branch does not validate.

They may share path and message conventions but should remain distinct types. User input errors are expected data; compiler failures may be exceptional at application startup.

## The static and dynamic models

`Formentation.Definition` is static. `Formentation.Form` owns one dynamic
interaction lifecycle. Renderer preparation derives a dynamic prepared view
for concrete visible occurrences; the current Phase 1 `RenderPlan` is an
internal implementation of that responsibility, not an ordinary public noun.

The prepared view is produced from:

- the definition;
- a current projected form/root or advanced state view;
- runtime context;
- the selected UI descriptor/capabilities and overrides.

It contains active branches, visible occurrences, concrete collection items,
resolved widget/component choices, transport facts, localized feedback, and
runtime identifiers. See [[06-runtime-projection|Runtime projection]] and
[[20-renderer-ui-model|Renderer and UI model]].

## Form state

Form state holds current data, raw parameters, decoded values, issues, action, submission state, and nested collection operations.

Formentation may provide a JSON-backed state implementation, but renderers must not assume it. Phoenix already provides the `%Phoenix.HTML.Form{}` boundary, and Ash and Ecto have their own state semantics.

See [[07-phoenix-integration|Phoenix integration]].

## Codec

A codec converts between browser parameters and domain values. It is separate from schema validation.

Examples:

- empty string to `nil` according to configured policy;
- ISO date string to `Date`;
- checkbox parameters to booleans;
- repeated fields to lists;
- money input to a domain money type.

Codecs need path-aware errors and should be composable for nested and collection values.

## Renderer, UI, theme, and widget

- A **renderer** integrates an output environment and prepares concrete
  component-ready occurrences, initially Phoenix/HEEx.
- A **UI integration** maps a prepared view to one component library or
  application design system.
- A **theme** supplies visual configuration inside one UI.
- A **widget** is an abstract input interaction implemented by a concrete UI
  component.

Presentation choices form three distinct levels, and every note should be explicit about which level it means:

1. **Role** — semantic meaning, chosen during compilation: `:text`, `:date`, `:money`.
2. **Widget key** — abstract interaction kind, resolved from role/type,
   presentation intent, UI defaults/capabilities, and overrides:
   `:textarea`, `:date_input`.
3. **Component** — the concrete function one UI binds to a resolved widget at
   render time.

Roles and widget keys may appear in a definition; concrete components never do.
Keeping these concepts separate allows Tailwind- and Bootstrap-oriented UIs to
share widget semantics, or a custom widget to participate in several UIs. See
[[20-renderer-ui-model#Widget resolution|the canonical widget model]].

## Info API

`Formentation.Info` is the stable query surface over definitions. It is used by renderers, tooling, tests, and applications.

See [[09-diagnostics-provenance-introspection#The Info API|The Info API]].

## Related notes

- [[031-form-definition|Form definition]]
- [[17-end-to-end-example|End-to-end example]]
- [[04-architecture|Architecture]]
- [[05-compiler-pipeline|Compiler pipeline]]
- [[06-runtime-projection|Runtime projection]]
- [[20-renderer-ui-model|Renderer and UI model]]
- [[15-glossary|Glossary]]
- [[Formentation|Back to the entry point]]
