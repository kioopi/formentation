## Project Guidelines

- Use `mix ci` alias when you are done with all changes and fix any pending issues
- **Version control is Jujutsu (`jj`)** layered on top of git. The git working copy will frequently be on a detached HEAD — this is normal and expected. Do not "fix" it by creating branches or resetting. Just edit files; new changes are tracked in the current `jj` change automatically. Use `git` only for read-only inspection (`git log`, `git diff`, `git status`) unless explicitly told otherwise. Use your jujutsu skill.
- Obsidian Cli is installed. Use your obsidian skill.
- Use classic TDD process. Red, Green, Refactor.
- Development should happen in very small iterations. It is preferable to touch
  a feature several times and leave a clean and readable story in the jj history
  than make larger strides that are hard to understand later.
- Strong emphasis on test coverage and a meaningful test suite. Refactoring
  tests, adding test to ensure quality from different points of view, property
  tesst, are all first class activities.
- Public functions carry `@doc`, with a doctest example where the function is
  practically doctestable (pure data in/out, or a cheap `render_component`
  check for components). Wire doctests via `doctest TheModule` in the module's
  test file. `mix ci` runs `mix docs --warnings-as-errors`, so documentation
  warnings fail the build like compiler warnings do — no separate manual check.

## Documentation vault

Planning and documentation live in an Obsidian vault at `docs/Formentation/`. Every
directory, including the vault root, has an index note of the same name that acts as
its introduction and table of contents. The vault has four areas:

- **`Planning/`** — conceptual and design documentation (the numbered `00`–`18` notes).
  *Why* the project exists and the *intended* architecture. Largely forward-looking;
  the reference the implementation is measured against.
- **`Development/`** — phase-by-phase implementation plans (`phase-1` … `phase-5`) and
  their status. *Where the work is happening.* `Development.md` carries the phase-status
  table (Done / In progress / Planned / TBD).
- **`Techdocs/`** — current-state technical documentation: architecture, data structures,
  algorithms, data flows, and adapter boundaries of what is **actually built**, above
  moduledoc altitude. For developers working *on* Formentation.
- **`Userguide/`** — practical, task-oriented documentation for developers *using*
  Formentation: setup, sources, configuration, adapters. Covers only shipped features.

Loose exploratory notes that have not earned a place in the vault live outside it under
`docs/discussion/`. The granular classic-TDD specs and plans live under
`docs/superpowers/{specs,plans}/`, also outside the vault; `Development/` summarizes them.

**Techdocs and Userguide describe only what currently exists.** Do not document planned or
in-flight features there — if a note is hard to write because a connecting piece is missing,
record that gap rather than inventing the piece. Fine-grained API detail belongs in
moduledocs; vault notes stay at architecture altitude so they change less often. Give each
Techdocs note an *as-of* marker (commit or date).

**After every block of work, check and update the vault** as part of finishing (alongside
`mix ci`):

- Update `Development/Development.md` phase status when a step's state changes.
- Add or update the relevant `Techdocs/` note when architecture, a data structure, a data
  flow, or an adapter boundary changed — and refresh its *as-of* marker.
- Add or update the relevant `Userguide/` page when the public, user-facing surface changed.
- Record decisions in `Planning/18-decisions.md` and keep index notes' links current.
- Use the obsidian skill for vault edits.

<!-- usage-rules-start -->
<!-- usage_rules-start -->
## usage_rules usage

_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

## Using Usage Rules

Many packages have usage rules, which you should _thoroughly_ consult before taking any
action. These usage rules contain guidelines and rules _directly from the package authors_.
They are your best source of knowledge for making decisions.

## Modules & functions in the current app and dependencies

When looking for docs for modules & functions that are dependencies of the current project,
or for Elixir itself, use `mix usage_rules.docs`

```
# Search a whole module
mix usage_rules.docs Enum

# Search a specific function
mix usage_rules.docs Enum.zip

# Search a specific function & arity
mix usage_rules.docs Enum.zip/1
```

## Searching Documentation

