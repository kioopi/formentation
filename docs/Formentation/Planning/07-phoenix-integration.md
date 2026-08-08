---
title: Phoenix Integration
tags:
  - formentation
  - phoenix
  - liveview
status: draft
---

# Phoenix integration

Phoenix is Formentation's first runtime and rendering environment. The
integration has three separable concerns:

1. projecting `%Formentation.Form{}` through `Phoenix.HTML.FormData`;
2. preparing a concrete, source-neutral view from a projected
   `%Phoenix.HTML.Form{}`;
3. rendering that prepared view through a Phoenix UI integration.

The permanent advanced path adapts an arbitrary `%Phoenix.HTML.Form{}` plus an
explicit definition and state view. First-class backing-state integrations
eventually wrap their state in `%Formentation.Form{}` and use the ordinary
projection path.

> [!important] Current architectural direction
> [[19-north-star-architecture|North-star architecture]] defines the ordinary
> `Definition`/`Form` path. [[20-renderer-ui-model|Renderer and UI model]]
> defines the target ownership boundary for preparation, UI integrations,
> capabilities, and themes. Concrete Phase 3 contracts remain provisional.

Relevant APIs are [Phoenix.HTML.Form](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html), [Phoenix.HTML.FormData](https://hexdocs.pm/phoenix_html/Phoenix.HTML.FormData.html), and Phoenix Component form helpers.

## JSON-backed `FormData`

An optional state struct might contain:

```elixir
%Formentation.Form{
  definition: definition,
  source: original_data,
  params: raw_params,
  value: decoded_value,
  issues: issues,
  action: :validate,
  valid?: false,
  private: %{}
}
```

Its `FormData` implementation must support:

- `to_form/2` for the root;
- field access through `input_value`, `input_validations`, and errors;
- nested object and collection forms through `to_form/4`;
- stable naming and IDs;
- submitted versus used/unused state: `form.params` keeps the Phoenix-compatible view (transport markers such as `_unused_*` preserved) so `Phoenix.Component.used_input?/1` works, while decoding consumes the normalized domain params ([[18-decisions#D-014 — Usage is a first-class interaction axis|D-014]]);
- hidden fields required for collection identity.

Use the existing implementations in [phoenix_ecto](https://github.com/phoenixframework/phoenix_ecto/blob/master/lib/phoenix_ecto/html.ex) and [AshPhoenix.Form](https://github.com/ash-project/ash_phoenix/blob/main/lib/ash_phoenix/form/form.ex) as behavioural references, not code to imitate mechanically.

## Params, values, and defaults

Maintain clear precedence:

1. submitted raw params determine displayed values after interaction;
2. decoded values support validation and domain access;
3. original data supplies values before submission;
4. UI initial-value policy may use schema annotations only when explicitly enabled.

JSON Schema's `default` is an annotation. It does not require a validator to insert a value. Formentation should not mutate data merely because `default` exists. A separate initialization policy can choose to apply defaults and record that decision.

## Decoding

Browser parameters are strings and maps of strings. JSON values include numbers, booleans, nulls, arrays, and objects. Decoding therefore precedes both validation and `FormData` conversion: the Phoenix form is a projection of already-decoded state, never the owner of decoding ([[18-decisions#D-009 — Form state separates transport from operation|D-009]]), and whole-instance validation defers while any field fails to decode ([[18-decisions#D-012 — Schema validation defers while any decode fails|D-012]]).

The codec layer should return path-aware issues rather than raising on ordinary malformed input:

```elixir
{:error,
 [%Formentation.Issue{
   source: :decode,
   instance_path: ["age"],
   code: :invalid_integer
 }]}
```

Preserve raw params so a failed number conversion does not erase what the user typed: `input_value` returns the raw attempted value when decoding failed ([[18-decisions#D-009 — Form state separates transport from operation|D-009]]).

## Widget transport

Phoenix markup is part of the transport protocol even though components do not
own decoding. Preparation must describe, and every UI must faithfully emit:

- primary and auxiliary control names and values;
- scalar, repeated/list, or structured cardinality;
- unchecked, absent, blank-option, and explicit-null behaviour;
- action/metadata controls that do not participate as ordinary data;
- environment usage markers such as `_unused_`.

The checkbox hidden `false` control is therefore a semantic invariant, not a
reference-UI detail. Multiple choices, placeholders, compound controls,
collections, and uploads require equivalent explicit contracts. Shared UI
conformance must render controls, feed their emitted params through `Form`, and
assert the decoded operation/candidate. The canonical ownership and test model is
[[20-renderer-ui-model#Widget transport contract|the widget transport contract]].

## Error mapping

Validator errors generally identify an instance location and schema keyword location. Phoenix expects errors attached to fields, conventionally as `{message, substitutions}` tuples.

The adapter should:

- retain the original structured issue;
- map the instance path to the appropriate nested form;
- attach object-level errors to the nearest meaningful group or form-level error list;
- handle required-property errors that may be reported at the parent object;
- retain branch-level errors without flooding every child field;
- expose translation-ready messages;
- keep every issue in state and let per-path usage plus `action` drive visibility — cross-field issues attach to a declared primary path, root issues show only after submit ([[18-decisions#D-014 — Usage is a first-class interaction axis|D-014]]).

See [[09-diagnostics-provenance-introspection#Submitted-instance issues|Submitted-instance issues]].

Renderer preparation uses an application-supplied translation facility to
convert visible structured issues into presentation-ready localized content.
Editing keeps raw `control_value` separate from localized/read-only
`display_value`; rerendering must never replace an invalid raw attempt with a
formatted value.

## State view

`%Phoenix.HTML.Form{}` carries values, names, IDs, input validations,
per-field errors, and `used_input?/1` params — everything projection needs
*except* three semantic facts an arbitrary `FormData` source cannot express
through those conventions. `Formentation.Phoenix.StateView` fills that gap,
dispatched as a protocol on `form.source`:

- `submitted?/2` — the source's semantic submit state, not "`form.action`
  equals a particular atom";
- `issue_visibility/3` — a source-owned visibility policy for issues at one
  absolute instance path, or `:default` to defer to the projector's
  Phoenix-compatible rule;
- `issues/2` — every issue the source can enumerate, normalized to
  `path`/`message`, or `:unavailable` when the source has no enumeration
  capability.

`@fallback_to_any` means a source with no dedicated implementation still
projects, through the conservative `Any` behaviour rather than a crash. No
public function — `Projector.project/2`, `project_at/3`, or either
component — takes an adapter argument; dispatch is entirely on
`form.source`. See [[18-decisions#D-027 — Projection reads semantic state through a StateView protocol|D-027]].

## Component API

The ordinary public component receives the Phoenix projection of a
`%Formentation.Form{}`:

```heex
<Formentation.Phoenix.fields form={@phoenix_form} />
```

The caller creates the projection through Phoenix's normal API and therefore
retains ownership of `as` and `id`:

```elixir
phoenix_form =
  Phoenix.Component.to_form(form_state,
    as: "asset[payload]",
    id: "asset_payload"
  )
```

`fields/1` derives both the definition and the projected subtree from the
Phoenix form's `%Formentation.Form{}` source. The component keeps a typed
`%Phoenix.HTML.Form{}` contract and can coexist with hand-written
`<.input field={@phoenix_form[:name]}>` calls.

The permanent low-level interoperability path remains explicit:

```heex
<Formentation.Phoenix.fields
  definition={@definition}
  form={@ecto_or_ash_phoenix_form}
/>
```

Phase 3 should add UI selection, prepared-view inspection, and individual
field/subtree rendering through progressive disclosure. Slots may be
appropriate for form-level actions, collection controls, or wrapper
customization. Avoid a slot API that forces callers to reimplement traversal,
issue association, or stable identity.

Rendering must compose *inside* an enclosing hand-written form: [[00-use-case|the motivating use case]] embeds a payload form in a page whose other inputs come from an Ecto changeset, so names, IDs, and error routing have to work under a parent namespace such as `asset[payload][...]`. The component API must not assume it owns the `<form>` element. See [[17-end-to-end-example#Rendering|the end-to-end example]].

## LiveView events

The renderer should not own business submission. A JSON-backed helper can provide conventional transitions:

```elixir
form = Formentation.Form.validate(form, params)
form = Formentation.Form.add_item(form, ["addresses"])
form = Formentation.Form.remove_item(form, ["addresses", {:id, item_id}])
```

But an Ash-backed view should continue using `AshPhoenix.Form.validate/2`, `add_form`, `remove_form`, and submission functions. The automatic renderer only needs the updated Phoenix form and definition.

## Accessibility

The default renderer should establish:

- deterministic label/input association;
- `aria-describedby` links for help and errors;
- fieldsets and legends for grouped choices;
- error summaries linked to fields;
- keyboard-operable collection actions;
- no use of placeholder as the only label.

UI integrations may change markup, but capability verification and conformance
tests must protect these semantics. A visual theme configures one UI; it does
not weaken the contract.

The stateless tier also supports controller/static rendering and ordinary HTML
POST. Without LiveSocket `_unused_` evidence, pristine forms hide issues and
submitted forms show them; progressive per-field visibility is unavailable
unless the caller provides equivalent usage state. Validation and submission
semantics remain unchanged.

## Security

- Never mark arbitrary schema text as safe HTML.
- Treat labels, descriptions, examples, enum titles, and diagnostics as untrusted content.
- Remote schema loading needs explicit network policy.
- UI visibility is not authorization.
- Apply normal Phoenix CSRF protections.
- Put limits on submitted nesting, collection length, and decoded bytes.

## Existing form engines

The renderer should work with a compatible `%Phoenix.HTML.Form{}` whenever possible. Engine-specific operations—relationship management, changeset actions, sparse collections, or persistence—remain with the engine.

This is essential for [[phase-5-ash-integration|Ash integration]].

## Related notes

- [[03-conceptual-model#Form state|Form state]]
- [[06-runtime-projection|Runtime projection]]
- [[20-renderer-ui-model|Renderer and UI model]]
- [[11-testing-strategy#Phoenix and component tests|Phoenix and component tests]]
- [[phase-1-walking-skeleton|Phase 1]]
- [[phase-5-ash-integration|Phase 5]]
