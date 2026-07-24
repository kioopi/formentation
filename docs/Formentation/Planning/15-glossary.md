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

**Definition** — The static, source-independent semantic representation produced by compilation.

**Diagnostic** — A structured message about declarations, compiler configuration, extensions, capabilities, or system support.

**Form state** — Current data, raw params, decoded values, errors/issues, action, and nested item operations for an interaction.

**Info API** — Stable public queries over a definition.

**Instance path** — Location within a concrete data instance, such as `addresses[2].postcode`.

**Issue** — A structured expected problem with submitted or decoded instance data.

**Node** — A semantic element in a definition or render plan: field, group, collection, choice, condition, content, or extension node.

**Origin** — Source location or derivation rule that explains where a declaration or decision came from.

**Origin tag** — Compact origin reference such as `{:ui_hints, pointer}` or `{:inference, rule_name}`; the simplified provenance form used before the full Decision model exists (see [[18-decisions|D-003]]).

**Projector** — Runtime engine that combines a static definition with form state and context to produce a render plan.

**Render plan** — Concrete tree of visible nodes, active branches, collection items, widget decisions, runtime fields, and issues.

**Renderer** — Platform-specific engine that turns a render plan into output, initially Phoenix HEEx.

**Role** — Semantic presentation meaning such as `:date`, `:email`, or `:money`; distinct from a concrete widget.

**Schema location** — Location within a schema resource, usually a canonical document URI plus JSON Pointer.

**Source adapter** — Translates a declaration source into Formentation compiler input while preserving source semantics and provenance.

**Template path** — Path of a semantic node independent of concrete collection indexes, such as `addresses[*].postcode`.

**Theme** — Presentation policy mapping roles/widgets to components, layout, and styles.

**Verifier** — Read-only compiler stage that checks invariants and emits diagnostics.

**Widget** — A particular input interaction, named by a widget key.

**Widget key** — Abstract interaction kind such as `:textarea` or `:date_input`, resolved from role, UI hints, and theme defaults; distinct from the role above it and from the concrete component a theme binds to it. See [[03-conceptual-model#Renderer, theme, and widget|role → widget key → component]].

## Related notes

- [[03-conceptual-model|Conceptual model]]
- [[14-naming|Naming]]
- [[Formentation|Back to the entry point]]

