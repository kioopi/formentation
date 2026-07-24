---
title: Phase 5 — Ash Integration and Optional Declarative DSL
tags:
  - formentation
  - roadmap
  - phase-5
  - ash
status: planned
phase: 5
---

# Phase 5 — Ash integration and optional declarative DSL

## Goal

Prove that Formentation's definition and renderer are genuinely independent of JSON-backed state by integrating with Ash resource/action declarations and `AshPhoenix.Form`.

The integration should preserve Ash's action, changeset/query, relationship, authorization, tenant, sparse-list, union, nested-form, and submission semantics rather than reimplementing them.

## Risk being retired

The architectural risk is hidden coupling: the renderer may claim to accept any Phoenix form but actually depend on `Formentation.Form` fields, JSON decoding rules, positional arrays, or JSON Schema-specific node metadata.

## Integration directions

There are two related but independent adapters.

### Ash declaration to definition

Compile a `Formentation.Definition` from an Ash resource and action using public introspection APIs. Candidate facts include:

- accepted attributes and action arguments;
- Ash types and constraints;
- required/allow-nil behaviour;
- public descriptions and metadata;
- embedded resources;
- relationship-management changes;
- create/update/read action differences;
- unions/enums and custom Ash types.

Presentation metadata may come from a Formentation extension/DSL rather than being added to Ash itself.

### Ash form state to runtime view

Accept `AshPhoenix.Form` through its `%Phoenix.HTML.Form{}` representation and a minimal adapter for capabilities not present in generic form fields:

- stable nested-form identity;
- add/remove/reorder operations remain Ash operations;
- form type/action/resource metadata for branch selection;
- nested/global error retrieval;
- sparse collections and hidden fields.

The same Phoenix renderer and theme should work without Ash-specific component forks.

## Deliverables

### Optional package/namespace

- `Formentation.Ash` or `formentation_ash` with optional dependencies;
- no Ash dependency in core or JSON Schema adapter;
- compatibility matrix for supported Ash/AshPhoenix versions.

### Ash source adapter

- compile entry points by resource/action and action type;
- type-to-semantic-role mapping;
- action argument/attribute ordering policy;
- embedded resource and managed relationship mapping;
- origins identifying resource, action, attribute/argument, and source module;
- diagnostics for custom/unsupported types and complex changes.

### Ash state adapter

- projection from an Ash-backed `%Phoenix.HTML.Form{}`;
- nested form path mapping;
- access to raw/translatable errors;
- collection identity compatible with sparse forms;
- no duplication of Ash validation/submission;
- helpers or documentation for using existing `AshPhoenix.Form` transitions in LiveView.

### UI metadata strategy

Choose and document one or more approaches:

- separate Formentation UI declaration targeting resource/action paths;
- a Spark extension adding form-presentation sections to Ash resources/domains;
- application-owned mapping modules;
- JSON Schema/UI hints associated with Ash action inputs.

All approaches must compile to the same ordinary Formentation structures.

### Demonstration application

Include:

- create and update actions;
- embedded resource;
- `manage_relationship` nested forms;
- sparse list add/remove/reorder;
- custom Ash type or enum;
- nested validation errors;
- action-specific fields;
- one conditional/union case if supported.

### Spark decision

