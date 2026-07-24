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
- `RenderPlan`, not `PhoenixTree`.

Source packages may use precise source terminology.

## Related notes

- [[15-glossary|Glossary]]
- [[Formentation|Back to the entry point]]

