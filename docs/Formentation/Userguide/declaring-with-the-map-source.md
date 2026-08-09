---
title: Declaring a form with the map source
aliases:
  - Declaring a form with the map source
  - Map source
tags:
  - formentation
  - userguide
  - sources
status: current
---

# Declaring a form with the map source

*Covers Formentation as of 2026-08-07.*

`Formentation.Source.Map` takes a plain Elixir map. It has no
dependencies, no separate hints document, and no schema validation — you
write structure and presentation together, inline. It is the easiest
source to start with and the one to use when your form is defined in
Elixir rather than loaded from a JSON document. Its stable selector is
`:map` when passed to `compile/2` or `form/2`.

```elixir
{:ok, definition, diagnostics} =
  Formentation.compile(declaration, adapter: :map)
```

If your forms come from JSON Schema documents, use
[[declaring-with-json-schema|that adapter]] instead. Both produce the
same kind of definition — a test compiles shared fixtures through both
and asserts the results are identical apart from provenance — so nothing
downstream changes when you switch.

## The object

The root of a declaration, and every nested object, is a map with
`kind: :object`:

```elixir
%{
  kind: :object,
  title: "Pump inspection",
  help: "Filled in after every service visit.",
  required: ["serial_number"],
  properties: [
    {"serial_number", %{kind: :string}}
  ],
  groups: [%{id: "electrical", title: "Electrical", fields: ["voltage"]}]
}
```

| Key | Type | Meaning |
| --- | --- | --- |
| `:kind` | `:object` | required |
| `:properties` | ordered list of `{name, spec}` | the fields, **in render order** |
| `:required` | list of names | which of *this object's* own properties are required |
| `:title` | string | label / legend |
| `:help` | string | descriptive text |
| `:groups` | list of group maps | presentation grouping — see below |

**Properties are a list, not a map.** That is the one thing to get right.
Elixir maps have no reliable order, so a map of properties would render
in whatever order the runtime felt like. The `{name, spec}` list means
declaration order *is* render order, and it stays that way.

**`required` is per object.** A nested object declares its own; a name in
the root's `required` list only refers to the root's own properties.

## Fields

Every non-object property is a scalar field with a `:kind`:

```elixir
{"serial_number", %{kind: :string, title: "Serial number", min_length: 4}}
```

| Key | Applies to | Meaning |
| --- | --- | --- |
| `:kind` | all | `:string`, `:integer`, `:number`, or `:boolean` |
| `:title` | all | the label; without it, the label is humanized from the name |
| `:help` | all | help text, rendered and linked with `aria-describedby` |
| `:role` | all | semantic role — `:date`, `:email`, `:uri`, … — which drives the widget |
| `:widget` | all | force a specific control, overriding inference |
| `:one_of` | strings | a fixed option set; makes the field a select |
| `:default` | all | value used for absent keys, **opt-in only** |
| `:examples` | all | example values (a list) |
| `:hidden` | all | render as a hidden input, still submitted |
| `:read_only` | all | display only; submitted values are discarded |
| `:min_length`, `:max_length` | strings | constraints |
| `:min`, `:max` | numbers | constraints |

An unrecognised `:kind` does not fail the compile — it produces a warning
and an unsupported node, and the rest of the form still works:

```elixir
{"tags", %{kind: :array}}
# warning: unsupported kind :array for property "tags"
```

The value at such a key is *preserved* through transitions rather than
dropped, so a form that renders half a JSON document will not silently
delete the other half.

