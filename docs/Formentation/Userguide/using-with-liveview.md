---
title: Using Formentation with LiveView
aliases:
  - Using Formentation with LiveView
  - LiveView
tags:
  - formentation
  - userguide
  - liveview
  - phoenix
status: current
---

# Using Formentation with LiveView

*Covers Formentation as of 2026-07-24. Every code sample below is either
lifted verbatim from the runnable demo (`demo/formentation_demo/`,
exercised by `test/formentation_demo/`) or was executed directly against
this version before being written down.*

Formentation's LiveView integration is two thin wrapper functions —
`Formentation.Form.validate/2` and `Formentation.Form.submit/2` — over
the same `transition/2` [[getting-started|Getting started]] already
uses for a plain controller. There is no LiveView-specific module, no
`use` macro, and no generated `handle_event` clauses: a LiveView handler
calls one of the two functions and re-projects the result, exactly like
a controller re-renders after a POST.

Everything on this page also runs live: `mix demo` serves a
pump-inspection form at `/` (embedded in a hand-written parent form) and
a nested-address form at `/nested` (no parent, so nested names and
nested error placement show without a presentation group in the way).
Its LiveViews — `demo/formentation_demo/pump_inspection_live.ex` and
`demo/formentation_demo/nested_live.ex` — are covered by
`test/formentation_demo/`, and the snippets below are lifted from them
rather than invented for this page.

## Mount: compile once, build the form, project it

```elixir
@impl true
def mount(_params, _session, socket) do
  {:ok, definition, _diagnostics} =
    Formentation.compile(PumpInspection.json_schema(),
      adapter: Formentation.Definition.Source.JSONSchema,
      ui: PumpInspection.ui_hints()
    )

  {:ok,
   socket
   |> assign(
     definition: definition,
     asset_form: to_form(%{"name" => "Pump 7"}, as: :asset),
     submitted: nil
   )
   |> assign_payload(Form.new(definition, PumpInspection.initial_data()))}
end
```

paired with a private helper that does the `Formentation.Form` →
`Phoenix.HTML.Form` projection every handler below calls back into:

```elixir
defp assign_payload(socket, form_state) do
  assign(socket,
    form_state: form_state,
    payload_form: FormData.to_form(form_state, as: "asset[payload]", id: "asset_payload")
  )
end
```

(`FormData` is `Phoenix.HTML.FormData`, called directly here instead of
through `Phoenix.Component.to_form/2` — they are equivalent; the demo
already has the alias in scope.) `assign_payload/2` is not a special
LiveView concept — it is the same "hold the form state, and separately
project it whenever it changes" step
[[getting-started|Getting started]] shows for a controller. LiveView's
only addition is doing it once in `mount/3` too, so the first render
already has a `Phoenix.HTML.Form` to hand to
`Formentation.Phoenix.fields/1`.

A LiveView that compiles on every mount rather than once at boot could
use `Formentation.form/2` instead of the `compile/2` + `Form.new/3`
pattern above — it combines both steps and is simpler when you don't need
the intermediate definition to cache or inspect. See
[[getting-started|Getting started]] for an example.

## Handlers: `validate/2` on change, `submit/2` on submit

```elixir
@impl true
def handle_event("validate", %{"asset" => asset_params}, socket) do
  {:noreply,
   socket
   |> assign(:asset_form, to_form(Map.delete(asset_params, "payload"), as: :asset))
   |> assign_payload(Form.validate(socket.assigns.form_state, payload_params(asset_params)))}
end

def handle_event("save", %{"asset" => asset_params}, socket) do
  case Form.submit(socket.assigns.form_state, payload_params(asset_params)) do
    {:ok, candidate, submitted_form} ->
      {:noreply,
       socket
       |> assign(:submitted, candidate)
       |> assign_payload(submitted_form)}

    {:error, submitted_form} ->
      {:noreply,
       socket
       |> assign(:submitted, nil)
       |> assign_payload(submitted_form)}
  end
end
```

wired from the template with the ordinary `phx-change`/`phx-submit`
attributes:

