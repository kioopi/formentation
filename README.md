# Formentation

Formentation compiles declarative descriptions of forms (JSON Schema, plain Elixir data) into a stable, source-independent semantic definition, projects that definition against runtime state, and renders it through replaceable presentation systems — Phoenix first.

**Status: pre-release, under active development.** Phase 1 (walking skeleton) is in progress, and the round trip — including the LiveView lifecycle — now runs end to end.

`Formentation.compile/2` compiles plain Elixir data (`Formentation.Definition.Source.Map`) or a JSON Schema document — draft 2020-12, validated offline against the metaschema, with a UI-hints channel for ordering, presentation groups, and widget/help overrides (`Formentation.Definition.Source.JSONSchema`) — into a `Formentation.Definition` queried through `Formentation.Info`, with origin provenance on every resolved value, structured diagnostics, and depth/node guards. A differential test asserts both sources answer `Info` queries identically apart from origins. `Formentation.Form` holds runtime state with pure replace transitions, typed decode policies, whole-instance validation deferred while any decode fails, and derived submission blockers for preserve-only nodes. That state implements `Phoenix.HTML.FormData`, and `Formentation.Phoenix.fields/1` renders it as accessible HTML through a reference theme — composing inside a form you wrote yourself. `Formentation.Form.validate/2` is the `phx-change` entry point; `Formentation.Form.submit/2` is the ordinary `phx-submit` entry point and returns `{:ok, candidate, submitted_form}` only when the submitted state is application-ready, otherwise `{:error, submitted_form}` for redisplay. Run `mix demo` to see it live: a pump-inspection form at `/`, a nested-object form at `/nested`, both backed by the same LiveViews `test/formentation_demo/` exercises.

