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

*Accurate as of 2026-07-24. Formentation is pre-release; this page is the
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

### LiveView is wrappers, not a framework

`Formentation.Form.validate/2` and `Formentation.Form.submit/2` are the
whole LiveView surface — thin sugar over `transition/2` for
`phx-change` and `phx-submit`, described on
[[using-with-liveview|Using Formentation with LiveView]]. There is no
`use` macro, no generated LiveView, no LiveComponent, no automatic
mount/handler wiring, and no upload support: you write `mount/3` and
`handle_event/3` yourself, exactly as you would without Formentation.

### No theme API

The components render through a single built-in theme, called directly.
There is no theme parameter, no component registry, and no documented
contract for writing your own. You can style the markup with CSS against
its class names; you cannot swap the markup.

### No extension points

No custom node kinds, no custom codecs or per-field codec overrides, no
custom source adapters beyond the two shipped, no compiler passes, no
widget registration. The `Formentation.Source` behaviour exists and is
implemented twice, but it is not yet a supported public extension point.

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
`Formentation.Params` envelope, because an absent key is ambiguous
between "cleared" and "untouched".

**All-or-nothing candidates.** If any field fails to decode, there is no
candidate at all and schema validation is skipped entirely until it
parses. This is intentional — it prevents one bad field from cascading
into confusing type errors — but it means you cannot get a partial
result out of a partly-invalid form.

**Defaults are opt-in and initialization-only.** They apply at
`Form.new/3` with `defaults: :apply`, never on a transition, and never
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
