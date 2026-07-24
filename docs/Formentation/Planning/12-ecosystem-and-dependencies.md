---
title: Ecosystem, Inspirations, and Dependencies
tags:
  - formentation
  - ecosystem
  - dependencies
status: draft
---

# Ecosystem, inspirations, and dependencies

This note records relevant projects and the current recommendation about depending on them. “Borrow the design” does not imply “add the package.” Versions and maintenance status should be rechecked when implementation begins.

## Phoenix

- [Phoenix.HTML.Form](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html) — runtime representation consumed by components and helpers.
- [Phoenix.HTML.FormData](https://hexdocs.pm/phoenix_html/Phoenix.HTML.FormData.html) — protocol that permits custom backing form state.
- [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) — modern form components and `%Phoenix.HTML.FormField{}` usage.
- [phoenix_ecto FormData implementation](https://github.com/phoenixframework/phoenix_ecto/blob/master/lib/phoenix_ecto/html.ex) — reference for changeset integration.

Recommendation: `formentation_phoenix` necessarily depends on the appropriate Phoenix packages; core should not.

## JSON Schema

- [JSON Schema specification](https://json-schema.org/specification) — authoritative semantics and dialect information.
- [JSON Schema output schemas](https://json-schema.org/draft/2020-12/json-schema-core#name-output-schemas) — relevant to structured validator output.
- [ex_json_schema](https://github.com/jonasschmidt/ex_json_schema) — established Elixir implementation and original candidate.
- [JSV](https://github.com/lud/jsv) — an Elixir JSON Schema validator worth evaluating for modern dialect support and structured output. (Independent project; not part of the Ash ecosystem.)

Recommendation: put validators behind a small adapter. Select one supported adapter for the first release rather than implementing lowest-common-denominator behaviour for several unproven integrations. **Decided 2026-07-21:** JSV is that validator — ex_json_schema stops at draft 7 and cannot process the pinned 2020-12 dialect. See [[18-decisions#D-008 — JSV is the JSON Schema validator|D-008]].

Evaluation criteria:

- dialect and vocabulary support;
- structured instance/schema locations;
- branch/evaluation output;
- local and remote reference resolution;
- recursive references;
- compilation/caching API;
- performance and maintenance;
- ability to register custom formats/vocabularies.

## React JSON Schema Form

- [react-jsonschema-form](https://rjsf-team.github.io/react-jsonschema-form/) — major reference implementation.
- [uiSchema reference](https://rjsf-team.github.io/react-jsonschema-form/docs/api-reference/uiSchema) — source for presentation hints and widgets.
- [schema-processing description](https://deepwiki.com/rjsf-team/react-jsonschema-form/6-schema-processing) — overview of recursive schema/UI processing.

Borrow:

- a separate UI declaration;
- automatic defaults;
- widget and template registries;
- support for custom fields and widgets;
- recursive schema processing experience.

Improve for Formentation:

- compile a static semantic definition rather than mixing all processing into component recursion;
- preserve provenance and explanations;
- separate state engine from renderer;
- verify renderer capabilities before rendering.

## Ash

- [Ash](https://github.com/ash-project/ash) — declarative, extensible application framework.
- [Ash design principles](https://github.com/ash-project/ash/blob/main/documentation/topics/about_ash/design-principles.md) — “Anything, not Everything,” declarative/introspectable/derivable, configuration, and pragmatism.
- [Ash extension guide](https://hexdocs.pm/ash/writing-extensions.html) — extensions, transformers, configuration, and `Info` functions.
- [AshPhoenix.Form](https://hexdocs.pm/ash_phoenix/AshPhoenix.Form.html) — sophisticated Phoenix form state for Ash actions.
- [AshPhoenix.Form.Auto](https://hexdocs.pm/ash_phoenix/AshPhoenix.Form.Auto.html) — automatic nested form derivation from resource/action metadata.

Recommendation: no Ash dependency in core. Add a later optional integration. Do not replace `AshPhoenix.Form` state machinery; render it using compatible definitions and Phoenix form boundaries.

## Spark

- [Spark](https://github.com/ash-project/spark) — toolkit for declarative, extensible Elixir DSLs.
- [Spark transformers](https://hexdocs.pm/spark/Spark.Dsl.Transformer.html) — ordered compile-time state transformation.
- [Spark verifiers](https://hexdocs.pm/spark/Spark.Dsl.Verifier.html) — read-only post-compilation verification and structured tests.
- [Spark source annotations](https://github.com/ash-project/spark/blob/main/documentation/how_to/use-source-annotations.md) — source provenance for diagnostics and tooling.

Borrow now:

- separate transformers and verifiers;
- stable introspection APIs;
- explicit extension descriptors;
- pass ordering;
- source provenance.

Recommendation: do not depend on Spark initially. Consider an optional Spark authoring DSL after ordinary data APIs and extension boundaries are proven.

## Splode

- [Splode](https://github.com/ash-project/splode) and [Splode documentation](https://hexdocs.pm/splode/Splode.html) — aggregatable, categorized, path-aware errors.

Borrow:

- leaf errors and aggregate classes;
- path prefixing and traversal;
- unknown-error normalization;
- serialization;
- merging errors across subsystems.

Recommendation: consider it for compiler/system diagnostics or provide an adapter. Keep expected submitted-instance issues as lightweight form data.

## Crux

- [Crux](https://github.com/ash-project/crux) — Boolean expression manipulation, constraints, SAT solving, and decision trees.

Potential later uses:

- a restricted declarative UI-condition language;
- dependency and contradiction analysis;
- simplifying conditions;
- exactly-one constraints in a deliberately limited domain.

Recommendation: no initial dependency. Full JSON Schema is not usefully reducible to Boolean SAT; validator predicates remain necessary.

## Iterex

- [Iterex](https://github.com/ash-project/iterex) — pausable/resumable external iterators with lazy composition.

Borrow: keep traversal cursor/state separate from traversed graph.

Recommendation: ordinary recursive traversal first. Consider Iterex only for resumable tooling, very large graphs, or lazy recursive expansion.

## Testing and documentation helpers

- [StreamData](https://hexdocs.pm/stream_data/StreamData.html) — bounded generative testing.
- [Floki](https://hexdocs.pm/floki/Floki.html) — HTML structure assertions in renderer tests.
- [ExDoc](https://hexdocs.pm/ex_doc/readme.html) — API and guide publication.

## Dependency policy

Every dependency should earn its place through one of:

- authoritative semantics the project must not reimplement;
- substantial correctness or interoperability value;
- a proven extension boundary;
- tooling whose maintenance cost is lower than an internal substitute.

Keep optional ecosystems behind separate packages or optional compilation paths. See [[04-architecture#Package boundaries|Package boundaries]].

## Related notes

- [[01-philosophy|Project philosophy]]
- [[08-extension-model|Extension model]]
- [[11-testing-strategy|Testing strategy]]
- [[phase-5-ash-integration|Phase 5]]

