---
title: Formentation Glossary
tags:
  - formentation
  - glossary
status: draft
---

# Glossary

**Codec** — Converts between raw browser parameters and domain/JSON values while preserving path-aware decoding failures.

**Compiler pass** — A named, ordered transformation of a static definition during compilation.

**Decision** — A resolved configuration value plus provenance and, where useful, superseded candidates.

**Declaration source** — External data describing form meaning, such as JSON Schema, UI hints, or Ash resource/action metadata.

**Concrete component** — A Phoenix function component, LiveComponent, or other
environment implementation selected by one UI for a prepared abstract widget
or container.

**Control value** — The raw value presented by an editable control. After an
invalid attempt it preserves the user's input rather than a normalized or
localized replacement.

**Definition** — The static, source-independent result of compilation,
containing separate semantic structure and presentation layout plus
diagnostics, provenance, and adapter-owned validation information.

**Diagnostic** — A structured message about declarations, compiler configuration, extensions, capabilities, or system support.

**Display value** — A localized or domain-formatted read-only representation
used for review, confirmation, print, or similar output; distinct from an
editable control value.

**Form** — The ordinary runtime object for one interaction lifecycle. It owns
or wraps original/current data, raw params, decoded operations, issues, usage,
submission blockers, stable collection identities, and backing state.

**FormData projection** — Conversion of `%Formentation.Form{}` into
`%Phoenix.HTML.Form{}` with caller-owned names/IDs and a preserved root plus
selected subtree.

**Info API** — Stable public queries over a definition.

**Instance path** — Location within a concrete data instance, such as `addresses[2].postcode`.

**Template node** — A position declared in the template, named by a `TemplatePath`.

**Occurrence** — A template node bound to one concrete `InstancePath` at runtime.

**Projection** — The syntactic mapping from `InstancePath` to `TemplatePath`,
replacing integer segments with `:item`.

**Issue** — A structured expected problem with submitted or decoded instance data.

**Node** — A semantic element in the current or future definition model, such
as a field, object, collection, choice, condition, content, or extension node.

**Origin** — Source location or derivation rule that explains where a declaration or decision came from.

**Origin tag** — Compact origin reference such as `{:ui_hints, pointer}` or `{:inference, rule_name}`; the simplified provenance form used before the full Decision model exists (see [[18-decisions|D-003]]).

**Prepared view** — Immutable, source-neutral, renderer-owned,
component-ready facts for concrete semantic/presentation occurrences. It may be
environment-specific and includes binding, visibility, transport,
localization, accessibility, capability, and fallback facts required by a UI.

**Presentation layout** — Static, source-neutral, UI-independent arrangement of
semantic references, groups, labels/help, hidden intent, and abstract widget
intent. It does not define data nesting or concrete components.

**Projector** — Historical Phase 1 name for the Phoenix render-preparation
engine. New vocabulary distinguishes FormData projection from render
preparation.

**Render plan** — Current Phase 1 internal representation of prepared visible
occurrences. It is evidence for, not automatically the public shape of, the
future prepared view.

**Render preparation** — Renderer operation that combines a definition, a
projected form/root or advanced state view, renderer context, UI capabilities,
and overrides into a prepared view.

**Renderer** — Environment integration that prepares form occurrences and
bindings for output, initially `Formentation.Phoenix`. It does not mean a
component-library package.

**Role** — Semantic meaning relevant to presentation, such as `:date`, `:email`,
or `:money`; distinct from an abstract widget and concrete component.

**Schema location** — Location within a schema resource, usually a canonical document URI plus JSON Pointer.

**Source adapter** — Translates a declaration source into Formentation compiler input while preserving source semantics and provenance.

**Template path** — Path of a semantic node independent of concrete collection indexes, such as `addresses[*].postcode`.

**Theme** — Visual configuration within one UI, such as tokens, density, colour
mode, spacing, or a component-library theme name. It is not a component
registry, renderer, or UI integration.

**Transport contract** — Renderer-prepared description of the controls a UI
must emit: primary/auxiliary names and raw values, scalar/list/structured
shape, cardinality, omission/unchecked/blank/null behaviour, and
environment-specific markers. The UI implements it; the codec and `Form` own
decoding semantics.

**UI integration** — Mapping from a renderer-prepared view to one concrete
component library or application design system. It owns components and markup,
not semantic traversal, decoding, validation, or submission policy.

**Verifier** — Read-only compiler stage that checks invariants and emits diagnostics.

**Widget** — An abstract input interaction such as `:textarea`, `:checkbox`, or
`:money_input`; distinct from the semantic role it represents and the concrete
UI component that implements it.

**Widget key** — Identifier for an abstract widget, resolved from role/type,
presentation intent, UI defaults/capabilities, and application overrides. See
[[20-renderer-ui-model#Widget resolution|role → abstract widget → concrete component]].

## Related notes

- [[03-conceptual-model|Conceptual model]]
- [[14-naming|Naming]]
- [[20-renderer-ui-model|Renderer and UI model]]
- [[Formentation|Back to the entry point]]
