---
title: The FormData projection
aliases:
  - The FormData projection
  - Phoenix FormData
tags:
  - formentation
  - techdocs
  - phoenix
status: current
---

# The `FormData` projection

> [!note] As of 2026-07-23 · step 6 complete
> Describes `defimpl Phoenix.HTML.FormData, for: Formentation.Form` as
> built. The state being projected is
> [[form-state-and-transitions|Form state and transitions]]; what the
> projection is consumed by is [[rendering|Rendering]].

This layer is where Formentation's own state model meets Phoenix's. It is
a **projection and nothing else**
([[18-decisions#D-009 — Form state separates transport from operation|D-009]]):
it owns no decoding, no validation, and no transitions. Every question
Phoenix asks it is answered by reading already-computed state. Driving
the form goes the other way round — through `Form.transition/2` — and the
implementation actively refuses options that would let a caller smuggle
state in sideways (`:action` and `:errors` raise).

## Why a projection at all

Phoenix's form ecosystem — `<.form>`, the core components, `to_form/2`,
`used_input?/1` — is organized around the `Phoenix.HTML.FormData`
protocol. Implementing it means a `Formentation.Form` *is* an ordinary
Phoenix form source, so everything built for Ecto changesets works
unchanged, and Formentation never has to reimplement naming, nesting, or
id generation. The cost is that Phoenix's conventions become a contract
this layer has to satisfy exactly; most of what follows is that contract.

## The four callbacks

| Callback | Answered from |
| --- | --- |
| `to_form/2` | the whole `Form` — sets `params`, `data`, `errors`, `action` |
| `to_form/4` | a nested data-nesting group; other node kinds raise |
| `input_value/3` | `FieldState.display_value` |
| `input_validations/3` | the node's schema constraints plus input policy |

### Instance path travels in the options

A Phoenix form has a `name` and an `id` but no notion of *where in the
data* it sits. The implementation therefore carries the current
[[paths-and-identity|`InstancePath`]] in a private options key, and every
callback resolves `path_of(form) ++ [field]` before asking `Info` which
node governs it. Nesting a form extends the path by one segment. This is
the mechanism that lets one `Definition` describe a tree while Phoenix
hands out flat, per-level form structs.

### Nesting materializes forms directly

`to_form/4` (what `<.inputs_for>` calls) accepts **data-nesting groups
only**; a scalar or a presentational group raises, because neither has a
sub-form to build. Names and ids are joined with Phoenix's own
conventions (`parent[key]`, `parent_key`), and the collection options
`:default`, `:prepend`, `:append` raise rather than being silently
ignored — defaults come from `Form` state, and collections arrive with
Milestone B.

## Values and the display-value rule

`input_value/3` returns `FieldState.display_value` — never the decoded
value, and never the raw params. This is what makes failed input
survivable: after a decode failure the field shows *what the user typed*,
because a control that blanks itself when the entry is rejected is
actively hostile. For a read-only field it returns the original data
regardless of what was submitted
([[18-decisions#D-016 — Participation is definition-driven, not transport-driven|D-016]]).
A path that resolves to no `Node.Field` falls back to Phoenix's ordinary
params-then-data lookup.

## Errors — three deliberate constraints

`form.errors` is where the projection makes the most decisions, all of
them forced by Phoenix conventions rather than chosen freely.

**Empty until an action.** With `action: nil` the list is `[]`
unconditionally. A pristine form never shows errors even though the state
layer may already hold issues from initial validation.

**Direct scalar children only.** Each form level projects the issues of
its own immediate `Node.Field` children. An issue whose path names a
*group* — a missing required nested object, say — is object-level and
stays out of `form.errors` entirely, because Phoenix's per-field
convention has nowhere to put it. Those issues are read directly from
`Form.issues/2` by [[rendering#Error summary|the error summary]].

**Keyed by existing atom, with a string fallback.** phoenix_html matches
error keys against the field name exactly as passed, and the core
components pass atom literals. Keys are therefore `String.to_existing_atom/1`
with a rescue to the string — never `String.to_atom/1`, which would let
schema-derived property names leak the atom table. The consequence is an
asymmetry worth knowing: when the atom exists, `form[:name].errors`
matches while `form["name"].errors` is `[]`. phoenix_ecto has the same
one.

Each error is Phoenix's `{message, opts}` shape, with the issue's `code`
and `source` carried in the opts so a consumer can tell a decode failure
from a schema violation.

## Validations derive from the schema, not from `required?`

`input_validations/3` produces the progressive-enhancement attributes
(`required`, `min`/`max`/`step`, `minlength`/`maxlength`) from the node's
constraints — and pointedly **not** from `required?` alone. A required
string that permits `""` gets no `required` attribute, because `""` is
schema-valid there; the test mirrors the compiler's
`:required_permits_empty` exemption exactly, so the browser and the
server agree about what is enforceable
([[18-decisions#D-010 — Empty-string, null, and absent-key decode policies|D-010]]).
These are hints for the browser, never a substitute for server
validation.

## Usage stays Phoenix's to answer

`form.params` is the byte-identical `phoenix_params` view produced by
[[form-state-and-transitions#Transport normalization|transport
normalization]], specifically so that `Phoenix.Component.used_input?/1`
keeps working against a Formentation form with no special-casing. A
contract test pins Formentation's usage answer against Phoenix's for the
same params, so the two can never quietly diverge
([[18-decisions#D-014 — Usage is a first-class interaction axis|D-014]]).

## The boundary this lives behind

A `defimpl`'s generated module is named after the *protocol*, not
`Formentation.Phoenix.*`, so the phoenix_html dependency cannot be
confined by module namespace. It is confined by **directory** instead —
everything Phoenix-aware lives under `lib/formentation/phoenix/`, checked
by a directory-scoped boundary test
([[18-decisions#D-017 — Phoenix integration ships in-tree behind a namespace boundary|D-017]],
[[18-decisions#D-018 — Reach is the architecture gate|D-018]]). Nothing
in the core layers may reference Phoenix; see
[[test-and-verification-architecture|Test and verification architecture]]
for how that is enforced.

## Naming is pinned, not assumed

Input naming follows Phoenix conventions and works with bare names (no
`:as`), so a payload form composes under an enclosing form's namespace —
`asset[payload][email]`. Rather than trust that by inspection, a property
test round-trips generated names through `Plug.Conn.Query.decode/1` and
asserts the params reassemble into the structure the definition
describes. Naming is the seam where a subtle error would be invisible in
review and fatal in production, so it is checked mechanically.

## Boundaries — what does not exist

No collections (`to_form/4` handles objects only, and the collection
options raise). No `:patch` or scoped transitions to project. No
`hidden` entries — the projection sets `hidden: []` and lets the theme
emit hidden inputs where the definition asks for them. Object-level and
root issues are deliberately outside `form.errors` and reachable only
through `Form.issues/2`.

## Code map

| Concern | Module | File |
| --- | --- | --- |
| The protocol implementation | `Phoenix.HTML.FormData` for `Formentation.Form` | `lib/formentation/phoenix/form_data.ex` |
| The state being projected | `Formentation.Form` | `lib/formentation/form.ex` |
| Boundary test | `Formentation.Phoenix.BoundaryTest` | `test/formentation/phoenix/boundary_test.exs` |
| `used_input?` contract | `Formentation.Phoenix.UsedInputContractTest` | `test/formentation/phoenix/used_input_contract_test.exs` |
| Naming property | `Formentation.Phoenix.NamingPropertyTest` | `test/formentation/phoenix/naming_property_test.exs` |

## Related notes

- [[form-state-and-transitions|Form state and transitions]] — the state this projects
- [[rendering|Rendering]] — the consumer of this projection
- [[end-to-end-data-flow|End-to-end data flow]] — this layer in the whole chain
- [[test-and-verification-architecture|Test and verification architecture]] — the boundary gate
- Design (Planning): [[07-phoenix-integration|Phoenix integration]] · [[06-runtime-projection|Runtime projection]]
- [[Techdocs]] · [[Formentation|Vault entry note]]
