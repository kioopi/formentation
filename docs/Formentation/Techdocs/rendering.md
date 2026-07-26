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

*As of 2026-07-25 (StateView protocol, D-027). Layers: definition → state → projection → **rendering**; the LiveView lifecycle now drives this same chain through `Form.validate/2`/`Form.submit/2` — see [[form-state-and-transitions#LiveView entry points|form state and transitions]]. Collections and a theme contract do not exist yet.*

## Projector data flow (`Formentation.Phoenix.Projector`)

`Projector.project(definition, %Phoenix.HTML.Form{})` returns a
`%Formentation.Phoenix.RenderPlan{}`. It is pure — the same definition and
form state always produce the same plan, with no side effects and no
mutation of form state. `Projector.project_at(definition, form, path)`
projects the single subtree at an instance path (a field or a
data-nesting group), returning `nil` when the node deliberately renders
nothing, and raising for an unknown or unsupported path.

The walk mirrors the compiled tree in declaration order (ordering was
already resolved at compile time; the projector adds none):

- **Fields** resolve a widget (table below), a label (`node.label`,
  falling back to the humanized field name), and `show_errors?`.
- **Presentational groups** (`nests_data?: false`, D-006) project their
  children under the *same* Phoenix form — a fieldset never introduces
  name nesting.
- **Data-nesting groups** project children under a nested form the
  projector materializes directly via
  `Phoenix.HTML.FormData.to_form/4` — never `<.inputs_for>`. Nothing
  injects `_persistent_id` this way, which settles the rendering half of
  that open question (the transport-side handling stays open for step 7)
  — [[18-decisions#D-019 — Projection is Phoenix-generic|D-019]].
- **Unsupported nodes**, and fields that are both `hidden?` and
  `read_only?` (D-016), project to nothing.

## `RenderPlan` and render-node shapes

One struct per node kind (D-015), mirroring `Formentation.Node`:

- `Formentation.Phoenix.RenderPlan` — `root` (a `RenderNode.Group`),
  `summary` (the submit-gated error-summary entries, `%{id, label,
  message}`), `diagnostics` (projection-time `Diagnostic`s, e.g.
  `:widget_fallback`). Planning-note fields with no Phase 1 behavior
  (fingerprint, active branches, item identities) are omitted, not
  stubbed.
- `Formentation.Phoenix.RenderNode.Group` — `legend`, `children`. Both
  D-006 group flavors project to this one shape; only the field names
  inside differ.
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
