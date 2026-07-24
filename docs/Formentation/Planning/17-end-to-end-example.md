---
title: End-to-End Example
tags:
  - formentation
  - example
status: draft
---

# End-to-end example

One small form from [[00-use-case|the motivating use case]], followed through every layer: two declaration sources, the compiled definition as seen through `Info`, rendering, a validation round-trip, and submission. Everything here is a design sketch, not a frozen API — its purpose is to expose problems early and to serve as the first fixture set for [[phase-1-walking-skeleton|Phase 1]].

The example is a *pump inspection* payload attached to an `asset` record: flat expert-defined data with one presentation group.

## Source 1: JSON Schema plus UI hints

The expert-authored schema, stored in the database:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "title": "Pump inspection",
  "properties": {
    "serial_number": { "type": "string", "title": "Serial number", "minLength": 4 },
    "condition": { "type": "string", "title": "Condition", "enum": ["good", "worn", "defective"] },
    "last_service": { "type": "string", "format": "date", "title": "Last service" },
    "operating_hours": { "type": "integer", "title": "Operating hours", "minimum": 0 },
    "voltage": { "type": "number", "title": "Voltage (V)" },
    "insulation_ok": { "type": "boolean", "title": "Insulation test passed" },
    "notes": { "type": "string", "title": "Notes" }
  },
  "required": ["serial_number", "condition"]
}
```

The companion UI-hints document (a first, provisional draft of the vocabulary Phase 1 must define):

```json
{
  "order": ["serial_number", "condition", "last_service", "operating_hours", "electrical", "notes"],
  "groups": [
    { "id": "electrical", "title": "Electrical", "fields": ["voltage", "insulation_ok"] }
  ],
  "fields": {
    "notes": { "widget": "textarea", "help": "Visible to all technicians." }
  }
}
```

Note what the hints do: they impose an order (JSON object member order is not reliable data), they create a presentation group over *flat* payload fields, and they override one widget.

## Source 2: plain Elixir data

The same form declared through the core map source (working name `Formentation.Source.Map`), with no JSON Schema involved:

```elixir
%{
  kind: :object,
  title: "Pump inspection",
  required: ["serial_number", "condition"],
  properties: [
    {"serial_number", %{kind: :string, title: "Serial number", min_length: 4}},
    {"condition", %{kind: :string, title: "Condition", one_of: ["good", "worn", "defective"]}},
    {"last_service", %{kind: :string, title: "Last service", role: :date}},
    {"operating_hours", %{kind: :integer, title: "Operating hours", min: 0}},
    {"voltage", %{kind: :number, title: "Voltage (V)"}},
    {"insulation_ok", %{kind: :boolean, title: "Insulation test passed"}},
    {"notes", %{kind: :string, title: "Notes", widget: :textarea, help: "Visible to all technicians."}}
  ],
  groups: [%{id: "electrical", title: "Electrical", fields: ["voltage", "insulation_ok"]}]
}
```

Two instructive differences from JSON Schema: the property list is *natively ordered* (tuples in a list, not a map), and presentation facts can sit inline because there is no external standard to respect. Both sources must still compile to definitions that answer the queries below identically, apart from origins. That differential test is the point of having two sources — see [[18-decisions#D-004 — Two declaration sources from the start|D-004]].

## The compiled definition, through Info

```elixir
{:ok, definition, _diagnostics} =
  Formentation.compile(schema, adapter: Formentation.JSONSchema, ui: ui_hints)

Info.fields(definition) |> Enum.map(& &1.name)
#=> ["serial_number", "condition", "last_service", "operating_hours",
#    "voltage", "insulation_ok", "notes"]

Info.required?(definition, ["serial_number"])   #=> true
Info.role(definition, ["last_service"])          #=> :date
Info.role(definition, ["condition"])             #=> :select  (a field with fixed options — not a structural choice node)
Info.node_at(definition, ["voltage"]).group      #=> "electrical"

Info.origins(definition, ["notes"])
#=> [
#     widget: {:ui_hints, "/fields/notes/widget"},
#     role:   {:inference, :string_default},
#     label:  {:json_schema, "/properties/notes/title"}
#   ]
```

Origins here are the compact tags of the simplified Phase 1 provenance model ([[18-decisions#D-003 — Simplified provenance first|D-003]]); the full `Decision`/`explain` machinery arrives in [[phase-2-compiler-diagnostics|Phase 2]].

The widget layering is visible in `notes`: semantic role `:text` (inferred), abstract widget key `:textarea` (UI hint), concrete component chosen by the theme at render time. See [[03-conceptual-model#Renderer, theme, and widget|role → widget key → component]].

## Rendering

The payload form is embedded in the hand-written asset form, so field names are namespaced under the parent:

```heex
<.form for={@asset_form} phx-change="validate" phx-submit="save">
  <.input field={@asset_form[:name]} label="Asset name" />

  <Formentation.Phoenix.form
    definition={@definition}
    form={@payload_form}
    theme={MyApp.FormTheme}
  />
