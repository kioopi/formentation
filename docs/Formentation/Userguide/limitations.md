---
title: What isn't supported yet
aliases:
  - What isn't supported yet
  - Limitations
tags:
  - formentation
  - userguide
  - limitations
status: current
---

# What isn't supported yet

*Accurate as of 2026-08-07. Formentation is pre-release; this page is the
one to re-read after every upgrade.*

Formentation is being built as a walking skeleton — a thin slice through
every layer first, widened afterwards. That means the parts that exist
work end to end, and the parts that do not are *absent*, not
half-finished. This page is the honest list, so you can tell before
investing which side of that line your use case falls on.

## The big ones

### No collections or arrays

There is no support for arrays of anything — not scalars, not objects.
An `array` property compiles to an unsupported node with a warning, and
the form renders around it. There is no add/remove/reorder UI, no item
identity, and no indexed paths.

This is the largest gap. If your forms are mostly repeating rows,
Formentation cannot do the job today.

The value at an array key is **preserved** through transitions rather
than deleted, so a form over a document containing arrays will not
destroy them — it simply cannot edit them.

That compile-time warning is a **static capability** fact, not a
verdict on any concrete instance: it means "this form can never decode,
replace, or render this property," and says nothing about whether the
data currently at that key happens to be fine. Two runtime functions
turn the static fact into a concrete answer:

- `Formentation.Info.unsupported_nodes/1` lists every such property in a
  *definition*, before any instance exists — useful for an application
  that wants to reject a schema needing full edit capability (an array
  users must be able to add rows to) up front, instead of discovering
  the gap when a form for it ships.
- `Formentation.Form.submission_status/1` (and `submission_blockers/1`)
  answer the *instance*-level question: can this particular form,
  loaded with this particular data, actually submit right now? A
  `required` array that is currently missing, or preserved array data
  that currently fails your JSON Schema validator, makes the form
  concretely non-submittable (`{:blocked, [...]}`) — there is no way for
  the form to fix either case. A form whose array data is present and
  valid submits normally, indefinitely; carrying an unsupported node
  does not by itself make a form permanently unsubmittable.

