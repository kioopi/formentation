---
title: Formentation Philosophy
tags:
  - formentation
  - philosophy
status: draft
---

# Project philosophy

Formentation begins with a narrow practical desire—render forms in Phoenix from JSON Schema, recorded concretely in [[00-use-case|the motivating use case]]—but treats that use case as evidence for a more general domain.

The domain is not JSON Schema processing. It is the declaration, compilation, introspection, execution, and presentation of forms.

## Declaration and engine

JSON Schema, a UI-hints document, and an Ash resource are descriptions. They say what values exist, which constraints apply, and sometimes how a value should be presented. Phoenix components, validation libraries, parameter decoders, and LiveView event handlers are engines. They say how to perform work.

The project should preserve this separation:

- declaration sources are converted to a common semantic definition;
- engines query that definition rather than reinterpreting the source independently;
- runtime data remains outside the static definition;
- renderers do not become validators;
- validators do not choose CSS classes or Phoenix components.

This follows the central argument of Zach Daniel's [Incremental Declarative Design](https://www.zachdaniel.dev/p/incremental-declarative-design): extract data rather than merely abstracting repeated code, and separate the “what” from the “how.”

## The definition is a source of leverage

A static definition is more useful than an opaque render function because it can be inspected before rendering. From one definition, Formentation should eventually be able to derive:

- a runtime render plan;
- default UI hints;
- a field and dependency index;
- an explanation of widget choices;
- a renderer-compatibility report;
- documentation;
- accessibility and localization diagnostics;
- cache keys and change reports.

This is the meaning of “declarative, introspectable, derivable” in the [Ash design principles](https://github.com/ash-project/ash/blob/main/documentation/topics/about_ash/design-principles.md). The definition should be useful even in an application that never renders HTML.

## Form state is not form meaning

A `%Phoenix.HTML.Form{}` describes an active interaction: names, identifiers, parameters, values, errors, and nested forms. A `FormDefinition` describes meaning: semantic fields, groups, choices, collections, constraints, presentation roles, dependencies, and provenance.

Neither can replace the other.

Formentation should combine them late. This permits a JSON-backed form state implementation without requiring every user to adopt it. It also leaves room for `Ecto.Changeset`, `AshPhoenix.Form`, and other `Phoenix.HTML.FormData` implementations.

See [[03-conceptual-model#The static and dynamic models|the static and dynamic models]] and [[07-phoenix-integration|Phoenix integration]].

## Useful defaults without hidden magic

An automatically generated form must make choices. A string might become a text field; an enum might become a select; a long string might become a textarea. These are conventions, but they need not be mysterious conventions.

Every automatic choice should be:

- governed by a named, documented rule;
- represented as data;
- introspectable through an explanation API;
- overridable through explicit configuration;
- checked against renderer capabilities.

This reconciles zero-configuration usability with Ash's “configuration over convention” principle. See [[09-diagnostics-provenance-introspection#Explainability|Explainability]].

## Explicit incompleteness

JSON Schema is a validation language, not a form language. Some schemas have no single obvious interactive representation. Some constructs are expensive, ambiguous, recursive, or renderer-dependent.

Formentation should never claim that “valid JSON Schema” implies “automatically renderable form.” Instead, it should:

- define levels of support;
- retain unsupported nodes in the definition where useful;
- emit structured diagnostics;
- provide extension points;
- allow a caller to choose strict or permissive compilation.

An honest support report is more valuable than silently degrading every unknown construct to a text input.

## Incremental design

The architecture in these notes is a direction, not permission to implement a framework all at once.

The first implementation should use ordinary structs, maps, protocols, behaviours, and pure functions. Compiler passes should be extracted when there are real passes. Extension descriptors should be formalized when a second extension proves the boundary. A Spark-powered Elixir DSL should be considered only when users need compile-time configuration and its tooling benefits.

See [[13-roadmap|Roadmap]] and [[phase-1-walking-skeleton|Phase 1]].

## A humane developer experience

Schema-driven systems often fail by moving complexity from code into configuration without improving understanding. Formentation should aim for the opposite:

- errors identify both the instance path and declaration origin;
- an `Info` API answers common questions without internal pattern matching;
- an `explain` API shows why a decision was made;
- renderer incompatibility is caught before template execution;
- source adapters preserve enough context to help users repair the source.

The project is successful when simple forms are simple, complex forms are explainable, and unsupported forms fail informatively.

## Related notes

- [[00-use-case|Motivating use case]]
- [[02-design-principles|Design principles]]
- [[03-conceptual-model|Conceptual model]]
- [[09-diagnostics-provenance-introspection|Diagnostics, provenance, and introspection]]
- [[12-ecosystem-and-dependencies|Ecosystem and dependencies]]
- [[Formentation|Back to the entry point]]