You should also consult the documentation of any tools you are using, early and often. The best
way to accomplish this is to use the `usage_rules.search_docs` mix task. Once you have
found what you are looking for, use the links in the search results to get more detail. For example:

```
# Search docs for all packages in the current application, including Elixir
mix usage_rules.search_docs Enum.zip

# Search docs for specific packages
mix usage_rules.search_docs Req.get -p req

# Search docs for multi-word queries
mix usage_rules.search_docs "making requests" -p req

# Search only in titles (useful for finding specific functions/modules)
mix usage_rules.search_docs "Enum.zip" --query-by title
```

<!-- usage_rules-end -->
<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage

# Elixir Core Usage Rules

## Pattern Matching

- Use pattern matching over conditional logic when possible
- Prefer to match on function heads instead of using `if`/`else` or `case` in function bodies
- `%{}` matches ANY map, not just empty maps. Use `map_size(map) == 0` guard to check for truly empty maps

## Error Handling

- Use `{:ok, result}` and `{:error, reason}` tuples for operations that can fail
- Avoid raising exceptions for control flow
- Use `with` for chaining operations that return `{:ok, _}` or `{:error, _}`

## Common Mistakes to Avoid

- Elixir has no `return` statement, nor early returns. The last expression in a block is always returned.
- Don't use `Enum` functions on large collections when `Stream` is more appropriate
- Avoid nested `case` statements - refactor to a single `case`, `with` or separate functions
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Lists and enumerables cannot be indexed with brackets. Use pattern matching or `Enum` functions
- Prefer `Enum` functions like `Enum.reduce` over recursion
- When recursion is necessary, prefer to use pattern matching in function heads for base case detection
- Using the process dictionary is typically a sign of unidiomatic code
- Only use macros if explicitly requested
- There are many useful standard library functions, prefer to use them where possible

## Function Design

- Use guard clauses: `when is_binary(name) and byte_size(name) > 0`
- Prefer multiple function clauses over complex conditional logic
- Name functions descriptively: `calculate_total_price/2` not `calc/2`
- Predicate function names should not start with `is` and should end in a question mark.
- Names like `is_thing` should be reserved for guards

## Data Structures

- Use structs over maps when the shape is known: `defstruct [:name, :age]`
- Prefer keyword lists for options: `[timeout: 5000, retries: 3]`
- Use maps for dynamic key-value data
- Prefer to prepend to lists `[new | list]` not `list ++ [new]`

## Mix Tasks

- Use `mix help` to list available mix tasks
- Use `mix help task_name` to get docs for an individual task
- Read the docs and options fully before using tasks

## Testing

- Run tests in a specific file with `mix test test/my_test.exs` and a specific test with the line number `mix test path/to/test.exs:123`
- Limit the number of failed tests with `mix test --max-failures n`
- Use `@tag` to tag specific tests, and `mix test --only tag` to run only those tests
- Use `assert_raise` for testing expected exceptions: `assert_raise ArgumentError, fn -> invalid_function() end`
- Use `mix help test` to for full documentation on running tests

## Debugging

- Use `dbg/1` to print values while debugging. This will display the formatted value and other relevant information in the console.

<!-- usage_rules:elixir-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage

# OTP Usage Rules

## GenServer Best Practices

- Keep state simple and serializable
- Handle all expected messages explicitly
- Use `handle_continue/2` for post-init work
- Implement proper cleanup in `terminate/2` when necessary

## Process Communication

- Use `GenServer.call/3` for synchronous requests expecting replies
- Use `GenServer.cast/2` for fire-and-forget messages.
- When in doubt, use `call` over `cast`, to ensure back-pressure
- Set appropriate timeouts for `call/3` operations

## Fault Tolerance

- Set up processes such that they can handle crashing and being restarted by supervisors
- Use `:max_restarts` and `:max_seconds` to prevent restart loops

## Task and Async

- Use `Task.Supervisor` for better fault tolerance
- Handle task failures with `Task.yield/2` or `Task.shutdown/2`
- Set appropriate task timeouts
- Use `Task.async_stream/3` for concurrent enumeration with back-pressure

<!-- usage_rules:otp-end -->
<!-- usage-rules-end -->