Remaining in Phase 1: collections. See [what isn't supported yet](docs/Formentation/Userguide/limitations.md) for the honest list.

**Using Formentation?** Start with the [user guide](docs/Formentation/Userguide/Userguide.md). **Working on it?** Start with the [end-to-end data flow](docs/Formentation/Techdocs/end-to-end-data-flow.md).

## Installation

Formentation is not yet published to Hex. Add it as a git dependency, pinned to a tag:

```elixir
def deps do
  [
    {:formentation, git: "https://github.com/kioopi/formentation.git", tag: "v0.1.0"}
  ]
end
```

Then fetch it:

```sh
mix deps.get
```

Its runtime dependencies (`jsv`, `phoenix_html`, `phoenix_live_view`, `vibe_kit`) are
all on Hex and resolve automatically.

## Concepts

A form passes through a small number of named stages:

- **Declaration** — what you write: a description of the form in some source vocabulary — plain Elixir data, or a JSON Schema document (draft 2020-12) with an optional UI-hints companion. See the [conceptual model](docs/Formentation/Planning/03-conceptual-model.md).
- **Source adapter** — a module implementing the `Formentation.Definition.Source` behaviour that compiles a declaration into a definition. `Formentation.Definition.Source.Map` is the reference adapter; `Formentation.Definition.Source.JSONSchema` compiles JSON Schema. See [source adapters](docs/Formentation/Techdocs/source-adapters.md).
- **Definition** — the compiled result: static semantic storage plus a presentation layout tree, queried through `Formentation.Info`. See [Definition and Node](docs/Formentation/Techdocs/definition-and-node.md).
- **Info** — the stable query surface. Renderers, tooling, and tests ask `Formentation.Info` questions (`fields/1`, `role/2`, `required?/2`, …) instead of pattern-matching definition internals.
- **Form state** — a definition paired with the data, params, and interaction history of one filling-in. Pure and Phoenix-free. See [form state and transitions](docs/Formentation/Techdocs/form-state-and-transitions.md).
- **Projection and rendering** — form state becomes an ordinary `Phoenix.HTML.Form`, which the projector turns into a render plan and the theme into HTML. See [rendering](docs/Formentation/Techdocs/rendering.md).
- **Diagnostics and origins** — compilation never fails silently or guesses invisibly: problems become `Formentation.Diagnostic` structs, and every resolved value records where it came from — a path into the source or a named inference rule. See [diagnostics and origins](docs/Formentation/Techdocs/diagnostics-and-origins.md).

Everything lives in [`docs/Formentation/`](docs/Formentation/Formentation.md), an Obsidian vault with four areas: `Planning/` (why and intended design), `Development/` (phase status), `Techdocs/` (what is actually built), and `Userguide/` (how to use it).

## Exploring in IEx

`iex -S mix` starts a console with helpers from [`.iex.exs`](.iex.exs) preloaded: `fixture/1` (a map declaration), `schema/1` and `ui_hints/0` (the same form as a decoded JSON Schema document plus a UI-hints document), `pump_inspection/0` (the [end-to-end example](docs/Formentation/Planning/17-end-to-end-example.md), read from the checked-in fixture files), and `compile!/2`, which picks the adapter from the declaration's shape, prints diagnostics, and returns the definition.

```elixir
iex> definition = compile!(schema(), ui: ui_hints())
iex> Info.fields(definition) |> Enum.map(&{&1.name, &1.role})
[{"name", :text}, {"email", :email}, {"newsletter", :boolean}]

iex> {:ok, email} = Info.presentation_at(definition, ["email"])
iex> email.widget
:email_input
```

Every resolved value knows where it came from — a JSON Pointer into the schema or hints document, or a named inference rule:

```elixir
iex> Info.origins(definition, ["email"])
[
  label: {:json_schema, "/properties/email/title"},
  role: {:json_schema, "/properties/email/format"},
  widget: {:ui_hints, "/fields/email/widget"},
  help: {:ui_hints, "/fields/email/help"}
]
```

Unsupported constructs degrade into structured diagnostics instead of failing the compile:

```elixir
iex> compile!(schema(%{"tags" => %{"type" => "array"}})) |> Info.diagnostics() |> Enum.map(& &1.code)
warning: unsupported type "array" for property "tags"
[:unsupported_type]
```

The same form compiles from either source with `Info`-equivalent answers (pinned by the differential test):

```elixir
iex> {schema, ui} = pump_inspection()
iex> compile!(schema, ui: ui) |> Info.role(["last_service"])
:date

iex> fixture([{"age", %{kind: :integer, min: 0}}]) |> compile!() |> Info.role(["age"])
:integer
```

## Form state

Transitions are pure and usable from IEx — no Phoenix required:

```elixir
{:ok, definition, []} =
  Formentation.compile(schema, adapter: Formentation.Definition.Source.JSONSchema, ui: ui_hints)

form = Formentation.Form.new(definition, %{"serial_number" => "PX-2044"})

form =
  Formentation.Form.transition(form, %Formentation.Params{
    values: %{"serial_number" => "PX-2044", "operating_hours" => "51o2"},
    event: :change
  })

Formentation.Form.candidate(form)
#=> :none — "51o2" failed to decode; no candidate instance exists (D-012)

Formentation.Form.field(form, ["operating_hours"]).display_value
#=> "51o2" — raw input is preserved for redisplay

Formentation.Form.issues(form, ["operating_hours"])
#=> [%Formentation.Issue{code: :invalid_integer, source: :decode}]
```

Absent keys in a replace transition clear their fields; `""` preserves
for strings and unsets typed controls; booleans ride the hidden-input
contract (`"true"`/`"false"`, never manufactured from absence).

## Rendering

Form state implements `Phoenix.HTML.FormData`, so it converts with the
ordinary `to_form/2`. The components render the form *body* — never a
`<form>` element — so a generated payload form composes inside a form you
wrote yourself, under its namespace:

```heex
<.form for={@asset_form} action={~p"/assets"} method="post">
  <.input field={@asset_form[:name]} label="Asset name" />

  <Formentation.Phoenix.fields form={@payload_form} />

  <button type="submit">Save</button>
</.form>
```

```elixir
payload_form = Phoenix.Component.to_form(form, as: "asset[payload]")
```

The built-in theme is deliberately unpolished markup with class hooks and
no CSS, implementing a tested accessibility contract: labelled controls,
`aria-describedby` help and errors, `aria-invalid`, fieldsets with
legends, a submit-gated error summary linking to its fields, no duplicate
ids, and HEEx-escaping of all schema-provided text. A pluggable theme API
is a later phase. See the [rendering guide](docs/Formentation/Userguide/rendering-with-phoenix.md) for the static half and the [LiveView guide](docs/Formentation/Userguide/using-with-liveview.md) for `phx-change`/`phx-submit`, or run `mix demo` to try both examples in a browser.

## Running the tests

```sh
mix test    # the suite: unit, property, and end-to-end example tests
mix test.dev # the development inner loop: format, then --stale-narrowed tests
mix ci      # full gate: compile with warnings-as-errors, format check, vault
            # wikilinks, docs with warnings-as-errors, tests, credo --strict,
            # dialyzer, duplication and architecture checks
mix test.browser # the [browser test suite](docs/Formentation/Techdocs/browser-testing.md)

```

Coverage reports come from [Six](https://hex.pm/packages/six): `mix six` for a summary, `mix six.html` for an annotated report.

## License

Formentation is released under the MIT License. See [LICENSE](LICENSE).
