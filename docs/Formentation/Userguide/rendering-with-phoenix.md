---
title: Rendering with Phoenix
aliases:
  - Rendering with Phoenix
tags:
  - formentation
  - userguide
  - phoenix
status: current
---

# Rendering with Phoenix

*Covers Formentation as of 2026-08-03. Every HTML fragment below represents
output from the version described; whitespace may be lightly reformatted for
readability.*

Formentation ships two function components and one built-in theme.
Rendering is a pure function of the definition and the form state — the
components choose nothing at render time that was not already decided
when the form was compiled or transitioned.

> [!note] What this page covers
> These components render identically in LiveView and in plain
> controller-rendered templates — rendering is a pure function of the
> definition and the form state either way. This page is about *what*
> gets rendered: widgets, groups, accessibility. Wiring
> `phx-change`/`phx-submit` and the handlers that drive a re-render are
> [[using-with-liveview|a separate page]].

## Getting a Phoenix form

`Formentation.Form` implements `Phoenix.HTML.FormData`, so it converts
with the ordinary `to_form/2`:

```elixir
form = Phoenix.Component.to_form(form_state, as: "payload")
```

The `:as` option namespaces every input beneath it. It is what lets a
Formentation form live inside a larger form you wrote by hand:

```elixir
to_form(form_state, as: "asset[payload]", id: "asset_payload")
# names become  asset[payload][serial_number]
# DOM ids become ftn--asset_payload--field--control--serial_number
```

Phoenix remains authoritative for submitted `name` values. Formentation owns
the ids emitted by its renderer: they are readable, collision-proof values
such as `ftn--asset_payload--field--control--serial_number`. Rendering resolves
their namespace from `dom_namespace`, then the Phoenix form's `id` or `name`;
it raises with guidance if none is available. Pass `dom_namespace="..."` to
either rendering component only when you need to override that DOM namespace;
it never changes submitted names.

`:action` and `:errors` are **owned by the form state** and raise if you
pass them — drive them through `Formentation.Form.transition/2` instead.

## The two components

### `fields/1` — the whole body

```heex
<.form for={@form} action={~p"/inspections"} method="post">
  <Formentation.Phoenix.fields definition={@definition} form={@form} />
  <button type="submit">Save</button>
</.form>
```

Renders the error summary followed by every field and group.

**It does not emit a `<form>` element.** That is deliberate and is the
component's defining property: the payload form is a *body*, so it
composes inside a form you own, alongside your own inputs:

```heex
<.form for={@asset_form} action={~p"/assets"} method="post">
  <.input field={@asset_form[:name]} label="Asset name" />

  <Formentation.Phoenix.fields definition={@definition} form={@payload_form} />

  <button type="submit">Save</button>
</.form>
```

### `field/1` — one subtree

```heex
<Formentation.Phoenix.field definition={@definition} form={@form} path={["address", "street"]} />
```

Renders a single field or nested object, addressed by its **instance
path** — the path a value has in the data, not the visual layout. Use it
when you want to interleave Formentation-rendered fields with your own
markup instead of taking the whole body at once.

Two things to know: presentation groups have no instance path and cannot
be addressed this way (they are visual, not structural); and an unknown
or unsupported path **raises**, so a typo fails loudly rather than
rendering nothing.

## Which widget you get

Resolution runs top to bottom, first match wins:

| # | Condition | Widget |
| --- | --- | --- |
| 1 | `hidden` | hidden input |
| 2 | an explicit `widget` that fits the field | that widget |
| 3 | an option set (`one_of` / `enum` / `const`) | select |
| 4 | boolean | checkbox |
| 5 | integer or number | number input |
| 6 | role `:date` / `:email` / `:uri` | date / email / url input |
| 7 | anything else | text input |

The widget set is `text_input`, `textarea`, `number_input`, `checkbox`,
`select`, `radio_group`, `date_input`, `email_input`, `url_input`, and
`hidden_input`.

A widget that cannot render the field it names — one outside that set, or
`checkbox` on a non-boolean — **falls back** to the inferred widget and
records a `:widget_fallback` diagnostic on the render plan rather than
raising. So a bad hint degrades the presentation; it never breaks the
page.

## What the markup looks like

Given a required email field with a minimum length:

```html
<div class="ftn-field">
  <label for="ftn--payload--field--control--email">Email</label>
  <input type="email" id="ftn--payload--field--control--email" name="payload[email]"
         value="ada@example.com" required minlength="3">
</div>
```

Presentation groups and nested objects both render as fieldsets:

```html
<fieldset id="ftn--payload--object--container--address" class="ftn-group"
          aria-describedby="ftn--payload--object--help--address">
  <legend>Address</legend>
  <p id="ftn--payload--object--help--address" class="ftn-group-help">
    Where the asset is installed.
  </p>
  <div class="ftn-field">
    <label for="ftn--payload--field--control--address--city">City</label>
    <input type="text" id="ftn--payload--field--control--address--city" name="payload[address][city]" value="">
  </div>
</fieldset>
```

The difference is invisible in the markup and decisive in the data: a
nested object's input is `payload[address][city]`; a presentation group's
member stays `payload[voltage]`.

The example is a nested object: Map `:help` and JSON Schema `"description"`
can supply its help through the built-in adapters. A native or prepared
presentation group that already carries help renders the same associated
markup, but the built-in Map `groups:` and JSON UI-group vocabularies do not
currently accept a public group-help key. Exposing that declaration capability
is separate future work.

