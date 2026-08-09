---
title: Inspecting definitions
aliases:
  - Inspecting definitions
tags:
  - formentation
  - userguide
status: current
---

# Inspecting definitions

*Covers Formentation as of 2026-08-09. Every snippet below was run
against that version.*

A `Formentation.Definition` is the compiled, inert description of a
form: it holds no values, no errors, and no DOM ids.
[[getting-started|Getting started]] shows how to get one, as the
compile-once alternative to the ordinary one-call path. This page is
about what you can ask it afterwards.

You need none of this to build a working form. Reach for it when a form
does not look the way you expected, when you are building tooling over a
declaration, or when you want a test to assert that a declaration
compiled to what you meant.

Every snippet below assumes the declaration from
[[getting-started|Getting started]], compiled with:

```elixir
{:ok, definition, []} = Formentation.compile(declaration, adapter: :map)
```

## The query surface

`Formentation.Info` is the stable way to ask a definition questions.
Renderers, tooling, and tests go through it instead of pattern-matching
definition internals, which are not a compatibility-stable surface.

```elixir
Formentation.Info.fields(definition) |> Enum.map(& &1.name)
#=> ["email", "age", "subscribed"]

Formentation.Info.role(definition, ["email"])
#=> :email

Formentation.Info.required?(definition, ["email"])
#=> true
```

`fields/1` returns fields in **semantic declaration order** — the order
you wrote them — which is not necessarily the order they render in when
a presentation layout reorders them.

## Where a value came from

Compilation never guesses invisibly. Every resolved value records its
provenance, which is what to reach for when a form does not look the way
you expected:

```elixir
Formentation.Info.origins(definition, ["age"])
#=> [
#=>   role: {:inference, :integer_default},
#=>   label: {:map_source, [:properties, "age", :title]}
#=> ]
```

The role was *inferred* from the kind; the label came from the `title`
you wrote. Anything tagged `{:inference, _}` is a decision Formentation
made for you — and anything tagged with a source path is one you made.

## Where to go next

- [[getting-started|Getting started]] — the whole loop in one page
- [[declaring-with-the-map-source|Declaring a form with the map source]] — every key you can write
- [[limitations|What isn't supported yet]] — before you plan around any of this
- [[Userguide|Back to the guide index]]
