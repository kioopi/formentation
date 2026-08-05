---
title: Diagnostics and origins
aliases:
  - Diagnostics and origins
tags:
  - formentation
  - techdocs
  - diagnostics
status: current
---

# Diagnostics and origins

> [!note] As of 2026-07-25 · source-neutral validation dispatch
> Describes the explainability model as built: the `Diagnostic` struct,
> the origin tags nodes carry, the guards, and the one *projection*-time
> diagnostic that now exists. The full `Decision` / `Info.explain/3`
> model is a [[phase-2-compiler-diagnostics|Phase 2]] target and is not
> built — see [[09-diagnostics-provenance-introspection|the design note]]
> for where this is going.

Two of Formentation's design principles are that compilation never fails
silently and never guesses invisibly. Both are cashed out by structures
rather than by convention: **diagnostics** record what went wrong, and
**origins** record where every resolved value came from. Neither is
optional metadata — a node that carries a `label` it inferred rather than
read is required to say so.

## Two kinds of problem, deliberately separate

`Diagnostic` and `Issue` are different structs because they answer
different questions, arise in different phases, and have different
audiences.

| | `Formentation.Diagnostic` | `Formentation.Issue` |
| --- | --- | --- |
| About | processing a **declaration** | validating a **submitted instance** |
| Phase | compile time (and projection) | runtime |
| Addressed by | `template_path` — a structural position | `path` — an `InstancePath` in real data |
| Audience | whoever wrote the schema or hints | whoever is filling in the form |
| Severity | `:error` \| `:warning` | — (all issues are problems) |
| Discriminator | `code` | `code` plus `source` (`:decode` \| `:validation`) |
| Lives on | `Definition.diagnostics` · `RenderPlan.diagnostics` | `Form.issues`, keyed by path |