If [[phase-3-extensibility|Phase 3]] deferred Spark, this is a strong moment to reconsider it. An Ash presentation extension may benefit from [Spark](https://github.com/ash-project/spark) sections/entities, source annotations, transformers, verifiers, generated docs, and autocomplete.

The result should be an architecture decision with prototype evidence. Spark remains optional for JSON/runtime-supplied declarations.

## Implementation strategy

### Step 1: Inventory `AshPhoenix.Form`

Build fixtures and record how root/nested forms expose values, params, IDs, errors, form type, resource/action, hidden fields, and collection identity. Study [AshPhoenix.Form](https://hexdocs.pm/ash_phoenix/AshPhoenix.Form.html), [automatic nested forms](https://hexdocs.pm/ash_phoenix/AshPhoenix.Form.Auto.html), and the existing `FormData` implementation.

### Step 2: Render a hand-authored definition over an Ash form

Before deriving definitions from Ash, prove the runtime boundary. Manually create a compatible definition for one Ash action and render it using the existing renderer.

Every JSON-backed-state assumption found here should be removed or moved into its adapter.

### Step 3: Derive a minimal action definition

Support scalar action inputs first. Map Ash types to semantic kinds/roles and preserve origins. Do not route Ash through JSON Schema solely to reuse the adapter unless a prototype proves that no meaningful Ash semantics are lost.

### Step 4: Add embedded and relationship forms

Use `AshPhoenix.Form.Auto` behaviour and action introspection as sources of nested form structure. Keep relationship semantics in Ash; Formentation describes/presents the available nested forms.

### Step 5: Add UI metadata

Prototype plain mapping data first. If a Spark extension is adopted, make it a front end that emits the same descriptors and origins.

### Step 6: Prove create/update differences

Compile per action initially. Sharing/merging definitions can be considered after differences are visible; one universal resource form is likely to hide action semantics.

## Testing strategy

### Resource/action compilation tests

- accepted versus non-accepted fields;
- required and nil constraints;
- action arguments and attributes;
- type/constraint-to-role mappings;
- create/update/read differences;
- custom type diagnostics;
- origins point to resource/action declarations.

### Ash form integration tests

- initial values and params;
- raw errors and translation tuples;
- nested embedded forms;
- `manage_relationship` forms;
- sparse list identity;
- add/remove/reorder using Ash APIs;
- create versus update child forms;
- hidden fields required for submission;
- successful Ash action submission.

### Decoupling tests

Run the same semantic definition and reference theme with:

- JSON-backed `Formentation.Form`;
- an `AshPhoenix.Form`.

Assert equivalent semantic fields/markup where state semantics are equivalent, while allowing engine-specific hidden fields and IDs.

### Authorization and context tests

- renderer visibility never substitutes for action authorization;
- actor/tenant context remains in Ash form operations;
- diagnostics do not expose sensitive values;
- action acceptance changes result in a new/invalidated definition as appropriate.

### DSL tests, if adopted

- source annotations in verifier errors;
- generated Info functions or descriptors;
- compile-time validation;
- plain data and DSL produce equivalent Formentation definitions;
- core use remains possible without Spark loaded.

## Definition of done

- [ ] An existing `AshPhoenix.Form` renders through the same projector/renderer used by JSON-backed forms.
- [ ] Ash validation, add/remove, relationship, and submission operations remain owned by AshPhoenix.
- [ ] Definitions can be derived for documented Ash action/type subsets through public introspection.
- [ ] Create and update actions may produce different definitions without hacks.
- [ ] Embedded resources and at least one managed relationship render and submit correctly.
- [ ] Sparse collection identity works through LiveView lifecycle tests.
- [ ] Unsupported custom types produce actionable diagnostics and extension hints.
- [ ] Ash-originated decisions are explainable through `Formentation.Info`.
- [ ] Core and Phoenix base packages do not require Ash.
- [ ] A documented evidence-based decision exists for an optional Spark DSL/extension.

## Notes of caution

- Do not replace `AshPhoenix.Form` with a JSON-shaped copy.
- Do not assume resource attributes equal action inputs; actions and arguments are the correct scope.
- Do not use UI visibility as authorization.
- Relationship changes contain lifecycle semantics not representable as ordinary nested maps.
- Sparse forms deliberately do not behave like positional arrays.
- Custom Ash types may need both semantic-role and codec extensions.
- Generating JSON Schema from Ash and immediately compiling it may lose action/change metadata; treat this as an optional interoperability route, not the default architecture.
- A Spark DSL embedded into Ash resources should remain presentation metadata and not force UI concerns into Ash core behaviour.

## Exit and future work

After this phase, Formentation has proved multiple declaration/state sources and a reusable renderer. Future work can be prioritized by users:

- richer source adapters;
- additional Phoenix UI packages;
- form documentation and editors;
- accessibility auditing;
- server-driven form protocols;
- definition diff/migration tooling;
- persistence or transport formats for definitions.

These are not automatic Phase 7 commitments. Apply [[01-philosophy#Incremental design|incremental declarative design]].

## Related notes

- [[12-ecosystem-and-dependencies#Ash|Ash ecosystem]]
- [[07-phoenix-integration#Existing form engines|Existing form engines]]
- [[08-extension-model#Optional Spark DSL|Optional Spark DSL]]
- [[11-testing-strategy#Ash integration tests|Ash integration tests]]
- [[13-roadmap|Back to the roadmap]]

