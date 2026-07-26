---
title: Declaring a form with JSON Schema
aliases:
  - Declaring a form with JSON Schema
  - JSON Schema source
tags:
  - formentation
  - userguide
  - sources
status: current
---

# Declaring a form with JSON Schema

*Covers Formentation as of 2026-07-26.*

`Formentation.JSONSchema` compiles a **decoded** draft 2020-12 schema
document — the map you get from `JSON.decode!/1`, with string keys — into
the same kind of definition the
[[declaring-with-the-map-source|map source]] produces. Presentation intent
that JSON Schema has no vocabulary for is supplied separately, as a
**UI-hints** document.

```elixir
schema = "schema.json" |> File.read!() |> JSON.decode!()
ui     = "ui.json"     |> File.read!() |> JSON.decode!()

{:ok, definition, diagnostics} =
  Formentation.compile(schema, adapter: Formentation.JSONSchema, ui: ui)
```

The `:ui` option is optional; without it you get structure only.

Use this source when the schema already exists — it is the case
Formentation was built for. Its one substantive advantage over the map
source is that it attaches a real **instance validator**, so submitted
data is validated against the schema, not just decoded.

## Two documents, on purpose

JSON Schema is a data-validation vocabulary. It can say a value is a
string of at least four characters; it cannot say the field goes third,
sits in a fieldset called "Electrical", and should be a textarea.

Rather than overload the schema with custom keywords, Formentation takes
presentation as a **separate document** applied after compilation. Your
schema stays a valid, portable schema that other tools can consume
unchanged.

```json
// schema.json — what the data is
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "title": "Pump inspection",
  "properties": {
    "serial_number": { "type": "string", "title": "Serial number", "minLength": 4 },
    "condition": { "type": "string", "title": "Condition",
                   "enum": ["good", "worn", "defective"] },
    "voltage": { "type": "number", "title": "Voltage (V)" },
    "notes": { "type": "string", "title": "Notes" }
  },
  "required": ["serial_number", "condition"]
}
```

```json
// ui.json — how it should look
{
  "order": ["serial_number", "condition", "electrical", "notes"],
  "groups": [
    { "id": "electrical", "title": "Electrical", "fields": ["voltage"] }
  ],
  "fields": {
    "notes": { "widget": "textarea", "help": "Visible to all technicians." }
  }
}
```

## The supported subset

Formentation implements a deliberately small slice of 2020-12. Anything
outside it degrades into a warning and an unsupported node — the form
still compiles, and the value at that key is preserved through
transitions rather than dropped.

### Supported

| Keyword | Effect |
| --- | --- |
| `type: "object"` | required at the root; nested objects nest data |
| `properties` | the fields |
| `required` | per object |
| `type` | `"string"`, `"integer"`, `"number"`, `"boolean"` |
| `title` | the label (humanized from the name when absent) |
| `description` | help text |
| `enum` | a fixed option set — **string members only** |
| `const` | a single-option field — **string values only** |
| `format` | `"date"`, `"email"`, `"uri"` become roles |
| `minLength`, `maxLength` | string constraints |
| `minimum`, `maximum` | numeric constraints |
| `default`, `examples` | annotations |

### Not supported

