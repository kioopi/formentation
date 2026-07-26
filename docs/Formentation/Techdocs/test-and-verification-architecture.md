---
title: Test and verification architecture
aliases:
  - Test and verification architecture
  - Test architecture
tags:
  - formentation
  - techdocs
  - testing
status: current
---

# Test and verification architecture

> [!note] As of 2026-07-26 · step 7 + browser-testing suite + vault link gate
> Describes the verification setup as built: the kinds of test in the
> suite, what each one pins, and the static gates in `mix ci` — including
> the demo's `Phoenix.LiveViewTest` suite and, now, the opt-in browser-real
> suite as verification mechanisms in their own right (detailed in
> [[browser-testing|Browser testing]]). Counts and individual test names
> are deliberately absent — they change weekly. The strategy this
> implements is [[11-testing-strategy|Planning/11 — Testing strategy]].

Formentation's suite is not a uniform pile of unit tests. It is a small
number of **distinct verification mechanisms**, each aimed at a specific
class of mistake that the others structurally cannot catch. Knowing which
mechanism owns which risk is what makes it possible to add a feature and
know where its tests belong.

## The mechanisms

| Mechanism | Catches | Where |
| --- | --- | --- |
| Example tests | ordinary behavioural regressions | every `*_test.exs` |
| Doctests | documentation drifting from behaviour | `doctest TheModule` in the module's test file |
| Property tests | invariants that hold over *generated* input | `*_property_test.exs` |
| Differential test | the two adapters diverging | `differential_test.exs` |
| Contract tests | Formentation disagreeing with an upstream library | `used_input_contract_test.exs`, the naming property |
| Reviewed snapshot | unnoticed markup change | `snapshot_test.exs` + a checked-in `.html` |
| Boundary tests | architectural erosion | `boundary_test.exs`, `mix reach.check` |
| Demo `LiveViewTest` suite | LiveView lifecycle regressions: mount, embedding, `phx-change`/`phx-submit`, `_persistent_id` | `test/formentation_demo/` |
| Browser-real suite | truths `LiveViewTest`'s missing `LiveSocket` hook cannot observe: real `_unused_` gating, raw-input sanitization, focus movement | `test/browser/`, opt-in via `mix test.browser` — see [[browser-testing|Browser testing]] |

Each is worth a word on *why it exists*, because in every case an
ordinary example test would have been the cheaper option and was
rejected for a reason.

### Doctests carry the examples

Public functions carry `@doc` with a worked example wherever the function
is practically doctestable — pure data in, data out, or a cheap
`render_component/2` check for components — and each module's test file
wires it in with `doctest TheModule`. The point is not coverage but
**anti-drift**: an example in a moduledoc that is also a test cannot
quietly stop being true, which is what makes the moduledocs usable as the
fine-grained API reference the vault notes deliberately are not.

### Property tests own the invariants

