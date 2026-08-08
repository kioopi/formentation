# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Formentation is pre-`0.1.0`, so breaking renames of internal module names are
expected and are not deprecated first — see
[`docs/Formentation/Planning/18-decisions.md`](docs/Formentation/Planning/18-decisions.md)
for the reasoning behind each one.

## Unreleased

### Changed

- **Breaking:** the `lib/formentation/` tree was restructured so a module's
  location states which architectural layer owns it, taking
  `lib/formentation/` from 29 entries down to 14 and
  `lib/formentation/phoenix/` from 14 down to 8
  ([D-047](docs/Formentation/Planning/18-decisions.md#d-047--the-lib-tree-is-restructured-to-state-the-north-star-architecture)).
  This renames 34 published modules. If your application references any of
  the following by full module name, update the reference:

  | Old name | New name |
  | --- | --- |
  | `Formentation.JSONSchema` | `Formentation.Definition.Source.JSONSchema` |
  | `Formentation.JSONSchema.Validator` | `Formentation.Definition.Source.JSONSchema.Validator` |
  | `Formentation.Source` | `Formentation.Definition.Source` |
  | `Formentation.Source.Map` | `Formentation.Definition.Source.Map` |
  | `Formentation.Source.Shared` | `Formentation.Definition.Source.Shared` |
  | `Formentation.Presentation` (and `Presentation.Field`/`.Group`/`.Object`) | `Formentation.Definition.Presentation` (`.Field`/`.Group`/`.Object`) |
  | `Formentation.Semantic` (and `Semantic.Field`/`.Object`/`.Unsupported`/`.Index`) | `Formentation.Definition.Semantic` (`.Field`/`.Object`/`.Unsupported`/`.Index`) |
  | `Formentation.Validation` | `Formentation.Definition.Validation` |
  | `Formentation.ValidationPlan` | `Formentation.Definition.ValidationPlan` |
  | `Formentation.Codec` | `Formentation.Form.Codec` |
  | `Formentation.Params` | `Formentation.Form.Params` |
  | `Formentation.Transport` | `Formentation.Form.Transport` |
  | `Formentation.SubmissionBlocker` | `Formentation.Form.SubmissionBlocker` |
  | `Formentation.Info.Presentation` (and its `.Object`/`.Field`/`.Group` descriptors) | `Formentation.Info.Layout` (`.Object`/`.Field`/`.Group`) |
  | `Formentation.Phoenix.RenderPlan` (and `.SummaryEntry`) | `Formentation.Phoenix.Render.Plan` (`.SummaryEntry`) |
  | `Formentation.Phoenix.RenderNode` (and `.Field`/`.Group`/`.FieldDOM`/`.GroupDOM`) | `Formentation.Phoenix.Render.Node` (`.Field`/`.Group`/`.FieldDOM`/`.GroupDOM`) |
  | `Formentation.Phoenix.RenderPreparation` (and `.Context`/`.Summary`/`.Visibility`/`.Widget`) | `Formentation.Phoenix.Render.Preparation` (`.Context`/`.Summary`/`.Visibility`/`.Widget`) |
  | `Formentation.Phoenix.ReferenceComponents` | `Formentation.Phoenix.Theme.Reference` |

  The public API surface (`Formentation.compile/2`, `Formentation.form/2`,
  `Formentation.Form`, `Formentation.Info`, `Formentation.Phoenix.fields/1`
  and `field/1`, the `:map`/`:json_schema` adapter selectors, and the shared
  kernel — `InstancePath`, `TemplatePath`, `JSONPointer`, `NodeId`, `Origin`,
  `Diagnostic`, `Issue`) did not move and is unaffected.