</.form>
```

Expected semantic structure (plain reference theme, styling elided):

```html
<div class="ftn-field">
  <label for="asset_payload_serial_number">Serial number</label>
  <input type="text" name="asset[payload][serial_number]" id="asset_payload_serial_number" value="" />
</div>

<div class="ftn-field">
  <label for="asset_payload_condition">Condition</label>
  <select name="asset[payload][condition]" id="asset_payload_condition">
    <option value=""></option>
    <option value="good">good</option>
    <option value="worn">worn</option>
    <option value="defective">defective</option>
  </select>
</div>

<!-- last_service, operating_hours ... -->

<fieldset class="ftn-group">
  <legend>Electrical</legend>
  <!-- voltage, insulation_ok -->
</fieldset>

<div class="ftn-field">
  <label for="asset_payload_notes">Notes</label>
  <textarea name="asset[payload][notes]" id="asset_payload_notes"
            aria-describedby="asset_payload_notes_help"></textarea>
  <p id="asset_payload_notes_help">Visible to all technicians.</p>
</div>
```

The fieldset renders a *presentation group*: it does not introduce a level of nesting in names, params, or the stored payload.

## A validation round-trip

The user edits, and `phx-change` delivers raw params:

```elixir
params = %{
  "serial_number" => "PX-104",
  "condition" => "worn",
  "last_service" => "2026-06-30",
  "operating_hours" => "51o2",        # typo: letter o
  "voltage" => "230",
  "insulation_ok" => "true",
  "notes" => ""
}
```

Decoding produces a partial value and a path-aware issue, preserving the raw text:

```elixir
form = Formentation.Form.validate(form, params)

form.issues
#=> [%Formentation.Issue{source: :decode, code: :invalid_integer,
#     instance_path: ["operating_hours"]}]

form.params["operating_hours"]  #=> "51o2"   (still displayed in the input)
```

> [!success] Decided: no candidate instance while decoding fails
> While `operating_hours` fails to decode there is no complete candidate instance, so whole-instance schema validation defers: no second `required`-style error can pile onto the decode issue, and the raw text never reaches the validator — [[18-decisions#D-012 — Schema validation defers while any decode fails|D-012]].

After the fix, submission decodes cleanly and the stored payload is flat JSON:

```json
{
  "serial_number": "PX-104",
  "condition": "worn",
  "last_service": "2026-06-30",
  "operating_hours": 5102,
  "voltage": 230.0,
  "insulation_ok": true,
  "notes": ""
}
```

Even this small example forced policy decisions, now recorded: `""` for `notes` is stored as `""` because the schema accepts it ([[18-decisions#D-010 — Empty-string, null, and absent-key decode policies|D-010]]); an unchecked checkbox submits an explicit `"false"` through the hidden-input transport contract ([[18-decisions#D-011 — Booleans use the hidden-input transport contract|D-011]]); both are global codec defaults, with per-field overrides deferred until a use case demands them.

## What this example is designed to expose

Each item links to where the question lives:

1. **Presentation group vs object container** — the fieldset nests markup but not data; `:group` currently conflates both meanings ([[16-open-questions#Core representation|open question]]).
2. **Enum as field, not structural choice** — `condition` is a field with options, reserving `:choice` for `oneOf`-style alternatives ([[18-decisions#D-005 — Scalar enums are fields, not choice nodes|D-005]]).
3. **Role → widget key → component layering** — visible in `notes` ([[03-conceptual-model#Renderer, theme, and widget|conceptual model]]).
4. **Ordering** — JSON needs an explicit order hint; the map source is natively ordered; the differential test must define what "same definition" means for order.
5. **Decode/validate interplay** — the `"51o2"` walkthrough above ([[18-decisions#D-012 — Schema validation defers while any decode fails|D-012]]).
6. **Embedding under a parent form** — names, IDs, and error routing under `asset[payload]` ([[00-use-case|requirement 5]]).
7. **Empty string, null, absent, and checkbox policy** — decided as typed global codec defaults ([[18-decisions#D-010 — Empty-string, null, and absent-key decode policies|D-010]], [[18-decisions#D-011 — Booleans use the hidden-input transport contract|D-011]]).
8. **Date handling** — `format: "date"` becomes role `:date`; the browser date input yields an ISO string, so the codec is near-identity but the *role* still matters for widget choice.

When Phase 1 implementation contradicts anything above, update this note — it is a fixture description, and fixtures must tell the truth.

## Related notes

- [[00-use-case|Motivating use case]]
- [[03-conceptual-model|Conceptual model]]
- [[phase-1-walking-skeleton|Phase 1 — Walking skeleton]]
- [[11-testing-strategy#Semantic fixtures|Semantic fixtures]]
- [[Formentation|Back to the entry point]]
