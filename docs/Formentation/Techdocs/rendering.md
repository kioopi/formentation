---
title: Rendering
aliases:
  - Rendering
tags:
  - formentation
  - techdocs
  - rendering
  - phoenix
status: current
---

# Rendering

*As of 2026-08-03 (native presentation traversal and semantic-index-backed
projection, [[18-decisions#D-033 — Phase 1 layout covers each supported occurrence exactly once|D-033]]; StateView protocol, [[18-decisions#D-027 — Projection reads semantic state through a StateView protocol|D-027]]; submission blockers normalized through it, [[18-decisions#D-028 — Unsupported nodes are a preserve-only capability; blocking is derived at runtime|D-028]]). Layers: definition → state → projection → **rendering**; the LiveView lifecycle now drives this same chain through `Form.validate/2`/`Form.submit/2` — see [[form-state-and-transitions#LiveView entry points|form state and transitions]]. Collections and a theme contract do not exist yet.*

## Projector data flow (`Formentation.Phoenix.Projector`)

`Projector.project(definition, %Phoenix.HTML.Form{})` returns a
`%Formentation.Phoenix.RenderPlan{}`. It is pure — the same definition and
form state always produce the same plan, with no side effects and no
mutation of form state. `Projector.project_at(definition, form, path)`
projects the single subtree at an instance path (a field or a
data-nesting group), returning `nil` when the node deliberately renders
nothing, and raising for an unknown or unsupported path.

The walk consumes `Formentation.Info.presentation_root/1` and
`presentation_at/2`. Those queries read the native `Definition.presentation`
tree and return typed presentation descriptors:

- **Object descriptors** carry a semantic `InstancePath` and form a
  layout boundary for the root or a nested data object.
- **Group descriptors** carry presentation layout identity only. They
  project their children under the same Phoenix form; a fieldset never
  introduces name nesting.
- **Field descriptors** carry a semantic `InstancePath` plus presentation
  facts such as label, help, hidden-control intent, and widget hint.

The projector builds one semantic-node lookup from `Definition.semantic` and
uses descriptor paths to resolve field facts through that backing store. This
keeps declaration order and layout order as separate contracts: for example,
semantic fields can enumerate as `["a", "c"]` while a presentation group
renders them as `["c", "a"]`. Unsupported nodes do not appear in renderable
presentation traversal; their semantic paths still classify as unsupported so
`project_at/3` and summary labelling preserve their existing behaviour.

Nested object descriptors cause exactly one
`Phoenix.HTML.FormData.to_form/4` descent for their semantic segment —
never `<.inputs_for>` and never a presentation-group id. Nothing injects
`_persistent_id` this way, which settles the rendering half of that open
question (the transport-side handling stays open for step 7) —
[[18-decisions#D-019 — Projection is Phoenix-generic|D-019]]. Fields that
are both presentation-hidden and semantically read-only project to nothing.

## `RenderPlan` and render-node shapes

One struct per render node shape:

- `Formentation.Phoenix.RenderPlan` — `root` (a `RenderNode.Group`),
  `summary` (the submit-gated error-summary entries, `%{id, label,
  message}`), `diagnostics` (projection-time `Diagnostic`s, e.g.
  `:widget_fallback`). Planning-note fields with no Phase 1 behavior
  (fingerprint, active branches, item identities) are omitted, not
  stubbed.
- `Formentation.Phoenix.RenderNode.Group` — `legend`, `children`. Semantic
  objects and presentation groups both project to this one render shape.
- `Formentation.Phoenix.RenderNode.Field` — `widget`, `field` (the
  `%Phoenix.HTML.FormField{}`, carrying id/name/value), `label`, `help`,
  `options`, `validations` (`Phoenix.HTML.Form.input_validations/2`,
  precomputed so the theme never calls back), `errors`, `show_errors?`,
  `read_only?`.

`show_errors?` is computed once, in the projector, so themes never
inspect `_unused_` markers or `form.action` (D-014, D-027). The source's
`StateView.issue_visibility/3` decides first; only a `:default` answer
falls back to the Phoenix-generic rule:

```
show_errors? = field.errors != [] and
  case StateView.issue_visibility(form.source, form, path) do
    :show -> true
    :hide -> false
    :default -> StateView.submitted?(form.source, form) or Phoenix.Component.used_input?(field)
  end
```

For a `%Formentation.Form{}` source this never reaches `:default` —
`Formentation.Form` owns the complete D-014 policy and answers `:show`/`:hide`
directly from `Form.show_issues?/2`, which reads *accumulated* usage rather
than `used_input?/1`'s *current-params* view. The two agree on every normal
LiveView round-trip and diverge when a later payload omits a path a prior
one used — see [[18-decisions#D-027 — Projection reads semantic state through a StateView protocol|D-027]]'s
recorded behaviour change for the pinned example. Any other `FormData`
source has no state view and falls back to `Any`, which always answers
`:default` — reproducing the formula's right-hand side unchanged.

## Widget resolution

First match wins:

| # | Condition | Widget |
| --- | --- | --- |
| 1 | `hidden?` | `:hidden_input` |
| 2 | widget hint present and sensible for the node | the hinted widget |
| 3 | `options` present | `:select` |
| 4 | `value_type: :boolean` | `:checkbox` |
| 5 | `value_type: :integer \| :number` | `:number_input` |
| 6 | `role: :date \| :email \| :uri` | `:date_input` / `:email_input` / `:url_input` |
| 7 | otherwise | `:text_input` |

A widget hint the theme's widget set does not cover (possible via the
unvalidated map source), or a `:checkbox` hint on a non-boolean field
(D-011's transport contract is boolean-shaped), falls back to the
*inferred* widget from the table above and records a `:widget_fallback`
diagnostic on the plan.

## Error summary

`plan.summary` is populated only when `StateView.submitted?/2` answers
`true` for `form.source`; otherwise it is `[]`. For a `%Formentation.Form{}`
source that means the last transition carried `event: :submit`
(`Form.submitted?/1`); for any other source through the `Any` fallback it
means `form.action == :submit`, the same rule as before D-027
([[18-decisions#D-027 — Projection reads semantic state through a StateView protocol|D-027]]).
It combines two sources:

- **Field entries** — every rendered field with `show_errors?: true`
  contributes one entry per error message, linkable to `field.id`.
- **Object entries** — root and object-level issues never appear in
  Phoenix's per-field `field.errors` convention. The projector asks the
  source's `StateView.issues/2` for the complete, normalized, adapter-ordered
  list and keeps the entries with no matching field node (`id: nil`, no
  link target), filtered by `issue_visibility/3`. `Formentation.Form`
  answers `{:ok, issues}`; a source with no enumeration capability answers
  `:unavailable` and the summary degrades honestly to the field entries
  only — the degradation is keyed on what `issues/2` reports, not on the
  source's module.

An entry whose path resolves to a `Semantic.Unsupported` is the one object
entry the projector labels, humanizing the node's last path segment; root
and group entries stay unlabelled.

### Where submission blockers enter

Capability explanations are not a projector concept. The
`%Formentation.Form{}` state view translates each
`Formentation.SubmissionBlocker` from `Form.submission_blockers/1` into one
normalized `StateView.Issue` at the owning unsupported node's path, whose
message is the blocker's source-neutral capability text with the owned
validation messages appended after `"Validation: "` when there are any. It
then drops the issues that blocker already speaks for, so they are not
enumerated a second time as bare lines. Blockers lead the enumeration;
everything else follows in path order
([[18-decisions#D-028 — Unsupported nodes are a preserve-only capability; blocking is derived at runtime|D-028]],
[[form-state-and-transitions#Submission status is derived, not stored|Form state and transitions]]).

By the time the list reaches the projector it is ordinary normalized
issues, so the object-entry rule above renders them unchanged — including
the humanized label, which the unsupported-node case already earns. A
source with different semantics (Ash, Ecto) can produce equivalent entries
without the projector learning anything new.

The summary renders at the top of `fields/1`'s own output, not the top
of the page. When the payload form is embedded after hand-written
inputs — the pump-inspection demo's shape, and the common LiveView
pattern — the summary appears mid-page rather than above everything.
There is no slot to reposition it; that is a
[[phase-3-extensibility|Phase 3]] theme-contract concern
([[18-decisions#D-021 — LiveView integration is wrappers plus a demo, not framework machinery|D-021]]).

## Public components and the Phoenix-generic boundary

`Formentation.Phoenix` exposes two function components, both composing
*inside* an enclosing hand-written `<form>` — neither renders a `<form>`
element, and names/ids work under a parent namespace such as
`asset[payload][...]`:

- `<Formentation.Phoenix.fields definition={@definition} form={@form} />`
  — the whole payload body: the error summary, then the projected tree.
- `<Formentation.Phoenix.field definition={@definition} form={@form}
  path={["email"]} />` — a subtree render at an instance path (fields and
  data-nesting groups; presentational groups have no instance path and
  are not independently addressable).

The projector reads display values, names, IDs, input validations, and
per-field errors through Phoenix conventions, and the three semantic facts
Phoenix cannot carry — submission, issue visibility, root/object issues —
through `Formentation.Phoenix.StateView`, dispatched on `form.source` with
`@fallback_to_any` — so any `Phoenix.HTML.FormData` implementation still
projects, not only `Formentation.Form`; an `AshPhoenix.Form` is just
another implementation to project, through the `Any` fallback until it
gets a dedicated state view. Neither `Projector.project/2`/`project_at/3`
nor either component takes an adapter argument — dispatch is entirely on
`form.source`. All of this lives in `lib/formentation/phoenix/`, behind the
[[18-decisions#D-017 — Phoenix integration ships in-tree behind a namespace boundary|D-017]]/[[18-decisions#D-018 — Reach is the architecture gate|D-018]] directory boundary —
[[18-decisions#D-019 — Projection is Phoenix-generic|D-019]],
[[18-decisions#D-027 — Projection reads semantic state through a StateView protocol|D-027]].

## DOM identity

Transport names and renderer-owned DOM identities are distinct facts. A
`Phoenix.HTML.FormField.name` remains the browser's submitted parameter name;
the renderer mints the ids it owns for controls, help, errors, containers, and
radio options. This avoids treating Phoenix's underscore-joined `FormField.id`
as a collision-proof DOM namespace.

`Formentation.Phoenix.DOMIdentity` is the internal primitive. It takes a
non-empty binary namespace plus a typed occurrence and emits this stable,
selector-safe contract:

```text
ftn--<namespace>--<kind>--<part>--<identity token>...
```

`kind` is `field`, `object`, or `group`. Field identities contain their
absolute instance-path segments; object identities contain their occurrence
path (none for the root); group identities contain the opaque layout id and
the enclosing object's occurrence path. `part` is `control`, `help`, `errors`,
`container`, or `option_<index>`. These are separate token positions, so a
field called `notes_help` and the help for `notes` cannot share an id.

Identity and namespace bytes are escaped byte by byte: ASCII letters, digits,
and `_` remain literal except that a leading digit is encoded; every other byte
is `-XX` with uppercase hexadecimal bytes. Therefore `--` appears only as the
token delimiter. The grammar preserves both path boundaries (`["a_b"]` versus
`["a", "b"]`) and segment type (`[0]` versus `["0"]`). Its output alphabet is
`[A-Za-z0-9_-]` and the `ftn` prefix makes it usable as an unescaped HTML/CSS
identifier in browser, Floki, and LazyHTML selectors.

The spelling is deliberately readable and stable: applications may use these
ids in tests, styles, and scripts. It changes only as a compatibility change.
The guarantee covers ids minted through this system within a render namespace;
it cannot prevent an application from manually writing the same id elsewhere
on the page. There is no hash, counter, traversal index, random value, or
occupied-id registry.

This is a foundation-only change: the current reference components still emit
Phoenix-derived ids. [[18-decisions#D-034 — Phoenix renderer DOM identities are typed and injective|D-034]]
records the contract; [issue #30](https://github.com/kioopi/formentation/issues/30)
will resolve component namespace selection and adopt it across the render plan
and markup.

## Reference theme (`Formentation.Phoenix.Theme.Reference`)

Per-widget function components called directly by `fields/1` and
`field/1` — nothing dispatches through a configurable theme parameter.
Phase 1 has no theme parameter or contract; this module is a markup set,
the executable specification a second theme will be measured against
once [[phase-3-extensibility|Phase 3]] extracts the real contract —
[[18-decisions#D-020 — The reference theme is a markup set, not a contract|D-020]].

Widget set: `text_input`, `textarea`, `number_input`, `checkbox`,
`select`, `radio_group`, `date_input`, `email_input`, `url_input`,
`hidden_input` — plus the field wrapper, group fieldset, and error
summary.

**Accessibility contract**, documented and Floki-tested against these
components:

1. Every control has a `<label for>` pointing at its id; placeholder text
   is never the only label.
2. Help text renders with a deterministic id, linked via
   `aria-describedby`.
3. Visible errors render with deterministic ids, linked via
   `aria-describedby` (composing with the help id); the control carries
   `aria-invalid`. Errors render only when `show_errors?`.
4. Groups render as `<fieldset>` with a `<legend>` (data-nesting and
   presentational groups, and radio groups).
5. The error summary appears only after submit; each entry with a field
   links (`href="#id"`) to its control; root/object-level entries render
   without a link.
6. No duplicate DOM ids in a rendered document.
7. All schema-provided text (labels, help, options, error messages) is
   HEEx-escaped; nothing schema-derived is ever marked safe.

Conformance obligations pinned on top of the contract:

- The editable checkbox emits the [[18-decisions#D-011 — Booleans use the hidden-input transport contract|D-011]] hidden input (`value="false"` preceding the `value="true"` checkbox).
- [[18-decisions#D-016 — Participation is definition-driven, not transport-driven|D-016]] read-only rendering: `readonly` on text-like controls (text/textarea/number/date/email/url), `disabled` on selects, checkboxes, and radio groups; no hidden mirrors anywhere. A read-only boolean is a disabled checkbox *without* the hidden input — outside D-011's contract, which binds editable checkboxes only.
- Selects always lead with a blank option (`<option value=""></option>`).
- A required boolean never renders the HTML `required` attribute on its checkbox — HTML `required` means must-be-*checked*, a different constraint than "always submits true or false", which the D-011 hidden input already satisfies.
- `:number_input` renders `type="text" inputmode="numeric"`, never `type="number"`: a real browser blocks a `<input type="number">` from *displaying* non-numeric raw text (and sanitizes an injected invalid value on the next round trip), which breaks raw-input preservation after a failed decode. `inputmode="numeric"` keeps the numeric-only mobile keyboard without that constraint — confirmed by a browser check and recorded as [[18-decisions#D-021 — LiveView integration is wrappers plus a demo, not framework machinery|D-021]].
- Progressive-hint attributes (`required`, `min`/`max`/`step`,
  `minlength`/`maxlength`) come from step 5's `input_validations`, applied
  as-is; they are hints, never server validation. Number widgets are the
  exception: since they render as `type="text" inputmode="numeric"` (not
  `type="number"`, see above), `min`/`max`/`step` are non-conforming on that
  fallback and are dropped — only `required` (when present) survives on a
  number input.

## Boundaries — what does not exist yet

LiveView's lifecycle projects through this same layer, with no
LiveView-specific code inside it: `phx-change`/`phx-submit` call
[[form-state-and-transitions#LiveView entry points|`Form.validate/2`/`Form.submit/2`]],
embedding in a live parent is ordinary `:as`/`:id` namespacing (as in the
demo's pump-inspection LiveView), and `_persistent_id` is stripped as
transport metadata by `Transport.normalize/1`. No collections,
item identity, or add/remove/reorder — Milestone B. No theme parameter,
component registry, or extracted theme contract — Phase 3. No branch or
partial-reprojection support — Phase 4. Behavioural widgets (file
uploads, async option search, JS-hook-driven controls) remain an open
question; the render-plan model only describes pure, render-time
widgets. Two edges of the error summary are recorded here rather than
handled: a schema-filed issue at a hidden-and-read-only field (which
never becomes a render node) is silently absent from `plan.summary`,
and an issue at a merely-hidden field produces a summary link whose
`href` targets a hidden control — both reachable only from
schema-backed sources, since the Map source has no validator to file
such issues in the first place.

## Related notes

- [[phoenix-form-data|The FormData projection]] — the layer this reads through
- [[form-state-and-transitions|Form state and transitions]]
- [[definition-and-node|Definition and node structs]]
- [[end-to-end-data-flow|End-to-end data flow]]
- [[Techdocs|Back to Techdocs]]
