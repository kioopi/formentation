---
title: Getting started
aliases:
  - Getting started
tags:
  - formentation
  - userguide
status: current
---

# Getting started

*Covers Formentation as of 2026-08-09. Every snippet below was run
against that version.*

This page walks the whole loop once: declare a form, compile it, render
it, take a submission, and read out decoded JSON. It uses the plain
Elixir declaration source, because it needs no files and no JSON
Schema knowledge. Everything here works in a plain Phoenix controller;
the same loop drives a LiveView too, with `Formentation.Form.validate/2`
and `Formentation.Form.submit/2` as the `phx-change`/`phx-submit` entry
points — see [[using-with-liveview|Using Formentation with LiveView]].

## Installing

Formentation is not yet on Hex. Add it as a git dependency pinned to a tag, then
`mix deps.get`:

```elixir
{:formentation, git: "https://github.com/kioopi/formentation.git", tag: "v0.1.0"}
```

Formentation requires Elixir ~> 1.20, and pulls in `phoenix_html`,
`phoenix_live_view`, and `jsv` (for JSON Schema) as required
dependencies.

## 1 · Declare the form

A declaration is a map with a `:kind`. Object properties are an
**ordered list** of `{name, spec}` tuples — ordering is data, not map
enumeration order, so what you write is what renders.

```elixir
declaration = %{
  kind: :object,
  required: ["email"],
  properties: [
    {"email", %{kind: :string, title: "Email address", role: :email, min_length: 3}},
    {"age", %{kind: :integer, title: "Age", min: 0}},
    {"subscribed", %{kind: :boolean, title: "Subscribe to the newsletter"}}
  ]
}
```

The full vocabulary is on [[declaring-with-the-map-source|the map source page]]. If you already have a JSON Schema, use
[[declaring-with-json-schema|that adapter]] instead — everything from
step 2 on is identical.

## 2 · Compile and initialize

The simplest path: compile the declaration and create a form in one call.

```elixir
{:ok, form, diagnostics} =
  Formentation.form(declaration, adapter: :map, data: %{"email" => "ada@example.com"})

diagnostics
#=> []
```

`Formentation.form/2` returns `{:ok, form, diagnostics}` on successful
compilation — `diagnostics` may carry warnings even on success — or
`{:error, diagnostics}` when the declaration cannot be compiled, in which
case no form is created.

The `adapter:` option is mandatory and selects your source:
- `:map` — plain Elixir declarations
- `:json_schema` — JSON Schema 2020-12 documents