> [!important] Unsupported declarations are preserve-only, not editable
> A property with an unrecognised `:kind` compiles to
> `Formentation.Definition.Semantic.Unsupported`. Its original value survives every
> replace transition untouched — the preservation path that keeps an
> edit form from silently deleting data it cannot represent — but the
> form can never decode, replace, or render it, and submitted params for
> that key are never consulted; they are not an escape hatch.
>
> The map source attaches **no validator**, so a preserved opaque value
> can never be *declared* invalid — there is no `:unsupported_invalid`
> blocker without a `Formentation.Definition.ValidationPlan`
> ([[declaring-with-json-schema|the JSON Schema source]] is the one that
> can make that call). A `required: true` property that is unsupported
> still concretely blocks submission the moment the original data is
> missing it, though — see
> [[form-state-and-transitions#Submission status is derived, not stored|Techdocs/Form state and transitions]]
> for how that surfaces.

### Labels are inferred when you omit them

Without `:title`, the label is humanized from the property name —
`"serial_number"` becomes `"Serial number"`. The inference is recorded,
so you can always tell which labels you wrote:

```elixir
Formentation.Info.origins(definition, ["serial_number"])
#=> [role: {:inference, :string_default}, label: {:inference, :label_from_name}]
```

`{:inference, _}` means Formentation decided; `{:map_source, _}` means
you did.

### Roles and widgets

`:role` describes what a value *means*; the widget is derived from it.
Set the role and let the rendering layer choose:

```elixir
{"last_service", %{kind: :string, role: :date}}   # renders as <input type="date">
{"email", %{kind: :string, role: :email}}         # renders as <input type="email">
```

Without a `:role`, one is inferred: `:one_of` makes the field a
`:select`, otherwise the role follows the kind (`:text`, `:integer`,
`:number`, `:boolean`).

Use `:widget` only when you want to override that chain — the classic
case being a long string:

```elixir
{"notes", %{kind: :string, widget: :textarea, help: "Visible to all technicians."}}
```

Widget names the reference UI understands are listed in
[[rendering-with-phoenix#Which widget you get|Rendering with Phoenix]]. A
widget it cannot render falls back to the inferred one and records a
diagnostic rather than failing.

### Option sets

`:one_of` gives a field a fixed set of scalar values (strings, numbers, or booleans):

```elixir
{"condition", %{kind: :string, title: "Condition", one_of: ["good", "worn", "defective"]}}
```

On scalar fields (`:string`, `:integer`, `:number`, `:boolean`), option values must be scalars (`String.t()`, `number()`, or `boolean()`). Unsupported non-scalar values (such as maps, tuples, nested lists, atoms, or `nil`) fail compilation with an `:invalid_declaration` diagnostic. An explicit `one_of: nil` is treated as absent and emits an `:unsupported_keyword` warning; other non-list `:one_of` declarations fail compilation with an `:invalid_declaration` diagnostic.

The field's role becomes `:select` and it renders as a `<select>` — or as
a radio group if you set `widget: :radio`. The rendered select always
leads with a blank option, so an untouched field is visibly unanswered
rather than silently defaulting to the first choice.

### Constraints are hints, not validation

`:min_length`, `:max_length`, `:min`, and `:max` become HTML attributes
(`minlength`, `min`, `max`, …) for progressive enhancement.

> [!warning] The map source does not validate submitted data
> Constraints declared here are **not enforced on the server**. The map
> source attaches no instance validator, so a submitted value is decoded
> to the right type and then accepted, whatever its length or range.
> Only [[declaring-with-json-schema|the JSON Schema source]] validates
> instances. If you need server-side constraint enforcement today, use
> JSON Schema — or validate the returned candidate yourself.

Type decoding *is* always enforced: `"36x"` in an integer field produces
an issue and no candidate, regardless of source.

### Defaults

`:default` is not applied unless you ask for it:

```elixir
{"status", %{kind: :string, one_of: ["new", "old"], default: "new"}}

Formentation.Form.new(definition, %{}, defaults: :apply)
|> Formentation.Form.candidate()
#=> {:ok, %{"status" => "new"}}
```

Without `defaults: :apply` the candidate is `%{}` — the default is
declared, and rendered as a hint to you, but not written into data.

Defaults apply **only at initialization** — at `Form.new/3` with
`defaults: :apply`, or via `Formentation.form/2` with the same
`defaults: :apply` option — never on a transition, and never over a
provided value. That is what lets a user clear a field and have it stay
cleared; a default that reasserted itself on every change would be
impossible to override.

### Hidden and read-only

These two look similar and behave completely differently:

```elixir
{"token",   %{kind: :string, hidden: true}}      # submitted, invisible
{"imported", %{kind: :string, read_only: true}}  # visible, not submitted
```

- **`hidden: true`** renders `<input type="hidden">`. The value is still
  submitted and decoded normally.
- **`read_only: true`** renders a visible but non-editable control
  (`readonly` on text inputs, `disabled` on selects and checkboxes) and
  **excludes the field from the submission entirely**. Whatever arrives
  for it is discarded and the original value is kept.

That second rule is a security-relevant property, not a styling one: a
read-only field cannot be overwritten by a crafted POST, because
participation is decided by your declaration rather than by what the
browser sent. A field that is *both* hidden and read-only renders
nothing at all.

## Nested objects

A property whose spec is `kind: :object` nests, and its name becomes a
data key:

```elixir
{"address",
 %{
   kind: :object,
   title: "Address",
   required: ["city"],
   properties: [
     {"street", %{kind: :string}},
     {"city", %{kind: :string}}
   ]
 }}
```

Values land nested to match — `%{"address" => %{"city" => "Berlin"}}` —
and inputs are named `payload[address][city]`. Address a nested field by
its path:

```elixir
Formentation.Info.required?(definition, ["address", "city"])  #=> true
```

## Presentation groups

`:groups` draws a fieldset around fields **without** nesting their data:

```elixir
groups: [%{id: "electrical", title: "Electrical", fields: ["voltage", "insulation_ok"]}]
```

| Key | Meaning |
| --- | --- |
| `:id` | identifier, required |
| `:fields` | member property names, required |
| `:title` | the `<legend>`; optional |

The distinction from a nested object is the whole point: a group is
**purely visual**. `voltage` stays at the top level of the data and its
input is still named `payload[voltage]`. Use a group to organize a flat
payload, and a nested object when the data really is nested.

The group node takes the position of its **first member** in render
order, and the members move with it. A member name that does not exist
produces an `:unknown_group_field` warning and is ignored. Preserve-only
unsupported properties remain in the semantic definition, but they do not
create renderable group members.

## Reading diagnostics

Compilation reports what it could not do rather than failing:

```elixir
{:ok, definition, diagnostics} = Formentation.compile(declaration, adapter: :map)

Enum.map(diagnostics, &{&1.severity, &1.code, &1.message})
#=> [
#=>   {:warning, :unsupported_kind, "unsupported kind :array for property \"tags\""},
#=>   {:warning, :required_permits_empty,
#=>    "required property \"city\" permits an empty string; add minLength: 1 if non-empty input is intended"}
#=> ]
```

Warnings worth knowing about:

- `:unsupported_kind` — a `:kind` outside the four scalars and `:object`.
- `:invalid_hint_value` — `hidden`/`read_only` given a non-boolean; ignored.
- `:unknown_group_field` — a group naming a property that does not exist.
- `:required_permits_empty` — a required string that still accepts `""`.
  Add `min_length: 1` if you meant "must not be blank"; "required" alone
  only means the key must be present.
- `:reserved_property_name` — a property named `_csrf_token`, `_target`,
  `_persistent_id`, or starting with `_unused_`. These are stripped as
  transport metadata and would never reach your data. Rename the property.

An `:error` diagnostic means `compile/2` returned `{:error, diagnostics}`
and there is no definition — a malformed declaration, a missing `:kind`,
or an exhausted depth/node budget (defaults: depth 16, 1 000 nodes,
overridable with `:max_depth` and `:max_nodes`). These are **adapter
options**, so they pass through `form/2` unchanged.

## Related

- [[getting-started|Getting started]] — the whole loop
- [[declaring-with-json-schema|Declaring a form with JSON Schema]] — the same form from a schema document
- [[rendering-with-phoenix|Rendering with Phoenix]] — what these declarations render as
- [[limitations|What isn't supported yet]]
- [[Userguide|Back to the guide index]]
