---
title: Userguide
aliases:
  - User guide
tags:
  - formentation
  - index
  - userguide
status: draft
---

# Userguide

**Practical documentation for developers using Formentation** — how to
declare a form, render it, and handle what comes back. Task-oriented:
how do I *do* a thing. The internal counterpart is [[Techdocs]].

> [!important] Scope — only what is available
> Pages here cover features that actually ship today. Formentation is
> pre-release and its API is not stable. Every page states its
> limitations inline, and [[limitations|What isn't supported yet]]
> collects them in one place — read that page before planning around
> anything here.

## Contents

1. [[getting-started|Getting started]] — the whole loop in one page:
   declare a form, compile and initialize it with `Formentation.form/2` or
   the two-step `compile/2` + `Form.new/3` path, render it, handle the
   submission, read the decoded result.
2. [[declaring-with-the-map-source|Declaring a form with the map source]] —
   the plain-Elixir declaration vocabulary, in full.
3. [[declaring-with-json-schema|Declaring a form with JSON Schema]] — the
   supported draft 2020-12 subset and the UI-hints companion document.
4. [[rendering-with-phoenix|Rendering with Phoenix]] — the two
   components, embedding under a parent form, widgets, and what the
   reference UI guarantees.
5. [[inspecting-definitions|Inspecting definitions]] — querying a
   compiled definition and reading where each resolved value came from.
6. [[using-with-liveview|Using Formentation with LiveView]] — mount,
   the `phx-change`/`phx-submit` handlers, the two rules, error
   visibility, the runnable demo (including its native-validation
   toggle), and how to run its browser-real test suite.
7. [[limitations|What isn't supported yet]] — the honest list.

Fine-grained API detail — every function, every option — lives in the
moduledocs rather than here; run `mix docs` or read them in IEx with
`h Formentation` (entry points and adapter contract) or `h Formentation.Form` (form operations).

## Related

- [[Techdocs]] — how the system works internally
- [[Formentation|Vault entry note]]