The class names — `ftn-form`, `ftn-field`, `ftn-group`, `ftn-help`, `ftn-group-help`,
`ftn-errors`, `ftn-error-summary`, `ftn-radio-group`, `ftn-radio` — are
the styling hooks. There is no CSS in the package; style them yourself.

### Booleans carry a hidden partner

```html
<input type="hidden" name="payload[subscribed]" value="false">
<input type="checkbox" id="ftn--payload--field--control--subscribed" name="payload[subscribed]" value="true">
<label for="ftn--payload--field--control--subscribed">Subscribe to the newsletter</label>
```

An unchecked HTML checkbox submits nothing, which is indistinguishable
from "the field wasn't on the page". The hidden input makes an editable
boolean always submit `"false"` or `"true"`.

A required boolean deliberately gets **no** `required` attribute: in HTML
that would mean "must be checked", which is a different constraint from
"must always submit a value" — and the hidden input already guarantees
the latter.

### Read-only and hidden fields

```html
<input type="text" id="ftn--payload--field--control--locked" name="payload[locked]" value="from-db" readonly>
```

Read-only fields render `readonly` on text-like controls and `disabled`
on selects, checkboxes, and radio groups — with **no hidden mirror**.
The value is not resubmitted, and it does not need to be: the server
keeps the original regardless of what arrives.

```elixir
# a POST containing locked=hacked, against original %{"locked" => "from-db"}
Formentation.Form.candidate(form)
#=> {:ok, %{"locked" => "from-db", ...}}
```

That is a security property rather than a styling one. A read-only
boolean is a disabled checkbox *without* the hidden partner, since the
hidden-input contract binds editable checkboxes only.

Fields that are both hidden and read-only render nothing at all.

## Errors

Errors appear only once there is something to show them for. Given a
`:submit` transition with two schema violations:

```html
<div class="ftn-error-summary" role="alert">
  <h2>This form has errors</h2>
  <ul>
    <li><a href="#ftn--payload--field--control--age">Age: value 10 is lower than minimum 18</a></li>
    <li><a href="#ftn--payload--field--control--email">Email: value length must be at least 3 but is 1</a></li>
  </ul>
</div>
...
<div class="ftn-field">
  <label for="ftn--payload--field--control--age">Age</label>
  <input type="text" inputmode="numeric" id="ftn--payload--field--control--age" name="payload[age]" value="10"
         aria-describedby="ftn--payload--field--errors--age" aria-invalid="true" required>
  <ul id="ftn--payload--field--errors--age" class="ftn-errors">
    <li>value 10 is lower than minimum 18</li>
  </ul>
</div>
```

The **summary appears only after a `:submit`**. The same state rendered
after an `event: :change` transition shows the per-field errors but no
summary — because a summary that appeared mid-typing would be noise, and
one that appeared on submit is a navigation aid.

Per-field errors follow a different rule: they show on submit, or once
that particular field has been interacted with. You get this without
doing anything; the visibility decision is made before the theme runs, so
there is nothing to configure.

Errors are rendered with a deterministic id and linked from the control
via `aria-describedby`, composing with the help text's id when both are
present.

Integer and number fields deliberately render as `type="text"` with
`inputmode="numeric"`: browsers can otherwise refuse or sanitize a raw
non-numeric value after a failed decode. The renderer therefore preserves that
raw text instead of emitting non-conforming `min`, `max`, or `step` attributes.

## Accessibility

The built-in theme is written to a contract that is asserted by tests
against the rendered DOM, not merely intended:

1. Every control has a non-empty `<label for>` pointing at its id.
   Placeholder text is never the only label.
2. Field help has a deterministic id and is linked from its control; group
   help has a prepared deterministic id and is linked from its fieldset via
   `aria-describedby`.
3. Visible errors have deterministic ids, are linked via
   `aria-describedby`, and the control carries `aria-invalid`.
4. Groups — nested objects, presentation groups, and radio groups —
   render as `<fieldset>` with a `<legend>`. Nested-object and presentation
   groups can render associated help.
5. The error summary appears only after submit; each entry links to its
   control. Object-level errors that belong to no single field render
   without a link.
6. No duplicate DOM ids in a rendered document.
7. All schema-provided text — labels, help, option values, error
   messages — is HEEx-escaped. Nothing schema-derived is ever marked
   safe.

That last point matters if your schemas are authored by anyone other
than you: a `title` containing markup is escaped, not rendered.

## Styling and replacing the theme

There is no CSS. The theme is markup plus class hooks, and it is
deliberately unpolished — it exists to be correct and legible, not
pretty.

> [!warning] There is no theme API yet
> The components call the built-in theme directly. There is no theme
> parameter, no component registry, and no documented contract for
> writing your own. Style it with CSS against the class names above; if
> you need different markup today, your option is to build your own
> components on `Formentation.Info` and `Formentation.Form`. A real
> theme contract is planned for [[phase-3-extensibility|Phase 3]].

## Related

- [[getting-started|Getting started]] — the whole loop
- [[declaring-with-the-map-source|Declaring a form with the map source]] — where widgets and groups are declared
- [[using-with-liveview|Using Formentation with LiveView]] — mount, handlers, and error visibility under `phx-change`/`phx-submit`
- [[limitations|What isn't supported yet]]
- [[Userguide|Back to the guide index]]