Conflating them is the mistake the split prevents: a schema author's
mistake ("this `type` is outside the supported subset") must never reach
an end user's screen, and an end user's mistake ("this field is
required") must never be reported as a compiler warning. `Issue` and its
visibility rules belong to
[[form-state-and-transitions|the state layer]]; this note covers
`Diagnostic`.

```elixir
%Formentation.Diagnostic{
  severity: :warning,
  code: :unsupported_type,
  message: ~s(unsupported type "array" for property "tags"),
  origin: {:json_schema, "/properties/tags/type"},
  template_path: %TemplatePath{segments: ["tags"]}
}
```

`origin` and `template_path` are both nilable — some problems cannot be
attributed to a declaration location (a whole document that fails the
metaschema, an exhausted node budget at the root), and the struct says so
with `nil` rather than inventing a plausible position.

## Severity is a control-flow fact, not a label

The two severities are not a rendering hint; they determine what
`compile/2` returns.

- **`:error`** — the declaration could not yield a definition. The
  adapter returns `{:error, diagnostics}` and there is no `Definition` at
  all.
- **`:warning`** — compilation succeeded, and the diagnostic rides along
  on `Definition.diagnostics` (read via `Info.diagnostics/1`). The form
  works; something in it was degraded, ignored, or is likely a mistake.

This is what makes the "degrade, don't crash" principle checkable rather
than aspirational: adversarial or partially-unsupported input must land
in the second row.

## What produces diagnostics

Five distinct producers, each with its own failure character. Individual
codes are listed for orientation; the modules are authoritative.

**1. Structural guards** — `:max_depth_exceeded`, `:max_nodes_exceeded`.
Errors. The depth ceiling (default 16) and node budget (default 1 000)
live in `Shared.Context` and are enforced by each adapter at its own
recursion points with identical semantics. Their whole purpose is to turn
runaway or hostile input into a diagnostic instead of a stack overflow,
so they are the one category that *must* be an error: there is no partial
answer to give.

**2. Declaration rejection** — `:invalid_schema`, `:unsupported_dialect`,
`:invalid_ui_hints`, `:invalid_declaration`, and `:unsupported_type` at
the root. Errors. The input is not a form at all: it fails the draft
2020-12 metaschema, declares a dialect the adapter does not implement,
carries a malformed `:ui` map, or is not an object schema. These fire
*before* or *at* the root of the walk, so nothing is half-built.

**3. Out-of-subset constructs** — `:unsupported_type` (at a property),
`:unsupported_kind`, `:unsupported_keyword`. Warnings. The declaration is
valid but says something the pinned subset does not translate. The
property becomes a `Semantic.Unsupported` and the rest of the form compiles
around it. `:unsupported_keyword` also covers annotations that are
recognised but deliberately dropped, such as an explicit null `default`.

> [!info] One code, two severities
> `:unsupported_type` is an error at the root and a warning at a
> property. That is not an inconsistency — it is the same *finding*
> reaching two different structural positions. A non-object root leaves
> nothing to compile; a non-scalar property leaves a form with one
> unsupported node in it. The code names the finding; the severity names
> what could still be salvaged.

**4. Hint problems** — `:unknown_widget`, `:unknown_hint_field`,
`:unknown_group_field`, `:unknown_order_entry`, `:invalid_hint_value`,
`:validator_unavailable`. Warnings. A hint refers to something that does
not exist, or supplies a value of the wrong shape. The rule throughout is
that a bad hint is *ignored*, loudly — presentation intent is never
allowed to fail a compile, because the form still has a defensible
default rendering without it. `:validator_unavailable` is the same
posture applied to the instance validator: a dangling local `$ref` or any
remote `$ref` (fetching is disabled) yields `validation: nil` and a
warning rather than an exception.

**5. Source-independent policy advisories** — `:reserved_property_name`,
`:required_permits_empty`. Warnings. These are architecturally the most
interesting, because nothing is wrong with the *declaration* — the
problem is what the declaration will mean downstream. A property named
`_target` or `_unused_x` would be stripped by transport normalization
([[18-decisions#D-014 — Usage is a first-class interaction axis|D-014]]);
a required string without `minLength: 1` accepts `""`, because JSON
Schema's `required` checks presence, not blankness
([[18-decisions#D-010 — Empty-string, null, and absent-key decode policies|D-010]]).
Both depend only on the finished node tree, never on the input
vocabulary, so they run once in `Shared.compile_impl/3` after the walk
and fire identically for both sources.

## Diagnostics are no longer compile-time only

Step 6 introduced the first diagnostic produced *after* compilation:
`:widget_fallback`, emitted by
[[rendering|`Formentation.Phoenix.RenderPreparation`]] onto
`RenderPlan.diagnostics` when a declared widget hint cannot render the
field it names — a widget outside the theme's set, or a `:checkbox` hint
on a non-boolean field. The projector falls back to the inferred widget
and records why.

This generalizes the model in a way worth stating: a diagnostic is
*anything a layer chose to do differently than the declaration asked*,
reported at the point of choosing. The compiler is simply where most such
choices happen. The projector's diagnostics live on the plan rather than
the definition because they depend on the theme's capabilities — a
different theme could render the same hint without complaint, and the
cached, shared `Definition` must not carry one theme's opinion.

## Origins — provenance for resolved values

Every node carries `origins`, a keyword list pairing a resolved property
with the tag explaining where its value came from
([[18-decisions#D-003 — Simplified provenance first|D-003]]):

```elixir
Info.origins(definition, ["email"])
# [
#   label:  {:json_schema, "/properties/email/title"},
#   role:   {:json_schema, "/properties/email/format"},
#   widget: {:ui_hints, "/fields/email/widget"},
#   help:   {:ui_hints, "/fields/email/help"}
# ]
```

Four tag shapes, one per contributing vocabulary:

| Tag | Points at | Used by |
| --- | --- | --- |
| `{:json_schema, pointer}` | an RFC 6901 [[paths-and-identity\|JSONPointer]] into the schema document | JSON Schema adapter |
| `{:ui_hints, pointer}` | a pointer into the hints document | JSON Schema adapter |
| `{:map_source, segments}` | a raw key path (a *list*, not a pointer) | Map adapter |
| `{:inference, rule}` | a named inference rule, not a location | both |

`{:inference, _}` is the important one. When no source supplied a value
and Formentation derived it — a label humanized from a property name, a
role read off a `format` — the origin names the *rule* rather than a
position. That is what "never guesses invisibly" means concretely: an
inferred value is indistinguishable from a declared one in the node, and
completely distinguishable in the origins.

Three properties hold across the model:

- **Only resolved values appear.** `Shared.origin_entries/1` drops `nil`
  origins, so the presence of a key in `origins` is itself the signal
  that the property was filled.
- **Overrides replace, not append.** A `fields.*.help` hint overriding a
  schema `description` replaces the origin entry too — origins describe
  the *winning* value, never the history of how it was decided. Recording
  that history is the
  [[09-diagnostics-provenance-introspection|`Decision` model]], deferred
  to Phase 2.
- **Origins are the sanctioned differential difference.** The
  [[source-adapters#The differential-equivalence property|differential property]]
  asserts that both adapters produce Info-equivalent trees,
  with origins as the *only* permitted divergence. Provenance is
  therefore precisely the part of a node that is allowed to know which
  vocabulary it came from — everything else must not.

## Boundaries — what does not exist

No `Decision` struct, no `Info.explain/3`, no ordered rule-by-rule
account of how a value was chosen; origins record the winner only. No
stable diagnostic-code registry or documented catalogue — codes are
atoms defined at their construction sites, and nothing yet pins them
against accidental renaming. No severity beyond `:error`/`:warning`, no
grouping, no deduplication: diagnostics accumulate in walk order.
Diagnostics also have no user-facing formatter — `message` is a plain
string built for a developer reading IEx or a test failure. All of this
is [[phase-2-compiler-diagnostics|Phase 2]] territory.

## Code map

| Concern | Module | File |
| --- | --- | --- |
| Compile-time diagnostic | `Formentation.Diagnostic` | `lib/formentation/diagnostic.ex` |
| Runtime issue | `Formentation.Issue` | `lib/formentation/issue.ex` |
| Origin struct | `Formentation.Origin` | `lib/formentation/origin.ex` |
| Guards · policy pass · `origin_entries/1` | `Formentation.Source.Shared` | `lib/formentation/source/shared.ex` |
| Metaschema translation | `Formentation.JSONSchema.Validator` | `lib/formentation/json_schema/validator.ex` |
| Projection-time diagnostic | `Formentation.Phoenix.RenderPreparation` | `lib/formentation/phoenix/render_preparation.ex` |

## Related notes

- [[compile-pipeline|Compile pipeline]] — the walk that stamps origins
- [[source-adapters|Source adapters]] — the two vocabularies being tagged
- [[paths-and-identity|Paths and identity]] — `JSONPointer` and `TemplatePath`
- [[form-state-and-transitions|Form state and transitions]] — `Issue`, the runtime counterpart
- [[rendering|Rendering]] — where `:widget_fallback` comes from
- Design / future (Planning): [[09-diagnostics-provenance-introspection|Diagnostics, provenance, introspection]] · [[phase-2-compiler-diagnostics|Phase 2]]
- [[Techdocs]] · [[Formentation|Vault entry note]]