There is no default and no inference: a plain map could be either a map
declaration or a decoded JSON Schema, so you always say which. A third
advanced route exists for supplying your own source — see
[[limitations#No extension points|what isn't supported yet]] for what it
does and does not promise.

A **bad `adapter:`** — one that is missing, unknown, or invalid — raises
`ArgumentError` immediately. This is different from a declaration that
fails to compile, which returns `{:error, diagnostics}` instead.

The `data:` option is the existing form data (defaults to `%{}` for a
blank form). To fill in declared defaults for absent keys, pass
`defaults: :apply` — see [[declaring-with-the-map-source#Defaults|the note on defaults]] before you do.

`data:` and `defaults:` are the initialization options; every other
option passes straight through to the adapter unchanged, so `:ui` for
JSON Schema, `:max_depth`, and `:max_nodes` all work through `form/2`
too.

`Formentation.Form` is the runtime state: the definition paired with the
data this particular form opened on. It is immutable and pure — no
process, no connection, no Phoenix. You can drive an entire interaction
from IEx.

### Two steps instead: compile once, reuse

If you compile a form declaration once and use it across many forms — at
application boot, in a module attribute, or behind a cache — split the
work in two steps:

```elixir
{:ok, definition, diagnostics} =
  Formentation.compile(declaration, adapter: :map)

form = Formentation.Form.new(definition, %{"email" => "ada@example.com"})
```

`Formentation.compile/2` returns the `Formentation.Definition` — a static,
inert description of the form that holds no values, no errors, and no DOM
ids. You can query what it compiled to, including where each resolved
value came from: see [[inspecting-definitions|Inspecting definitions]].

Because the definition is inert, one compiled definition can back any
number of forms: pair it with data through `Formentation.Form.new/3` as
often as you need. Its second argument is the existing data (defaults to
`%{}` for a blank form), and its `defaults: :apply` is the same option
`form/2` forwards.

## 3 · Render it

Convert the state into a Phoenix form and hand it to the `fields` component:

```heex
<.form for={@form} action={~p"/signup"} method="post">
  <Formentation.Phoenix.fields form={@form} />
  <button type="submit">Save</button>
</.form>
```

with the assigns prepared as:

```elixir
assign(conn, form: Phoenix.Component.to_form(form, as: "payload"))
```

The `as: "payload"` option namespaces every input. That produces:

```html
<div class="ftn-form">
  <div class="ftn-field">
    <label for="ftn--payload--field--control--email">Email address</label>
    <input type="email" id="ftn--payload--field--control--email" name="payload[email]"
           value="ada@example.com" required minlength="3">
  </div>
  <div class="ftn-field">
    <label for="ftn--payload--field--control--age">Age</label>
    <input type="text" inputmode="numeric" id="ftn--payload--field--control--age" name="payload[age]"
           value="">
  </div>
  <div class="ftn-field">
    <input type="hidden" name="payload[subscribed]" value="false">
    <input type="checkbox" id="ftn--payload--field--control--subscribed"
           name="payload[subscribed]" value="true">
    <label for="ftn--payload--field--control--subscribed">Subscribe to the newsletter</label>
  </div>
</div>
```

Three things to notice, because they are guarantees rather than
coincidences:

- **No `<form>` element.** `fields/1` renders the *body* only, so it
  composes inside a form you own — including one that already has its own
  fields and its own namespace. This is the point of the component's
  design.
- **Widgets were chosen for you.** `role: :email` became
  `type="email"`, `:integer` became a number input with `step="1"`, and
  `:boolean` became a checkbox. See
  [[rendering-with-phoenix#Which widget you get|widget resolution]].
- **The checkbox has a hidden partner.** An unchecked HTML checkbox
  submits nothing at all, which is indistinguishable from "the field
  wasn't on the page". The paired hidden input makes a boolean always
  submit `"false"` or `"true"`.

`required` and `minlength` come from your declaration, as browser hints
only — they are never a substitute for the server-side decoding and
validation in the next step.

## 4 · Handle the submission

Submitted params go through `Formentation.Form.submit/2`. It runs the
submit transition, then answers the application question directly:

```elixir
def create(conn, %{"payload" => params}) do
  case Formentation.Form.submit(form, params) do
    {:ok, instance, _submitted_form} ->
      save_it(conn, instance)

    {:error, submitted_form} ->
      render(conn, :new,
        form: Phoenix.Component.to_form(submitted_form, as: "payload")
      )
  end
end
```

The success branch carries the decoded JSON instance. The error branch
carries the exact submitted form state for redisplay, including raw
input, issue visibility, decode issues, validation issues, and blockers.
Persistence stays in your application; Formentation only classifies the
submitted data.

### What you get back

On success, the tuple's instance is the JSON object the form describes —
a **plain map**, with values decoded to their declared types:

```elixir
{:ok, instance, submitted_form} = Formentation.Form.submit(form, params)
instance
#=> %{"age" => 36, "email" => "ada@example.com", "subscribed" => false}
```

Note `36`, not `"36"`, and `false`, not `"false"`. That map is what you
persist; nothing downstream of the form has to know Formentation exists.

When submission fails, redisplay the returned submitted form. Inspect
`submission_status/1` only if you need to distinguish the reasons:

- `:undecodable` — some raw input could not decode, so there is no candidate.
- `{:blocked, blockers}` — a preserve-only unsupported node blocks submission.
- `{:invalid, issues}` — decoding succeeded, but validation found ordinary issues.

A candidate is materialization output, not permission to persist:
blockers can coexist with `candidate/1 == {:ok, map}` and an empty
ordinary issue list. Only the `{:ok, instance, submitted_form}` branch
means application-ready.

For an undecodable field, the returned form has no candidate:

```elixir
Formentation.Form.candidate(submitted_form)
#=> :none

Formentation.Form.issues(submitted_form) |> Enum.map(& &1.message)
#=> ["\"36x\" is not a valid integer"]
```

The all-or-nothing rule is deliberate: it stops one bad field from
producing a cascade of confusing follow-on errors from schema
validation.

### Re-rendering keeps what the user typed

Hand the returned submitted form straight back to `to_form/2` and render
again. The bad input is still there:

```elixir
Formentation.Form.field(submitted_form, ["age"]).display_value
#=> "36x"
```

A control that blanks itself when your entry is rejected is hostile, so
Formentation keeps the raw text and shows the error beside it. You do not
have to do anything to get this.

## What you now have

A complete round trip: declaration → definition → state → HTML →
params → decoded JSON. Everything except step 3 is plain Elixir with no
Phoenix involvement, which is why you can test steps 1–2 on their own from IEx.

## Where to go next

- [[declaring-with-the-map-source|Declaring a form with the map source]] — every key you can write
- [[declaring-with-json-schema|Declaring a form with JSON Schema]] — if your schema already exists
- [[rendering-with-phoenix|Rendering with Phoenix]] — groups, nested objects, widgets, accessibility
- [[limitations|What isn't supported yet]] — before you plan around any of this
- [[Userguide|Back to the guide index]]