```heex
<.form for={@asset_form} id="asset-form" phx-change="validate" phx-submit="save">
  ...
  <Formentation.Phoenix.fields form={@payload_form} />
  <button type="submit">Save</button>
</.form>
```

`Form.validate/2` is sugar over `transition/2` with `event: :change` and
returns the changed form state. `Form.submit/2` runs the corresponding
`:submit` transition, then returns `{:ok, candidate, submitted_form}` only
when `submission_status/1` is `:ready`; undecodable, blocked, and invalid
submissions return `{:error, submitted_form}` for redisplay. Hand both
functions the raw params subtree Phoenix already gave you: no
`%Formentation.Params{}` envelope to build yourself in ordinary handlers.

### Under embedding, pluck your subtree first

When the payload lives inside a hand-written parent form — the
pump-inspection example's `asset[name]` / `asset[payload][...]` shape —
the event params arrive one level deeper than `validate/2`/`submit/2`
expect, since each wants the payload's own subtree. Extracting it is the
handler's job, one line:

```elixir
defp payload_params(asset_params), do: Map.get(asset_params, "payload", %{})
```

used above as `Form.validate(socket.assigns.form_state,
payload_params(asset_params))`. The nested example (`NestedLive`) has no
parent form, so its handler needs no plucking at all — it hands
`payload` straight through:

```elixir
@impl true
def handle_event("validate", %{"payload" => payload}, socket) do
  {:noreply, assign_payload(socket, Form.validate(socket.assigns.form_state, payload))}
end
```

Formentation does not know or care whether it is embedded; the pluck is
plain params-map code you write, not an API Formentation exposes.

## The two rules

Two things the components and the `FormData` projection actively
enforce, both already noted on
[[rendering-with-phoenix|Rendering with Phoenix]] and worth restating
here because LiveView is where breaking them is tempting.

**1. Drive `action` only through transitions.**
`Phoenix.Component.to_form(form, action: :submit)` raises — `:action`
and `:errors` are owned by `Formentation.Form` state, not options a
caller can set on the projected `Phoenix.HTML.Form`:

```
** (ArgumentError) the :action option is owned by Formentation.Form state; drive it through Formentation.Form.transition/2 instead
```

`form.action` becomes `:change` or `:submit` only because
`Form.validate/2`/`Form.submit/2` set it, which is what makes error
visibility (below) a property of the form state itself rather than
something a template can accidentally short-circuit.

**2. Re-project after every transition.**
`Formentation.Phoenix.RenderPlan` is a pure function of the definition
and the *current* `Phoenix.HTML.Form` — every `handle_event` above ends
by calling `assign_payload/1` again on the post-transition form state,
exactly like a controller re-renders after a POST. There is no
incremental update path; a handler that assigned the new form state
without re-projecting would keep rendering the old plan.

## Error visibility, as the user experiences it