There is no `unsupported: :error` (or similar) compile option to reject
a definition outright for containing unsupported nodes. That policy
decision is left to the application, built on `Info.unsupported_nodes/1`
as the extension point —
[[18-decisions#D-028 — Unsupported nodes are a preserve-only capability; blocking is derived at runtime|D-028]].

### LiveView is wrappers, not a framework

`Formentation.Form.validate/2` and `Formentation.Form.submit/2` are the
whole LiveView surface. `validate/2` is the form-returning `phx-change`
transition; `submit/2` runs the `phx-submit` transition and returns the
success-or-redisplay decision, described on
[[using-with-liveview|Using Formentation with LiveView]]. There is no
`use` macro, no generated LiveView, no LiveComponent, no automatic
mount/handler wiring, and no upload support: you write `mount/3` and
`handle_event/3` yourself, exactly as you would without Formentation.

### No UI API

The components render through a single built-in UI, called directly.
There is no UI parameter, no component registry, and no documented
contract for writing your own. You can style the markup with CSS against
its class names; you cannot swap the markup.

### No extension points

No custom node kinds, no custom codecs or per-field codec overrides, no
compiler passes, no widget registration. Third-party adapters can be
passed to `compile/2` and `form/2` as modules, and the adapter-selection
mechanism is public and supported. `Formentation.Source` is documented so
the contract the built-in adapters satisfy is readable — but documented is
not the same as stable to build against. The internals required to
construct a valid `Formentation.Definition` are not a compatibility-stable
surface, so writing a third-party adapter remains an unsupported activity
that may break across versions.

## By area

### Declaration sources

**Both sources.** Only four scalar types — string, integer, number,
boolean — plus nested objects. Option sets are string-valued only.

**JSON Schema.** The supported subset is small and deliberate: no `$ref`
(local or remote), no `allOf`/`anyOf`/`oneOf`, no `if`/`then`/`else`, no
arrays, no `patternProperties`, no `additionalProperties`, no
`dependentSchemas`. Remote reference fetching is disabled by design.

Three specific behaviours regularly surprise people:

- **`format` does not validate.** It picks a role and therefore a widget,
  but `"not-an-email"` in a `"format": "email"` field produces no error.
  In 2020-12 `format` is an annotation, not an assertion.
- **Property order is alphabetical** without an `order` hint, because
  JSON object keys are unordered.
- **UI hints reach top-level fields only.** A hint naming a field inside
  a nested object is ignored with a warning; there is no path syntax for
  it yet.

**Map source.** No instance validation at all. Constraints you declare
(`min_length`, `min`, …) become browser attributes but are **not enforced
on the server**. Type decoding is always enforced; nothing else is. If
you need server-side constraint enforcement, use JSON Schema or validate
the candidate yourself.

### Runtime and state

**Replace transitions only.** Every transition replaces the whole form's
state from the submitted params. Partial (`:patch`) transitions and
scoped (sub-tree) transitions are reserved shapes in the API that raise
if you use them.

**A bare params map is refused.** `transition/2` requires a
`Formentation.Form.Params` envelope, because an absent key is ambiguous
between "cleared" and "untouched".

**All-or-nothing candidates.** If any field fails to decode, there is no
candidate at all and schema validation is skipped entirely until it
parses. This is intentional — it prevents one bad field from cascading
into confusing type errors — but it means you cannot get a partial
result out of a partly-invalid form.

**Defaults are opt-in and initialization-only.** They apply at
`Form.new/3` with `defaults: :apply` (or via `Formentation.form/2` with
the same `defaults: :apply` option), never on a transition, and never
over a value you provided.

### Rendering

Two edge cases in the error summary are known and recorded rather than
handled, both reachable only from schema-backed sources:

- an error on a field that is **both** hidden and read-only never renders
  a node, so it is absent from the summary;
- an error on a merely-hidden field produces a summary link pointing at a
  hidden control;
- the summary renders at the top of the Formentation fields block, not
  the top of the page — an embedded payload form (the common LiveView
  shape) shows it mid-page when hand-written inputs precede it. There is
  no slot to reposition it yet.

Behavioural widgets — file uploads, async option search, anything driven
by a JS hook — are not supported and are not yet designed for. The render
model describes pure, render-time widgets only.

### Diagnostics and introspection

Diagnostics carry a code and a developer-facing message; there is no
stable code registry, no user-facing formatter, no grouping, and no
deduplication. Origins record the *winning* source of each resolved
value, not the full history of how it was decided — there is no
`explain` API yet.

### Packaging

Not yet published to Hex. Install it as a git-URL dependency pinned to a
tag — see [[getting-started#Installing|Getting started]] for the dependency line.

The API is **not stable**. Function signatures, struct shapes, and
diagnostic codes may all change before a release.

## What does work end to end

For balance, the complete list of what you can rely on today:

- compiling from plain Elixir maps or JSON Schema 2020-12, with both
  proven to produce identical definitions by a differential test;
- compiling and initializing in one step with `Formentation.form/2`, or
  compiling once with `compile/2` and reusing that definition across many
  forms through `Form.new/3`;
- querying the result through `Formentation.Info`, including full
  provenance for every resolved value;
- nested objects and presentation groups;
- hidden and read-only fields, with participation decided by the
  declaration rather than by what the browser sends;
- typed decoding with explicit empty-string, absent-key, and boolean
  policies;
- whole-instance schema validation (JSON Schema source);
- rendering as accessible HTML that composes inside a form you own, with
  a tested accessibility contract;
- keeping raw invalid input visible after a failed decode;
- a LiveView lifecycle — `phx-change`/`phx-submit` through
  `Form.validate/2`/`Form.submit/2`, embedding under a parent form, and
  `_persistent_id` handled as transport metadata — exercised by a
  runnable demo (`mix demo`), see
  [[using-with-liveview|Using Formentation with LiveView]].

## Where this is going

Named phases and their intent are in [[Development]]; the decision log
behind the current shape is [[18-decisions|Planning/18 — Decisions]].
Neither is a commitment or a schedule.

## Related

- [[getting-started|Getting started]]
- [[declaring-with-json-schema|Declaring a form with JSON Schema]]
- [[rendering-with-phoenix|Rendering with Phoenix]]
- [[using-with-liveview|Using Formentation with LiveView]]
- [[Userguide|Back to the guide index]]
