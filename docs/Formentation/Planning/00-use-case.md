---
title: Motivating Use Case
tags:
  - formentation
  - use-case
  - requirements
status: active
---

# Motivating use case

Formentation exists because of a concrete customer project. This note records that project so scope decisions can be traced to a real requirement rather than to architectural ambition. The [[13-roadmap#Scope control|scope-control checklist]] should point here first.

## The project

A customer runs their operation on a collection of spreadsheets and wants to migrate to a relational database backed by a Phoenix application.

- The **entities and relationships** are well understood and become ordinary SQL tables, columns, and foreign keys, edited through hand-written forms and changesets.
- Each of several record types additionally carries a **bag of data whose shape only domain experts can define**: measurements, attributes, and observations that vary by deployment and evolve over time. These bags become JSON payload columns (for example Postgres `jsonb`) beside the relational columns.
- Domain experts must be able to **define and revise the payload shape themselves**, without code changes: which fields exist, their types and constraints, labels and help text, ordering, and **grouping of related fields**.
- Staff then need generated **forms to enter and update** those payloads, embedded in the application's existing pages.

JSON Schema is the natural declaration and validation format for the payloads. The expert-authored schema is stored in the database and describes both what a valid payload is and, together with UI hints, how its form should look.

## What this requires from Formentation

1. **Runtime compilation.** Schemas live in the database and change while the application runs. Compilation is an ordinary runtime function; caching matters later, compile-time macros do not.
2. **Bounded trust.** Experts are not attackers, but they will make mistakes: deep nesting, huge enums, contradictory hints. Depth/size limits and honest diagnostics are needed before this is production software. Schema property names must never become atoms.
3. **Two audiences for errors.** Experts need *declaration* diagnostics ("this schema construct is not supported, here is where and why"); staff need *instance* issues ("must be at least 0"). This is exactly the [[03-conceptual-model#Diagnostic and issue|diagnostic/issue distinction]].
4. **Grouped fields over flat data.** Experts group related fields for presentation. The payload itself stays flat; grouping is a UI concern. Presentation groups and object containers are therefore different things, even if they share markup.
5. **Embedding.** A payload form is a fragment inside a larger hand-written form whose other inputs come from an Ecto changeset. The renderer must compose under an enclosing form and namespace (for example `asset[payload][...]`), not assume it owns the page. See [[07-phoenix-integration#Component API|Component API]].
6. **Entry and update.** New records start from an empty payload (with an explicit default-application policy); edits initialize from stored JSON.
7. **A modest schema subset, honestly reported.** Flat-ish objects, scalars, enums, groups, and ordering cover the spreadsheets. Conditional fields ("show B only when A is x") are a plausible expert request later — [[phase-4-dynamic-schemas|Phase 4]] has a real customer, but not an immediate one.

## What this project does not need

Recording non-needs is as useful as recording needs:

- multiple UI themes — the application has one design system;
- full JSON Schema coverage — unsupported constructs may simply be diagnosed;
- remote `$ref` resolution — schemas are local database rows;
- Ash integration — this application is plain Ecto; [[phase-5-ash-integration|Phase 5]] remains a decoupling proof, not a customer requirement;
- a schema-builder UI — experts start with supported JSON authoring; the [[09-diagnostics-provenance-introspection|introspection surface]] is what would later power such an editor.

## How to use this note

Every feature should trace to a numbered requirement above or to a recorded second use case. When a design question has no answer here, prefer the simpler option and record the question in [[16-open-questions|Open questions]].

## Related notes

- [[01-philosophy|Project philosophy]]
- [[17-end-to-end-example|End-to-end example]] — a worked form from this domain
- [[18-decisions|Decision log]]
- [[13-roadmap|Roadmap]]
- [[Formentation|Back to the entry point]]