The gating rule itself — per-field errors show on submit or once a
field is used, the summary shows only on submit — is
[[rendering-with-phoenix#Errors|described on the rendering page]] and
does not change under LiveView. What LiveView changes is *when* each
event fires:

- **`phx-change`** fires as the user edits the form. A real browser
  marks the fields the user has never interacted with as
  `_unused_<name>` in the event payload, and Formentation reads that
  marker to decide which fields the user has actually touched — so only
  the field being edited (plus anything touched earlier) shows its error
  while the rest of the form stays quiet.
- **`phx-submit`** fires once, and opens the submit gate: every stored
  issue becomes visible, including the object- and root-level ones that
  never show on a lone `:change`, plus the error summary with a link to
  each field.

> [!warning] `Phoenix.LiveViewTest` does not send `_unused_` markers
> That marker convention is applied by LiveView's client-side JS before a
> real request ever reaches the server — it is not something
> `Phoenix.HTML.FormData` or the server produces. `Phoenix.LiveViewTest`'s
> `form/3` plus `render_change/1`/`render_submit/1` instead re-serialize
> the *entire* rendered form on every call, as ordinary provided keys with
> no `_unused_` marker at all. In a `Phoenix.LiveViewTest`-driven test
> every field in a full-form change is therefore `:used` from the first
> event, whether or not a real browser would have sent it that way. This
> is real, verified behavior — the demo's own test suite pins it
> deliberately (`test/formentation_demo/pump_inspection_live_test.exs`,
> describe `"phx-change"`) — not a simplification for this page. Keep it
> in mind when writing your own `Phoenix.LiveViewTest` assertions.

One more honest detail: the error summary renders at the **top of the
Formentation fields block**, not the top of the page. If your template
puts hand-written inputs — like the pump-inspection example's
`asset[name]` — before `<Formentation.Phoenix.fields .../>`, the summary
appears mid-page, after those inputs. There is no slot to reposition it
today.

## Running the demo

```sh
mix demo        # http://localhost:4000
mix demo 4001   # or any other port
```

Two routes, `FormentationDemo.PumpInspectionLive` at `/` and
`FormentationDemo.NestedLive` at `/nested`:

- **`/`** — the pump-inspection form embedded inside a hand-written
  `asset` form (`asset[name]` plus the Formentation-rendered
  `asset[payload][...]` body). It opens with some readings already
  filled in and the two required identity fields blank, so you can watch
  error-visibility gating live: edit an unrelated field and only that
  field's error (if any) appears; hit Save with the identity fields
  still blank and the summary shows up with everything.
- **`/nested`** — a `title` plus a data-nesting `address` object
  (`payload[address][street]`, `payload[address][number]`), no parent
  form. The one place to see nested names and nested error placement
  without a presentation group's flat names in the way.

Both pages render the decoded candidate as JSON in a `<pre>` once
`Form.submit/2` returns the `:ok` branch. A failed submit clears that
output and redisplays the returned submitted form.

### The "Native browser validation" toggle

The pump-inspection page (`/`) opens with a checkbox above the form,
labeled "Native browser validation" and checked by default. It flips
`novalidate` on `<.form>`. Checked (the default), the reference theme's
HTML5 `required`/`minlength` attributes do their normal job: a browser
blocks a Save click on a blank required field before it is ever sent, and
you see the browser's own native error bubble. Uncheck it and Save again
with the same blank fields — the click now reaches the server, and you
see Formentation's own submit-gated error summary instead. It is a small,
deliberate demonstration of a real trade-off: native validation is kept as
a genuine feature, but it can pre-empt Formentation's own validation and
accessible summary before a submit is ever sent — see
[[18-decisions#D-023 — The demo keeps native validation, behind a toggle|D-023]]
for why both are kept, and toggled rather than one being dropped.

## Browser-tested end to end

Everything on this page — the `_unused_` gating described above, the
number widget's raw-text preservation, and clicking through to a focused
control from the error summary — is also pinned by a small suite that
drives this same demo through a real Chromium browser instead of
`Phoenix.LiveViewTest`, because `Phoenix.LiveViewTest` cannot observe
those specific truths (see the warning above, and
[[browser-testing|Browser testing]] for the full internals).
It is opt-in, not part of `mix ci`, and does need a one-time toolchain
setup:

```sh
mise install                    # once per clone: pins Elixir/Erlang/Node/Playwright
mise run playwright-browsers    # once per machine: downloads the Chromium build
                                 # (Arch Linux: no --with-deps; that flag installs
                                 # system packages via apt/dnf and has no Arch backend)
mix test.browser                # runs the four browser tests
```

If Playwright lives somewhere `mise where npm:playwright` cannot find (a
non-mise install, a container image with its own layout), point at it
directly instead: `PHX_TEST_PLAYWRIGHT_ASSETS_DIR=/path/to/playwright/lib
mix test.browser`.

## Related

- [[getting-started|Getting started]] — the same loop, one HTTP request at a time
- [[rendering-with-phoenix|Rendering with Phoenix]] — widgets, groups, and the error contract this page's gating rests on
- [[browser-testing|Browser testing]] (Techdocs) — internals of the Playwright suite mentioned above
- [[limitations|What isn't supported yet]]
- [[Userguide|Back to the guide index]]
