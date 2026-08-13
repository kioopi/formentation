# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Formentation is pre-`1.0`, so breaking changes — including renames of published
module names — are expected within a minor version and are not deprecated
first; see
[`docs/Formentation/Planning/18-decisions.md`](docs/Formentation/Planning/18-decisions.md)
for the reasoning behind each one. Releases are consumed as Git tags, not from
Hex.

## Unreleased

### Changed

- **Breaking:** the `Formentation.Info.Layout` descriptors address template
  positions instead of instance occurrences. `Info.Layout.Object` and
  `Info.Layout.Field` both replace `semantic_path :: Formentation.InstancePath.t()`
  with `template_path :: Formentation.TemplatePath.t()`; the field is in
  `@enforce_keys` on both structs, so code that pattern-matches or constructs
  a descriptor must be updated. A layout descriptor describes a declared node,
  which has one static position and — once collections land — many occurrences,
  so an instance path was never the right type for it. No compatibility field
  is kept
  ([D-050](docs/Formentation/Planning/18-decisions.md#d-050--occurrence-is-the-runtime-binding-of-a-template-node)).

Runtime behaviour is otherwise unchanged across the unreleased waves: the form
runtime decomposition
([D-051](docs/Formentation/Planning/18-decisions.md#d-051--the-form-runtime-pipeline-is-decomposed-into-internal-modules))
and the source-adapter compiler cleanup
([D-052](docs/Formentation/Planning/18-decisions.md#d-052--a-definition-is-final))
are internal refactors that produce identical definitions, diagnostics, and
form transitions.

## 0.2.0 — 2026-08-09

### Added

- `Formentation.form/2`, which compiles a declaration and initializes a form
  in one call, alongside stable `:map` and `:json_schema` source selectors for
  both `compile/2` and `form/2` ([#27](https://github.com/kioopi/formentation/issues/27)).
- `Formentation.Form.submission_status/1` and
  `Formentation.Form.SubmissionBlocker`, which expose why a submission is not
  application-ready — `:undecodable`, `{:blocked, blockers}`, or
  `{:invalid, issues}` ([#3](https://github.com/kioopi/formentation/issues/3)).
- Separate semantic and presentation query seams on `Formentation.Info`.
- Projected-form rendering: `Formentation.Phoenix.fields/1` and `field/1`
  accept a `Phoenix.HTML.Form` projection of a `Formentation.Form` without a
  separate `definition:` assign, deriving the definition and projection root
  from the projection ([#39](https://github.com/kioopi/formentation/issues/39)).

### Changed

- **Breaking:** `Formentation.Form.submit/2` returns the application decision
  instead of the form. At `v0.1.0` its spec was `submit(t(), map()) :: t()`; it
  now returns `{:ok, instance, submitted_form}` only when the submission is
  application-ready, and `{:error, submitted_form}` for redisplay
  ([#3](https://github.com/kioopi/formentation/issues/3),
  [#19](https://github.com/kioopi/formentation/issues/19)). Existing code that
  assigns the result directly will silently start holding a tuple — see
  **Migration** below.
- **Breaking:** `Formentation.Definition` stores separate semantic and
  presentation structures. Its format version was bumped, and the old mixed
  root tree, the `nests_data?` flag, and `Formentation.Node.*` are gone.
- **Breaking:** `Info.fields/1` returns semantic declaration order, while
  presentation traversal returns layout order. At `v0.1.0` a single mixed tree
  made these the same order. This is an intentional correction, not a
  regression, but it changes observable output.
- The public Phoenix lifecycle now projects a `Formentation.Form` directly
  rather than passing `definition:` alongside a generic form. Other `FormData`
  sources remain supported and continue to supply `definition:`.
- **Breaking:** the `lib/formentation/` tree was restructured so a module's
  location states which architectural layer owns it
  ([D-047](docs/Formentation/Planning/18-decisions.md#d-047--the-lib-tree-is-restructured-to-state-the-north-star-architecture)).
  Every module rename since `v0.1.0` is tabulated under **Migration** below.

  The ordinary entry-point API (`Formentation.compile/2`, `Formentation.form/2`,
  `Formentation.Form`, `Formentation.Info`, `Formentation.Phoenix.fields/1`
  and `field/1`, the `:map`/`:json_schema` adapter selectors, and the shared
  kernel — `InstancePath`, `TemplatePath`, `JSONPointer`, `NodeId`, `Origin`,
  `Diagnostic`, `Issue`, `Formentation.Definition`, `Formentation.Source`,
  `Formentation.Source.Map`) did not move and is unaffected.

### Fixed

- Nested-object content-derived presence
  ([#1](https://github.com/kioopi/formentation/issues/1)).
- Submission blockers for unsupported nodes
  ([#3](https://github.com/kioopi/formentation/issues/3)).
- DOM identity and duplicate-id handling
  ([#32](https://github.com/kioopi/formentation/issues/32)).
- Group help rendering ([#35](https://github.com/kioopi/formentation/issues/35)).
- Numeric rendering preserves raw input
  ([#36](https://github.com/kioopi/formentation/issues/36)).
- Map-source compiler totality over malformed declarations
  ([#6](https://github.com/kioopi/formentation/issues/6)).

### Removed

- The unused `vibe_kit` runtime dependency. No library or demo module
  referenced it, and an unconditional dependency of a form library is imposed
  on every consuming application. A future UI-library integration will declare
  its own dependencies when that boundary is designed
  ([#9](https://github.com/kioopi/formentation/issues/9)).

### Migration

Everything below is expressed against **`v0.1.0`**, the only released version.
Intermediate names that existed only between tags are deliberately absent.

**1. `Form.submit/2` returns a decision tuple.** This is the change most likely
to break a working application, and it fails quietly rather than loudly — the
old call still succeeds, it just returns something else.

```elixir
# v0.1.0 — returned the form
socket = assign(socket, form_state: Formentation.Form.submit(form, params))

# v0.2.0
case Formentation.Form.submit(form, params) do
  {:ok, instance, submitted_form} -> # application-ready; persist `instance`
  {:error, submitted_form} -> # redisplay `submitted_form`
end
```

Use `Formentation.Form.submission_status/1` on the returned form if you need to
distinguish `:undecodable`, `{:blocked, blockers}`, and `{:invalid, issues}`.

**2. `Info.fields/1` returns declaration order.** At `v0.1.0` it followed the
single mixed tree, so its order matched the rendered layout. It now returns
**semantic declaration order**; presentation traversal returns layout order.
If you relied on `Info.fields/1` to drive rendering order, use the layout
query instead.

**3. Rendering no longer needs a `definition:` assign.** Pass the projected
`Formentation.Form` alone:

```elixir
# v0.1.0
<Formentation.Phoenix.fields definition={@definition} form={@form} />

# v0.2.0 — the definition is recovered from the projection
<Formentation.Phoenix.fields form={@form} />
```

Any other `Phoenix.HTML.FormData` source is still supported and still supplies
`definition:`; that route is now explicitly a permanent advanced path.

**4. Module renames.** If your application references any of these by full
module name, update the reference:

  | `v0.1.0` name | `v0.2.0` name |
  | --- | --- |
  | `Formentation.JSONSchema` | `Formentation.Source.JSONSchema` |
  | `Formentation.JSONSchema.Validator` | `Formentation.Source.JSONSchema.Validator` |
  | `Formentation.Codec` | `Formentation.Form.Codec` |
  | `Formentation.Params` | `Formentation.Form.Params` |
  | `Formentation.Transport` | `Formentation.Form.Transport` |
  | `Formentation.Phoenix.RenderPlan` | `Formentation.Phoenix.Render.Plan` (`.SummaryEntry`) |
  | `Formentation.Phoenix.RenderNode` (and `.Field`/`.Group`) | `Formentation.Phoenix.Render.Node` (`.Field`/`.Group`/`.FieldDOM`/`.GroupDOM`) |
  | `Formentation.Phoenix.Projector` | `Formentation.Phoenix.Render.Preparation` (`.Context`/`.Summary`/`.Visibility`/`.Widget`) |
  | `Formentation.Phoenix.Theme.Reference` | `Formentation.Phoenix.UI.Reference` |

  `Formentation.Phoenix.Render.*` and `UI.Reference` are excluded from the
  published documentation in `v0.2.0` — they keep their moduledocs for IEx, but
  they are internal by intent. Code that reached into them at `v0.1.0` was
  depending on an implementation detail and should move to `Formentation.Info`.

**5. `Formentation.Node.*` is gone, split rather than renamed.** The single
mixed node tree became two structures, so there is no one-to-one replacement:

  | `v0.1.0` | `v0.2.0` |
  | --- | --- |
  | `Formentation.Node.Field` | `Formentation.Definition.Semantic.Field` (value facts) plus `Formentation.Definition.Presentation.Field` (layout reference) |
  | `Formentation.Node.Group` | `Formentation.Definition.Semantic.Object` when it nested data; `Formentation.Definition.Presentation.Group` when it only grouped for display — the `nests_data?` flag that distinguished them is gone |
  | `Formentation.Node.Unsupported` | `Formentation.Definition.Semantic.Unsupported` |
  | `Formentation.Node` (the `t()` union) | no equivalent; the two trees have separate types |

  `Definition.root` no longer exists. Query definitions through
  `Formentation.Info` rather than pattern-matching their storage — that is the
  stable surface, and the one this split was designed to keep intact.

## 0.1.0 — 2026-07-24

Initial tagged release: the Phase 1 walking skeleton. Declarations from the
plain-Elixir map source or a JSON Schema 2020-12 subset compile to a
`Formentation.Definition` queried through `Formentation.Info`; a
`Formentation.Form` pairs one with data and runs decode/validate transitions;
`Formentation.Phoenix.fields/1` and `field/1` render it through
`Phoenix.HTML.FormData` with an accessible reference UI, exercised by a
runnable demo and a real-browser suite.

Consumers on this tag should read the `0.2.0` **Migration** notes above before
upgrading: the definition representation, `Form.submit/2`'s return shape, and
several module names all changed.
