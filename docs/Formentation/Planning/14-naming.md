---
title: Naming
tags:
  - formentation
  - naming
status: draft
---

# Naming

## Formentation

Formentation is the current working name.

Strengths:

- contains “form” visibly;
- suggests formation, transformation, and configuration;
- does not bind the project to JSON Schema or Phoenix;
- supports clear Elixir module names such as `Formentation.Definition` and `Formentation.Info`;
- is distinctive enough to be searchable.

Risks:

- it is an invented word and needs pronunciation/explanation;
- it can be mistyped as “Formation” or “Fermentation”;
- package, domain, organization, and trademark availability still need checking before publication.

Possible pronunciation: “for-men-TAY-shun,” although the project does not need to prescribe it strongly.

## Alternative names

These are conceptual suggestions only; availability has not been checked.

| Name | Character | Concern |
| --- | --- | --- |
| Formology | Emphasizes a general study/system of forms. | May sound academic; likely used elsewhere. |
| Formative | Friendly and familiar. | Common word and likely difficult to claim. |
| Declariform | Highlights declarative forms. | More technical and less natural. |
| FormWeaver | Suggests combining declarations, state, and UI. | Sounds more like a renderer than a definition system. |
| Forma | Short and elegant. | Extremely broad and likely unavailable. |
| Formcraft | Conveys extensibility and careful construction. | May imply manual construction over derivation. |
| Formarium | Distinctive, suggests a collection/system. | Invented and potentially less obvious. |

Formentation is stronger than names containing “schema,” “JSON,” “Phoenix,” or “HTML” because [[04-architecture|the architecture]] explicitly allows several declaration sources and consumers.

## Package naming

Conceptual package names:

- `formentation`;
- `formentation_phoenix`;
- `formentation_json_schema`;
- `formentation_ash`.

Begin with one repository and possibly one package plus namespaces. Split packages only when optional dependencies, release cadence, or user installation costs justify it.

## Vocabulary style

Prefer domain terms over source-specific terms in core APIs:

- `Definition`, not `CompiledJSONSchema`;
- `Node`, not `SchemaField`;
- `Origin`, not `JSONPointerMetadata`;
- `Issue`, not `ValidationException`;
- `SourceAdapter`, not `SchemaLoader`;
- `PreparedView` for the target component-ready read model, not `PhoenixTree`;
- `UI` or `UI integration` for a component-library adapter, not `Theme`;
- `Theme` only for visual configuration within one UI.

Source packages may use precise source terminology.

Keep the runtime/rendering verbs distinct:

- **FormData projection** turns `%Formentation.Form{}` into
  `%Phoenix.HTML.Form{}`;
- **render preparation** combines the definition, projected form/root, context,
  UI descriptor, and overrides into a prepared view;
- **rendering** turns that prepared view into output through a UI integration.

`Projector`, `RenderPlan`, `RenderNode`, and
`Formentation.Phoenix.Theme.Reference` are current Phase 1 implementation
names. They do not define the future public vocabulary. Before `0.1.0`,
`Projector` should be renamed for preparation and the reference component
module should be renamed so “theme” does not continue to mean a component set.
See
[[20-renderer-ui-model#Projection and preparation terminology|the canonical terminology]].

## Related notes

- [[15-glossary|Glossary]]
- [[20-renderer-ui-model|Renderer and UI model]]
- [[Formentation|Back to the entry point]]
