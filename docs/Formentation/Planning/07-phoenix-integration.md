---
title: Phoenix Integration
tags:
  - formentation
  - phoenix
  - liveview
status: draft
---

# Phoenix integration

Phoenix is Formentation's first runtime and rendering environment. The integration has three separable concerns:

1. JSON-backed state that implements `Phoenix.HTML.FormData`;
2. adapting an existing `%Phoenix.HTML.Form{}` to runtime projection;
3. rendering a `RenderPlan` with Phoenix components.

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

## Component API

A basic public component could be:

```heex
<Formentation.Phoenix.form
  definition={@definition}
  form={@form}
  theme={MyApp.FormTheme}
/>
```

Advanced users should be able to render subtrees or override individual nodes:

```heex
<Formentation.Phoenix.field
  definition={@definition}
  form={@form}
  path={["email"]}
/>
```

Slots may be appropriate for form-level actions, collection controls, or wrapper customization. Avoid a slot API that forces callers to reimplement traversal.

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

Themes may change markup, but capability verification and contract tests should protect these semantics.

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
- [[11-testing-strategy#Phoenix and component tests|Phoenix and component tests]]
- [[phase-1-walking-skeleton|Phase 1]]
- [[phase-5-ash-integration|Phase 5]]