`$ref` (local or remote), `allOf` / `anyOf` / `oneOf`, `if` / `then` /
`else`, `arrays`, `patternProperties`, `additionalProperties`,
`dependentSchemas`, and every other composition or conditional keyword.
Numeric `enum`s and non-string `const`s are rejected as well —
[[18-decisions#D-005 — Scalar enums are fields, not choice nodes|option sets are string-only]]
for now.

A non-object root, a `$schema` that is not 2020-12, or a document that
fails the metaschema are **errors**: `compile/2` returns
`{:error, diagnostics}` and there is no definition.

> [!important] Unsupported declarations are preserve-only, not editable
> A property using an unsupported keyword compiles to
> `Formentation.Node.Unsupported`. Its original value survives every
> replace transition untouched — that preservation is the whole reason
> an edit form does not silently delete data it cannot represent — but
> the form can never decode, replace, or render it. Submitted params for
> that key are simply **never consulted**; they are not an escape hatch
> around the missing keyword, however plausible-looking the posted
> value is. If the property is `required` and currently absent from
> your data, or the preserved value currently fails your schema, the
> form becomes concretely non-submittable — see how that is detected and
> surfaced in
> [[form-state-and-transitions#Submission status is derived, not stored|Techdocs/Form state and transitions]].

> [!warning] Property order is not preserved
> JSON object keys are unordered by specification, so the adapter walks
> properties **alphabetically** to stay deterministic. A schema with no
> `order` hint renders its fields in alphabetical order, not the order
> they appear in the file. If order matters — and for a form it usually
> does — you must supply an `order` hint.

## The UI-hints vocabulary

The hints document has three optional top-level keys.

### `order`

A list of names setting the top-level render order:

```json
"order": ["serial_number", "condition", "electrical", "notes"]
```

> [!important] Order entries name *rendered* children, not fields
> Grouping happens before ordering. Once `voltage` is a member of the
> group `electrical`, it is no longer a top-level child — the *group* is.
> Listing `voltage` in `order` produces an `:unknown_order_entry`
> warning; list the group id `electrical` instead. This is the single
> most common hints mistake.

Names not mentioned in `order` keep their relative position after the
ones that are.

### `groups`

Presentation groups — a fieldset drawn around fields **without** nesting
their data:

```json
"groups": [
  { "id": "electrical", "title": "Electrical", "fields": ["voltage", "insulation_ok"] }
]
```

`id` and `fields` are required, `title` optional. The group takes the
position of its first member. `voltage` stays a top-level key in the
data and its input is still named `payload[voltage]` — for genuinely
nested data, use a nested object schema instead.

### `fields`

Per-field overrides, keyed by property name:

```json
"fields": {
  "notes":    { "widget": "textarea", "help": "Visible to all technicians." },
  "imported": { "read_only": true },
  "token":    { "hidden": true }
}
```

| Key | Meaning |
| --- | --- |
| `widget` | `"text"`, `"textarea"`, `"select"`, `"checkbox"`, `"radio"` |
| `help` | overrides the schema's `description` |
| `hidden` | render as a hidden input; still submitted |
| `read_only` | display only; submitted values discarded |

A `help` hint **replaces** the `description` as the source of the help
text, and the provenance says so:

```elixir
Formentation.Info.origins(definition, ["email"])
#=> [
#=>   label: {:json_schema, "/properties/email/title"},
#=>   role:  {:json_schema, "/properties/email/format"},
#=>   help:  {:ui_hints, "/fields/email/help"}
#=> ]
```

Every origin is a JSON Pointer into whichever document supplied the
value, which makes "why does this field look like that?" a question with
an exact answer.

> [!warning] Hints reach top-level fields only
> The hints post-pass does not recurse into nested objects. A hint naming
> a nested field like `bio` inside `profile` produces an
> `:unknown_hint_field` warning and is ignored — there is no path syntax
> for it yet. The map source has no such limit, because it expresses the
> same intent inline.

A malformed hints document is an **error** (`:invalid_ui_hints`) and
fails the compile before any work happens. Individual bad *entries* are
warnings: an unknown widget, a hint for a field that does not exist, a
group naming a missing member, a non-boolean `hidden`/`read_only`.

## Validation — what you do and don't get

The adapter compiles an instance validator from your schema and attaches
it to the definition. It runs on every transition, once every field has
decoded:

```elixir
{:error, submitted_form} =
  Formentation.Form.submit(form, %{"age" => "10"})

Formentation.Form.issues(submitted_form)
#=> [%Issue{path: %InstancePath{segments: ["age"]}, code: :minimum,
#=>         message: "value 10 is lower than minimum 18", source: :validation}]
```

Issues carry `source: :validation` for constraint violations and
`source: :decode` for values that could not be parsed into their type.
Missing required properties are reported **at the missing field's own
path**, so the field shows its own error instead of the parent object
being blamed.

> [!warning] `format` does not validate
> In JSON Schema 2020-12, `format` is an *annotation* by default, not an
> assertion. Formentation uses it to pick a role (and therefore a widget
> and an HTML input type), but a value like `"not-an-email"` in a
> `"format": "email"` field produces **no issue**. Use `pattern`-free
> alternatives or validate the returned candidate yourself if you need
> the guarantee. The `type="email"` attribute the browser gets is a
> client-side hint only, trivially bypassed.

Validation is also **deferred while any field fails to decode**: if an
integer field holds `"36x"`, you get the decode issue for that field and
no schema issues at all until it parses. This avoids a cascade of
type-violation noise on top of the real problem.

If the validator cannot be built — a dangling local `$ref`, or any
remote `$ref`, since fetching is disabled — you get a
`:validator_unavailable` warning and a definition with **no validation
at all**. Check for it rather than assuming validation is on.

## Reading diagnostics

```elixir
Enum.map(diagnostics, &{&1.severity, &1.code, &1.message})
#=> [
#=>   {:warning, :unsupported_type, "unsupported type \"array\" for property \"tags\""},
#=>   {:warning, :unknown_hint_field, "ui hints reference unknown field \"nope\""},
#=>   {:warning, :unknown_order_entry, "order references unknown field or group \"plan\""}
#=> ]
```

Codes specific to this source, beyond the shared ones described on
[[declaring-with-the-map-source#Reading diagnostics|the map source page]]:

- `:unsupported_type` — a property type outside the subset (warning), or
  a non-object root (error).
- `:unsupported_keyword` — a supported type with an unsupported
  refinement, such as a numeric `enum` or a non-string `const`.
- `:unsupported_dialect` — `$schema` is not draft 2020-12.
- `:invalid_schema` — the document fails the metaschema; the pointer in
  the diagnostic's origin locates the offending part.
- `:unknown_widget`, `:unknown_hint_field`, `:unknown_order_entry`,
  `:invalid_hint_value` — hint problems, all ignored rather than fatal.
- `:validator_unavailable` — see above.

## Related

- [[getting-started|Getting started]] — the whole loop
- [[declaring-with-the-map-source|Declaring a form with the map source]] — the inline alternative
- [[rendering-with-phoenix|Rendering with Phoenix]] — what these declarations render as
- [[limitations|What isn't supported yet]]
- [[Userguide|Back to the guide index]]