Properties are used where a claim is universally quantified and examples
would only sample it. The ones that exist guard, among others: that
compilation never creates atoms from input, that the depth and node
budgets hold against adversarial nesting, that a read-only field's
original value survives any transition
([[18-decisions#D-016 — Participation is definition-driven, not transport-driven|D-016]]),
and that generated input names round-trip through Phoenix's own param
reassembly. These are exactly the claims where a hand-picked example
proves almost nothing.

### The differential test makes "source-independent" checkable

`differential_test.exs` compiles each shared fixture through **both**
adapters and asserts the resulting trees are *Info-equivalent*: same node
struct, same semantic facts per node, same child counts, recursively.

Its importance is out of proportion to its size. "Source-independent" is
the project's central architectural claim
([[18-decisions#D-004 — Two declaration sources from the start|D-004]]),
and it is the kind of claim that decays invisibly — an adapter picks up a
behaviour the other lacks and nothing fails. This test converts the claim
into a build failure. [[diagnostics-and-origins#Origins — provenance for resolved values|Origins]]
are the single sanctioned difference and are asserted separately.

The fact list is the test's real interface: adding a semantic field to
`Node.Field` without adding it there means the new field is silently
unchecked across sources. It is the one place in the suite where an
omission is more dangerous than a wrong assertion.

### Contract tests pin agreement with upstream

Two places make claims *about another library's behaviour* rather than
about Formentation's:

- **`used_input?` contract** — Formentation extracts usage from
  LiveView's `_unused_` marker convention itself, in
  [[form-state-and-transitions#Transport normalization|`Transport`]],
  because the state layer must stay Phoenix-free. That means two
  independent implementations of the same convention. The test runs both
  against the same params and asserts they agree
  ([[18-decisions#D-014 — Usage is a first-class interaction axis|D-014]]).
- **Naming property** — generated input names are round-tripped through
  `Plug.Conn.Query.decode/1` and asserted to reassemble into the
  structure the definition describes.

Both target the same failure mode: a divergence that is invisible in
review, silent in production, and only manifests as data quietly landing
in the wrong place.

### One reviewed snapshot, not snapshot-everything

There is exactly one HTML snapshot —
`test/support/fixtures/pump_inspection/static_render.html` — holding
[[end-to-end-data-flow|the end-to-end example]] rendered under a parent
namespace. It is compared **byte-exactly**, and the update ritual is
deliberate: delete the file, rerun, *read the diff*, commit.

The restraint is the design. Snapshots asserted broadly become
rubber-stamped noise, and [[11-testing-strategy|the testing strategy]]
specifically warns against a suite that only knows HTML. One snapshot is
enough to notice unintended markup change; everything about the markup
that actually *matters* is asserted semantically instead — see below.

### Accessibility is asserted structurally, not textually

`Formentation.HTMLAssertions` provides Floki helpers — `assert_labelled`,
`describedby`, `assert_no_duplicate_ids`, `find_one` — shared by the
theme, component, and snapshot tests, and each maps to a numbered item of
[[rendering#Reference theme|the accessibility contract]]. Asserting
"every control has a non-empty `<label for>` pointing at its id" as a DOM
query rather than a substring match is what lets the theme's markup be
restyled freely while its guarantees stay pinned.

### The demo is where the LiveView lifecycle gets tested

`Form.validate/2` and `Form.submit/2` add no verification mechanism of
their own — they are `transition/2` underneath, already covered by the
state layer's example and property tests. What they add is a *caller*
worth testing in its own right: a real `mount/3`, real `handle_event/3`
clauses, and a real `<.form>` template wired to
`phx-change`/`phx-submit`, none of which the layered unit tests above
exercise. `test/formentation_demo/` drives
`FormentationDemo.PumpInspectionLive` (embedded under a hand-written
parent form) and `FormentationDemo.NestedLive` (a bare data-nesting
object) through `Phoenix.LiveViewTest`, asserting the same accessibility
and error-visibility properties the rest of the suite pins, now
end to end through a live socket.

One result is worth flagging because it reverses an assumption the
step-7 spec started with: `Phoenix.LiveViewTest`'s `form/3` plus
`render_change/1`/`render_submit/1` re-serialize the *entire* rendered
form on every call and never carry `_unused_` markers, on a change or a
submit alike. That convention is applied client-side, by LiveView's JS
hook, before a real request ever reaches the server, and
`Phoenix.LiveViewTest` never runs that hook. So the demo's tests pin
*marker-less* semantics — every serialized field `:used` from the first
event, a blank required field erroring immediately rather than only
once touched — while a separate real-browser check confirmed the
marker-gated semantics the spec originally expected, for the transport
`Phoenix.LiveViewTest` cannot simulate
([[18-decisions#D-021 — LiveView integration is wrappers plus a demo, not framework machinery|D-021]]).
Both are true, of different transports — worth knowing before trusting a
green `LiveViewTest` suite as proof of what a real browser will show.

## Fixtures are a shared contract, not test data

`Formentation.Fixture` is a behaviour with four callbacks: `map_source/0`,
`json_schema/0`, `ui_hints/0`, `field_names/0`. Every differential
fixture implements it, so each fixture *is* one form expressed in both
declaration vocabularies.

That shape is what makes the differential test possible at all, and it
means adding a fixture is how you extend cross-source coverage. The
fixtures live under `test/support/fixtures/`, with the JSON documents as
real `.json` files rather than inline heredocs — they are also what
`.iex.exs` loads, so the same forms are explorable by hand.

## Static gates — `mix ci`

Tests are only half the verification. `mix ci` runs, in order:
`compile --warnings-as-errors`, `format --check-formatted`, `vault.links`,
`test`, `credo --strict`, `dialyzer`, `ex_dna --max-clones 0`, and
`reach.check --arch --smells`. Three of those deserve explanation.

**`mix vault.links`** fails on any `[[wikilink]]` that contains a line
break. Obsidian does not parse those, so a hard-wrapped link renders as
literal text and the note loses a link with nothing failing. Reflowing a
paragraph is enough to introduce one, which is why it is a gate rather
than a review habit. It scans `docs/Formentation/**/*.md` — only the
tracked vault, since `docs/discussion/` and `docs/superpowers/` are
untracked working notes — and skips fenced blocks and inline code spans,
so code samples and prose *about* wikilink syntax are not mistaken for
links.

`Mix.Tasks.Vault.Links` lives in `test/support/mix/tasks/` rather than
`lib/`: it compiles on `elixirc_paths(:test)`, so it never ships in the
package, and a `preferred_envs` entry runs it in `MIX_ENV=test`. It takes
an optional path argument, which is what lets
`test/mix/tasks/vault_links_test.exs` drive it over a `tmp_dir` fixture;
the line-scanning itself is a pure `split_links/1` covered by unit tests
and doctests. Being outside a layer, it carries a `layer_coverage.ignore`
entry in `.reach.exs` alongside the other `test/support` modules.

**`ex_dna --max-clones 0`** fails on *any* duplicated code block. In a
project with two adapters translating different vocabularies into the
same tree, near-duplicate walks are the natural failure mode; the zero
threshold is what pushed the shared logic into
`Formentation.Source.Shared` rather than letting the adapters drift into
parallel copies.

**`mix reach.check --arch --smells`** is the architecture gate
([[18-decisions#D-018 — Reach is the architecture gate|D-018]]). Its
policy in `.reach.exs` declares five layers — `core`, `source`,
`json_schema`, `phoenix`, and (since step 7) `demo` — and then declares
what may *not* depend on what:

- nothing below the projection layer may reach Phoenix;
- core never selects a source adapter (`compile/2` receives one);
- JSV never leaks past `JSONSchema.Validator`
  ([[18-decisions#D-008 — JSV is the JSON Schema validator|D-008]]);
- the projection layer reads compiled core state, never adapters;
- no layer may acquire IO, write, or send effects unnoticed — the whole
  library is declared pure data transformation, with narrow per-module
  allowances for the path builders' use of `IO.iodata_to_binary/1`;
- the library must never depend on `demo`, even though `demo` — the
  runnable example under `demo/formentation_demo/` — may call anything
  and do server-ish IO, since it is an application, not library code.

One entry there encodes a decision rather than a rule: `core` is
forbidden from depending on `json_schema` **outright, with no exception**.
Instance validation used to be the one sanctioned core→adapter edge
(`Formentation.Form` → `JSONSchema.Validator`), which forced a baselined
core/`json_schema` layer cycle; that dispatch now goes through the
core-owned `Formentation.Validation` behaviour, so the edge, its named
exception, and the baseline file are all gone ([[18-decisions#D-025 — Instance validation dispatches through a source-neutral behaviour|D-025]]).
There is no longer a grandfathered violation — any cross-layer edge fails.

**The Phoenix boundary is checked twice, differently.** `reach` checks it
by module pattern; `boundary_test.exs` walks the AST of every file
outside `lib/formentation/phoenix/` looking for a `Phoenix.*` alias. The
redundancy is deliberate: a `defimpl`'s generated module is named after
the protocol (`Phoenix.HTML.FormData.Formentation.Form`), not after
`Formentation.Phoenix.*`, so **the boundary is a directory fact that a
purely namespace-based check would miss**
([[18-decisions#D-017 — Phoenix integration ships in-tree behind a namespace boundary|D-017]]).

## Layering is what makes the suite cheap

The property that makes all of the above affordable is the one-directional
[[end-to-end-data-flow|data flow]]: each layer is testable without the
next. The compile pipeline is tested with no runtime state; the state
layer with no Phoenix; the projector against any `FormData` source; the
theme against a hand-built plan. Nothing needs a `Plug.Conn`, a LiveView
process, or a browser.

That is not a happy accident of the test suite — it is the layering
being *paid off*, and it is the reason a boundary violation is treated as
a build failure rather than a style note.

The one addition since is the demo layer: `test/formentation_demo/`
genuinely does spin up a LiveView process, because it is verifying the
wrappers' LiveView-facing behavior specifically, not any layer below it
— the layering property is what let that be added as one bounded suite
rather than requiring every layer to grow LiveView-shaped tests of its
own.

## Boundaries — what is not verified

A small, opt-in browser-real suite now exists ([[browser-testing|Browser testing]]),
covering exactly the gap called out above — four seed tests, run via
`mix test.browser` and excluded from `mix ci`. It is deliberately narrow:
no axe-style automated accessibility audit (the contract is still asserted
structurally, not by a browser tool), no performance or load testing, and
no benchmarks. Coverage is measured (`mix six`) but no threshold gates the
build. Diagnostic codes are asserted where they are produced but are not
pinned against accidental renaming by any registry.

## Code map

| Concern | File |
| --- | --- |
| Differential property | `test/formentation/differential_test.exs` |
| Fixture behaviour | `test/support/fixture.ex` |
| Shared fixtures | `test/support/fixtures/` |
| Accessibility helpers | `test/support/html_assertions.ex` |
| Reviewed snapshot | `test/support/fixtures/pump_inspection/static_render.html` |
| Phoenix boundary (AST) | `test/formentation/phoenix/boundary_test.exs` |
| Architecture policy | `.reach.exs` |
| CI pipeline | `mix.exs` — the `ci` alias |
| LiveView demo suite | `test/formentation_demo/`, `demo/formentation_demo/` |
| Browser-real suite | `test/browser/`, `mix test.browser` alias in `mix.exs` |

## Related notes

- [[browser-testing|Browser testing]] — the opt-in Playwright suite this note's mechanism table now includes
- [[end-to-end-data-flow|End-to-end data flow]] — the layering this exploits
- [[source-adapters#The differential-equivalence property|Source adapters]] — the differential property in context
- [[rendering#Reference theme|Rendering]] — the accessibility contract being asserted
- [[phoenix-form-data|The FormData projection]] — what the contract tests pin
- Design (Planning): [[11-testing-strategy|Testing strategy]] · [[02-design-principles|Design principles]]
- [[Techdocs]] · [[Formentation|Vault entry note]]
