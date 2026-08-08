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

*As of 2026-08-07 (projection-context resolution and cursor ownership extracted
to `RenderPreparation.Context`; object-level error-summary entries link to their rendered,
focusable fieldset, keyed off `RenderNode.Group`'s `kind`/`occurrence_path`
provenance, [GitHub issue #34](https://github.com/kioopi/formentation/issues/34);
summary construction extracted to `RenderPreparation.Summary` with entries
promoted to `RenderPlan.SummaryEntry` structs, widget resolution extracted
to `RenderPreparation.Widget` behind a typed `resolve/2`, and D-014/D-027
visibility/submission policy extracted to `RenderPreparation.Visibility`
(the sole caller of `Phoenix.Component.used_input?/1`), with field option ids
consolidated into `DOMIdentity.field_options/3` — internal refactors, no
behaviour change; validated projection roots, projected native Phoenix
forms, nested subtree summaries,
and explicit generic FormData route, [[18-decisions#D-041 — Projected Phoenix forms are the ordinary rendering input|D-041]]; native presentation traversal and semantic-index-backed
projection, [[18-decisions#D-033 — Phase 1 layout covers each supported occurrence exactly once|D-033]]; StateView protocol, [[18-decisions#D-027 — Projection reads semantic state through a StateView protocol|D-027]]; submission blockers normalized through it, [[18-decisions#D-028 — Unsupported nodes are a preserve-only capability; blocking is derived at runtime|D-028]]; DOM identity, [[18-decisions#D-034 — Phoenix renderer DOM identities are typed and injective|D-034]]; group help, [[18-decisions#D-036 — Group help uses prepared Phoenix identities|D-036]]; prepared `role`/`required?` on `RenderNode.Field`, [[18-decisions#D-043 — Semantic `role` and schema `required?` join `value_type` as flat prepared facts|D-043]]). Layers: definition → state → projection → **rendering**; the LiveView lifecycle now drives this same chain through `Form.validate/2`/`Form.submit/2` — see [[form-state-and-transitions#LiveView entry points|form state and transitions]]. Collections and a theme contract do not exist yet.*

## Render preparation data flow

Internal `RenderPreparation.prepare/2` returns a
`%Formentation.Phoenix.Render.Plan{}`. It is pure — the same form and
definition context always produce the same plan, with no side effects and no
mutation of form state. A form projected from `Formentation.Form` carries its
definition and projection-root path, so ordinary component use supplies only
the form. Any other `Phoenix.HTML.FormData` source is the explicit advanced
route and supplies `definition:`. `prepare_at/3` projects the single subtree
at a path relative to that form's projection root (a field or a data-nesting
group), returning `nil` when the node deliberately renders nothing, and
raising for an unknown or unsupported path. `prepare/1,2` and `prepare_at/2,3`
accept an explicit `dom_namespace`; otherwise they use `form.id || form.name` and
raise with an actionable error when neither exists.

`RenderPreparation.Context` owns the projection-context boundary: it selects
the native or generic entry branch, validates the projection root, selects the
DOM namespace, and owns the traversal cursor. It never depends on
`Phoenix.HTML.FormData`; `cursor_to/2` returns the relative segment descent
distance and the moved context, while `RenderPreparation` performs the actual
form descent and traverses the descriptors. `enter/2` similarly reports the
direct child segment without coupling context resolution to Phoenix form
construction.

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
subtree preparation and summary labelling preserve their existing behaviour.

Nested object descriptors cause exactly one
`Phoenix.HTML.FormData.to_form/4` descent for their semantic segment —
never `<.inputs_for>` and never a presentation-group id. Nothing injects
`_persistent_id` this way, which settles the rendering half of that open
question (the transport-side handling stays open for step 7) —
[[18-decisions#D-019 — Projection is Phoenix-generic|D-019]]. Fields that
are both presentation-hidden and semantically read-only project to nothing.

## `RenderPlan` and render-node shapes

One struct per render node shape:

- `Formentation.Phoenix.Render.Plan` — `root` (a `RenderNode.Group`),
  `summary` (the submit-gated error-summary entries, each a
  `RenderPlan.SummaryEntry{id, label, message}`), `diagnostics`
  (projection-time `Diagnostic`s, e.g. `:widget_fallback`). Planning-note
  fields with no Phase 1 behavior (fingerprint, active branches, item
  identities) are omitted, not stubbed.
- `Formentation.Phoenix.Render.Plan.SummaryEntry` — `message` (enforced) plus
  a nilable `id` and `label`. `id` is the DOM id to link to, `nil` for an
  entry with no rendered target; `label` is the prefix the message carries,
  `nil` when the message stands alone. Both entry sources below build
  entries through `SummaryEntry.from_target/2`, which takes the `%{id, label}`
  pair a source resolves and the message it carries.
- `Formentation.Phoenix.Render.Node.Group` — `legend`, `help`, `dom`, `kind`,
  `occurrence_path`, `children`. `dom` is a `GroupDOM{container, help}`
  prepared even for the structural root. Semantic objects and presentation
  groups both project to this one render shape, distinguished by `kind`
  (`:object` | `:presentation_group`, always set by preparation, never
  inferred from DOM-id text or child shape) and `occurrence_path` (the
  occurrence's exact `InstancePath` for an `:object` group, `nil` for a
  presentation group). The root retains its help in the plan; `fields/1` renders only its children,
  while `field path={[]}` renders the root group itself. For a **nested**
  projected form the plan root is the projected object, so the same two rules
  apply one level down: `fields/1` renders the object's children without its
  fieldset, legend, or group help, and `field path={[]}` on that form is how
  the object's own fieldset is rendered.
- `Formentation.Phoenix.Render.Node.Field` — `widget`, `field` (the
  `%Phoenix.HTML.FormField{}`, carrying Phoenix id/name/value), `label`, `dom`,
  normalized semantic `value_type`, source `role` (an atom hint like `:email`
  or `:date`, or `nil`), schema `required?`, `help`,
  `options`, `validations` (`Phoenix.HTML.Form.input_validations/2`,
  precomputed so the theme never calls back), `errors`, `show_errors?`,
  `read_only?`. `dom` is a `FieldDOM{control, container, help, errors,
  options}`. `control` names scalar controls (and hidden inputs); `container`
  names a composite widget's container, currently a radio group's fieldset.
  Options retain source scalar values (`String.t() | number() | boolean()`),
  and option ids are positionally parallel to them. `role` and `required?`
  are prepared meaning facts (D-043): a theme reads them directly, without
  consulting a `Definition` or source adapter. `required?` is the schema fact
  only — it is presentation/accessibility-only and never becomes the native
  HTML `required` attribute, which continues to come solely from
  `validations[:required]` under D-010's policy.

`show_errors?` is computed once during render preparation, so components never
inspect `_unused_` markers or `form.action` (D-014, D-027).
`Formentation.Phoenix.Render.Preparation.Visibility` owns this decision —
`prepare/2` hands it the two context facts it reads (`source`, `root_form`),
narrowed the same way `Summary` is (see below). The source's
`StateView.issue_visibility/3` decides first; only a `:default` answer falls
back to the Phoenix-generic rule:

```
show_errors? = field.errors != [] and
  case StateView.issue_visibility(form.source, form, path) do
    :show -> true
    :hide -> false
    :default -> StateView.submitted?(form.source, form) or Phoenix.Component.used_input?(field)
  end
```

`Visibility` is also the only module that calls `Phoenix.Component.used_input?/1`
and the only source of `submitted?/1`; `Summary` reuses `Visibility.submitted?/1`
rather than re-deciding D-027 submission on its own.

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

`Formentation.Phoenix.Render.Preparation.Widget` owns this decision —
`Widget.resolve/2` takes the `Info.Presentation.Field` descriptor and its
`Semantic.Field` occurrence and returns `{widget, diagnostics}`. First match
wins:

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

The table is covered by property tests that assert the *result* against the
node's shape rather than restating the clause order — a resolved `:checkbox`
implies a boolean node, a `:date_input` implies a `:date` role on a string, a
rejected hint lands exactly where the same node with no hint lands. That keeps
the oracle independent of the implementation it checks.

## Error summary

`Formentation.Phoenix.Render.Preparation.Summary` owns this construction —
`prepare/2` hands it the finished render tree and the four context facts it
reads (`source`, `root_form`, `root_instance_path`, `definition`), and nothing
else. The narrowed parameter is the boundary: summary construction works from
an already-prepared tree and the source's `StateView`, never from the
namespace or traversal state the projection walk carries, so it cannot grow a
dependency on either.

`plan.summary` is populated only when `StateView.submitted?/2` answers
`true` for `form.source`; otherwise it is `[]`. For a `%Formentation.Form{}`
source that means the last transition carried `event: :submit`
(`Form.submitted?/1`); for any other source through the `Any` fallback it
means `form.action == :submit`, the same rule as before D-027
([[18-decisions#D-027 — Projection reads semantic state through a StateView protocol|D-027]]).
It combines two sources:

- **Field entries** — every rendered field with `show_errors?: true`
  contributes one entry per error message. Scalar fields link to their prepared
  control id; radio groups link to their prepared container id, the rendered
  fieldset. That fieldset has `tabindex="-1"`, so following its summary anchor
  moves focus to a meaningful, non-tab-stop group boundary.
- **Object entries** — root and object-level issues never appear in
  Phoenix's per-field `field.errors` convention. The projector asks the
  source's `StateView.issues/2` for the complete, normalized, adapter-ordered
  list, filtered by `issue_visibility/3`. `Formentation.Form` answers
  `{:ok, issues}`; a source with no enumeration capability answers
  `:unavailable` and the summary degrades honestly to the field entries
  only — the degradation is keyed on what `issues/2` reports, not on the
  source's module. An issue whose path names a rendered `:object` group
  links to that group's fieldset, using the group's `legend` as the label
  ([GitHub issue #34](https://github.com/kioopi/formentation/issues/34)).
  `Summary` builds this occurrence-path → target index once per `build/2`
  call by walking `root.children` (never `root` itself — `fields/1` never
  renders the projection root's own fieldset, native or nested, so a
  root-of-form or nested-projection-root issue always stays unlinked) and
  indexing every rendered `:object` group by its exact `occurrence_path`,
  reading the id from the group's already-prepared `dom.container` rather
  than reconstructing one from the issue's path. The lookup is an exact
  match with no ancestor fallback: an issue below a rendered object but
  with no rendered node of its own stays unlinked rather than targeting an
  enclosing fieldset. A `:presentation_group` is walked for its descendant
  objects but is never a link target itself, since it owns no semantic
  occurrence. An `:object` group's fieldset carries `tabindex="-1"`, the
  same convention a radio group's fieldset uses, so a linked entry's anchor
  always resolves to a focusable, non-tab-stop target; a `:presentation_group`
  fieldset carries no `tabindex`.

A nested projected form's plan carries a summary scoped to its own subtree,
but `fields/1` does not render it by default: the summary is owned by the
outermost render, and two `role="alert"` regions for one form is an
accessibility regression. `summary={true}` / `summary={false}` overrides that
placement explicitly.

An entry whose path resolves to a `Semantic.Unsupported` is the one object
entry the projector labels, humanizing the node's last path segment; root
and group entries stay unlabelled.

### Where submission blockers enter

Capability explanations are not a projector concept. The
`%Formentation.Form{}` state view translates each
`Formentation.Form.SubmissionBlocker` from `Form.submission_blockers/1` into one
normalized `StateView.Issue` at the owning unsupported node's path, whose
message is the blocker's source-neutral capability text with the owned
validation messages appended after `"Validation: "` when there are any. It
then drops the issues that blocker already speaks for, so they are not
enumerated a second time as bare lines. Blockers lead the enumeration;
everything else follows in path order
([[18-decisions#D-028 — Unsupported nodes are a preserve-only capability; blocking is derived at runtime|D-028]],
[[form-state-and-transitions#Submission status is derived, not stored|Form state and transitions]]).

By the time the list reaches render preparation it is ordinary normalized
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
  element. Their optional `dom_namespace` overrides only renderer-owned DOM
  identities; it never changes Phoenix names or form ids:

- `<Formentation.Phoenix.fields form={@form} />`
  — the whole payload body: the error summary, then the projected tree.
- `<Formentation.Phoenix.field form={@form}
  path={["email"]} />` — a subtree render at an instance path (fields and
  data-nesting groups; presentational groups have no instance path and
  are not independently addressable).

Render preparation reads display values, names, IDs, input validations, and
per-field errors through Phoenix conventions, and the three semantic facts
Phoenix cannot carry — submission, issue visibility, root/object issues —
through `Formentation.Phoenix.StateView`, dispatched on `form.source` with
`@fallback_to_any` — so any `Phoenix.HTML.FormData` implementation still
projects, not only `Formentation.Form`; an `AshPhoenix.Form` is just
another implementation to project, through the `Any` fallback until it
gets a dedicated state view. Neither `RenderPreparation` nor either component
takes an adapter argument — dispatch is entirely on `form.source`. All of this
lives in `lib/formentation/phoenix/`, behind the
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
the enclosing object's occurrence path. The definition finalizer rejects a
duplicate layout id across presentation objects, groups, and fields, while the
enclosing occurrence path distinguishes repeated collection items. `part` is
`control`, `container`, `help`, `errors`, or `option_<index>`. For fields,
`control` names the labelled/error-summary target when it is a control,
`container` names a composite widget's grouping element (such as a radio
fieldset), and `option_<index>` names one radio input. These are separate token
positions, so a field called `notes_help` and the help for `notes` cannot share
an id.

`DOMIdentity.field_options/3` mints a field's whole option-id list in one call,
so every renderer-owned field id comes from `DOMIdentity`. It indexes positions
only — option *values* never reach the id, so relabelling a choice in place
leaves the ids its controls already carry untouched.

The namespace moves when you render a subtree from its own form.
`dom_namespace!/2` resolves `form.id || form.name`, and a nested form's id is
the joined one, so the same field's renderer-owned id differs by which form
rendered it:

```
root   fields/1 → ftn--asset_payload--field--control--address--street
nested fields/1 → ftn--asset_payload_address--field--control--address--street
```

The Phoenix `name` is identical in both. Each plan is internally consistent —
labels, `aria-describedby`, and summary `href`s always agree within one plan —
so this is only a problem when the same subtree is rendered twice on one page.
That is the concrete reason to pass `dom_namespace:`.

Identity and namespace bytes are escaped byte by byte: ASCII letters, digits,
and `_` remain literal except that a leading digit is encoded; every other byte
is `-XX` with uppercase hexadecimal bytes. Therefore `--` appears only as the
token delimiter. The grammar preserves both path boundaries (`["a_b"]` versus
`["a", "b"]`) and segment type (`[0]` versus `["0"]`). Its output alphabet is
`[A-Za-z0-9_-]` and the `ftn` prefix makes it usable as an unescaped HTML/CSS
identifier in browser, Floki, and LazyHTML selectors.

The namespace is escaped too, so `asset-form` produces `asset-2Dform` while
`asset_form` stays readable; prefer a snake_case render namespace when readable
ids matter. `ftn-` remains the reference markup's class vocabulary
(`ftn-field`, `ftn-group`, and so on); `ftn--` is the distinct prefix for
renderer-minted ids.

The spelling is deliberately readable and stable: applications may use these
ids in tests, styles, and scripts. It changes only as a compatibility change.
The guarantee covers ids minted through this system within a render namespace;
it cannot prevent an application from manually writing the same id elsewhere
on the page. There is no hash, counter, traversal index, random value, or
occupied-id registry.

Projection resolves one namespace per render: explicit `dom_namespace`, then
`form.id || form.name`, otherwise an actionable error. It mints all identities
before markup: fields use absolute instance paths, objects use their own
occurrence paths, and presentation groups combine their layout id with the
enclosing object occurrence path. Whole-form and subtree projection therefore
prepare byte-identical ids for the same occurrence and namespace.

The reference components consume these prepared values verbatim. They do not
use `Phoenix.HTML.FormField.id` as a uniqueness contract or append `_help`,
`_errors`, or radio indexes. Phoenix names remain transport-authoritative;
renderer ids are the control/label/help/error/fieldset/summary relationship
surface. Groups render optional help with the already-prepared `GroupDOM.help`
identity; components never derive help IDs themselves.

## Reference components (`Formentation.Phoenix.Theme.Reference`)

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
2. Field help renders with a deterministic id and is linked from the control;
   group help uses its prepared deterministic id and is linked from the
   fieldset via `aria-describedby`.
3. Visible errors render with deterministic ids, linked via
   `aria-describedby` (composing with the help id); the control carries
   `aria-invalid`. Errors render only when `show_errors?`.
4. Groups render as `<fieldset>` with a `<legend>` (data-nesting and
   presentational groups, and radio groups). Data-nesting and presentation
   groups use prepared fieldset IDs and optionally render associated help.
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
- Options retain their declared scalar value. Themes emit each control value
  and compare it to the current form value through the same canonical string
  representation (`to_string/1`) for `selected`/`checked`; otherwise numeric
  or boolean options submit correctly but fail to re-mark after a round trip.
  [GitHub issue #38](https://github.com/kioopi/formentation/issues/38) owns
  source-level rejection of unsupported non-scalar declarations.
- A required boolean never renders the HTML `required` attribute on its checkbox — HTML `required` means must-be-*checked*, a different constraint than "always submits true or false", which the D-011 hidden input already satisfies.
- `:number_input` always renders `type="text"`, never `type="number"`: a real browser blocks a `<input type="number">` from *displaying* non-numeric raw text (and sanitizes an injected invalid value on the next round trip), which breaks raw-input preservation after a failed decode ([[18-decisions#D-021 — LiveView integration is wrappers plus a demo, not framework machinery|D-021]]). Its keyboard hint uses both prepared facts: integer fields use `inputmode="numeric"`; general-number fields use `inputmode="decimal"`. Browser coverage asserts those live-DOM attributes and raw-value preservation, not platform-dependent soft-keyboard layouts. `inputmode` is an ergonomic hint, not the transport grammar — the codec remains authoritative for signs, fractions, exponents, trimming, and invalid input ([[18-decisions#D-038 — Semantic value type and abstract widget are orthogonal prepared facts|D-038]]).
- Progressive-hint attributes (`required`, `min`/`max`/`step`,
  `minlength`/`maxlength`) come from step 5's `input_validations`; they are
  hints, never server validation. `min`/`max`/`step` are dropped for numeric
  semantic value types on `:number_input`, `:text_input`, `:textarea`, and
  `:select`: the first two render text controls, and textareas/selects do not
  accept those attributes. `:radio_group` follows its separate required-only
  policy. `required`, when present, survives.

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
