---
title: Browser testing
aliases:
  - Browser testing
  - Browser-real tests
  - Playwright suite
tags:
  - formentation
  - techdocs
  - testing
status: current
---

# Browser testing

> [!note] As of 2026-08-04 · browser-test suite, prepared DOM identities, ephemeral test port
> Describes the opt-in Playwright suite as built: the harness, the config
> posture, and what each seed test pins. This is additive to
> [[test-and-verification-architecture|the test architecture]]'s mechanism
> table, not a replacement for it — the suite covers one specific gap that
> mechanism describes: `Phoenix.LiveViewTest` never runs a browser.

## Why this suite exists

`Phoenix.LiveViewTest`'s `form/3` plus `render_change/1`/`render_submit/1`
never runs LiveView's client-side `LiveSocket` JS hook — the piece of the
stack that applies the `_unused_<field>` marker convention before a request
reaches the server ([[18-decisions#D-021 — LiveView integration is wrappers plus a demo, not framework machinery|D-021]]).
A test suite built entirely on `LiveViewTest` can assert what the *server*
does with markers it receives, but it cannot assert that a real browser
*produces* them the way the design assumes. [[18-decisions#D-022 — Browser-real tests are an opt-in, demo-driven Playwright suite|D-022]]
closes that gap with a small, opt-in suite that drives the demo through an
actual Chromium instance.

## Toolchain — mise, not `assets/`

The suite depends on `phoenix_test_playwright` (which pulls in `phoenix_test`
transitively), added to `mix.exs` as `only: :test, runtime: false`. Rather than the conventional
Phoenix pattern (`cd assets && npm install playwright`, a committed
`node_modules`), Playwright is installed as a pinned tool via the mise
`npm:` backend:

```toml
# mise.toml
[tools]
"npm:playwright" = "1.61.1"

[tasks.playwright-browsers]
description = "Download the Chromium build matching the pinned Playwright (idempotent)"
run = "playwright install chromium"
```

`mise install` installs the `npm:playwright` package into mise's own tool
directory (not the project); `mise run playwright-browsers` downloads the
matching Chromium build into `~/.cache/ms-playwright`. There is no `assets/`
directory in this repository and no committed `node_modules` — the whole
mechanism lives in mise-managed paths outside the tree.

`phoenix_test_playwright` hard-codes its own driver lookup as
`assets_dir/node_modules/playwright/cli.js`, which assumes the conventional
layout. `test/test_helper.exs` bridges the gap by asking mise where it put
the package and pointing `assets_dir` at its `lib/` subdirectory:

```elixir
assets_dir =
  System.get_env("PHX_TEST_PLAYWRIGHT_ASSETS_DIR") ||
    case System.cmd("mise", ["where", "npm:playwright"], stderr_to_stdout: true) do
      {path, 0} -> Path.join(String.trim(path), "lib")
      {out, _} -> raise "Playwright not found (`mise where npm:playwright` failed): #{out}. " <>
                          "Run `mise install` and `mise run playwright-browsers`."
    end
```

`mise where npm:playwright`'s output already ends in a path whose `lib/`
holds `node_modules/playwright/cli.js`, so no `node_modules` needs to exist
inside this project at all. `PHX_TEST_PLAYWRIGHT_ASSETS_DIR` overrides the
`mise where` call outright — the one supported escape hatch for a
non-standard install.

## Config posture — no `config/` directory, gated on one env var

Formentation ships no `config/` directory; every setting the demo or the
test suite needs lives in `test/test_helper.exs`, and the browser-specific
half of it is gated behind `PLAYWRIGHT_E2E`:

```elixir
browser? = !!System.get_env("PLAYWRIGHT_E2E")
```

When `browser?` is false — every plain `mix test` — the demo endpoint gets
`server: false` and nothing Playwright-related runs; `test_helper.exs` is
otherwise byte-for-byte the same file. When `browser?` is true, `test_helper.exs`:

- configures `FormentationDemo.Endpoint` with `server: true`,
  `adapter: Bandit.PhoenixAdapter`, listening on `127.0.0.1` at a port
  `Formentation.FreePort.pick/0` obtains from the kernel;
- sets the `phoenix_test` application env — `otp_app: :formentation`,
  `playwright: [assets_dir: ..., headless: true, timeout: to_timeout(second: 5)]`,
  and `base_url` from the endpoint's own `url()`;
- starts `PhoenixTest.Playwright.Supervisor`.

The port is not fixed. `Formentation.FreePort.pick/0` binds port 0, reads
back the port the kernel assigned, and releases it, so the endpoint takes
a port nothing else holds — two concurrent browser runs, or an
interactive `mix demo`, can never collide, and no command needs a `PORT`
prefix. It is chosen before boot because `Phoenix.Endpoint` caches
`url/0` from the `:url` config at init; `base_url` and
`test/browser/demo_http_smoke_test.exs` both read that same `url/0`, so
they follow automatically.

The suite runs `async: true` and shares one demo server across its tests, so
under load a `fill_in` → `phx-change` → websocket → DOM patch
round-trip can exceed PhoenixTest's default 2s assertion timeout; the
`timeout: to_timeout(second: 5)` above absorbs that.

This timeout was originally raised in the belief that the suite's
intermittent failures were load-timing contention rather than a
correctness race. That was wrong — see [[#Wait for the LiveSocket join before interacting|the join race below]],
which no timeout can fix. The 5s value is still a reasonable default for
genuine round-trip latency, but it is not what makes the suite reliable.

## Tag and runner — `browser: :chromium`, not bare `:browser`

The tests carry `@moduletag browser: :chromium` rather than the more
obvious bare `@moduletag :browser`. `PhoenixTest.Playwright.Case`'s
`setup_all` reads the same `:browser` key out of ExUnit tags to pick the
driver's browser engine (`:chromium` / `:firefox` / …, defaulting to
`:chromium`); a bare atom tag sets `browser: true`, and `true` is not a
valid engine name, so NimbleOptions rejects it and the setup crashes.
Pinning the value to `:chromium` — already the default — keeps the tag
under the literal key `:browser`, so `ExUnit.configure(exclude: [:browser])`
(set unconditionally at the bottom of `test_helper.exs`) still excludes it
by presence of that key, and `--only browser` still selects it.

`mix test.browser` is a **function alias**, not the more common
`["cmd ..."]` shell-out form:

```elixir
aliases: [
  # ...
  "test.browser": [&test_browser/1]
]

defp test_browser(args) do
  System.put_env("PLAYWRIGHT_E2E", "1")
  Mix.Task.run("test", ["--only", "browser" | args])
end
```

`mix cmd PLAYWRIGHT_E2E=1 mix test --only browser` would have been the
natural one-liner, but since Elixir 1.19 `mix cmd` no longer shells out —
it tries to exec `PLAYWRIGHT_E2E=1` as a program name rather than treating
it as an environment assignment. Setting the env var directly in Elixir and
delegating to `Mix.Task.run/2` in-process sidesteps that. `cli/0` also lists
`"test.browser": :test` under `preferred_envs`, so the alias runs in the
`:test` Mix env without an explicit `MIX_ENV=test`.

`mix ci` never runs this alias — it is excluded from CI by design, not by
oversight; see [[test-and-verification-architecture#Static gates — `mix ci`|the static gates note]].

To iterate on a single test file: `PLAYWRIGHT_E2E=1 mix test <file> --only
browser` (bypassing the alias, since `mix test.browser` doesn't forward a
file argument ahead of `--only browser` today — pass it after, as `args`).

## What the seed tests pin

All live in `test/browser/pump_inspection_browser_test.exs`, driving
`FormentationDemo.PumpInspectionLive` at `/`:

1. **Valid-submit smoke** — fills in the three blank required fields
   (`Serial number`, `Condition`, and `Mounting`), clicks Save, and asserts the decoded
   candidate JSON appears in `pre#decoded-candidate`. Baseline: the whole
   stack works end to end through a real browser.
2. **`_unused_` gating of a pristine required field** ([[18-decisions#D-014 — Usage is a first-class interaction axis|D-014]]) —
   loads the form, asserts the blank required `serial_number`'s error is
   hidden, edits an unrelated field (`Operating hours`), and asserts the
   error *stays* hidden because `serial_number` was never touched. Then
   unchecks native validation and submits, asserting the same error
   *becomes* visible. This is the truth `Phoenix.LiveViewTest` cannot
   express at all — under `LiveViewTest`, the whole form re-serializes on
   every event and the field would already show `:used` from the first
   `render_change/1`.
3. **Integer raw-text preservation** ([[18-decisions#D-021 — LiveView integration is wrappers plus a demo, not framework machinery|D-021]]) —
   types `"51o2"` into `Operating hours` (rendered as `type="text"
   inputmode="numeric"`, so the browser accepts the non-numeric text
   unlike the `type="number"` control it replaced), asserts the live DOM
   attribute, and proves both the decode error and raw text survive the
   live round-trip.
4. **General-number raw-text preservation** ([[18-decisions#D-038 — Semantic value type and abstract widget are orthogonal prepared facts|D-038]]) —
   types the failed exponent attempt `"-1.5e"` into `Voltage (V)`, asserts
   its live `inputmode="decimal"` attribute, and proves the decode error and
   exact raw attempt survive the live round-trip. This tests DOM attributes and
   raw preservation, not a platform-dependent soft-keyboard layout.
5. **Error-summary anchor focus** — unchecks native validation, submits a
   blank form, clicks the `Serial number:` link inside the error summary
   (`.ftn-error-summary[role='alert']`), and asserts keyboard focus lands
   on `#ftn--asset_payload--field--control--serial_number`. This is an end-to-end interaction
   (`click` → focus movement) with no server-side equivalent to assert.
6. **Radio-summary anchor focus** — unchecks native validation, submits a
   blank form, clicks `Mounting:` in the error summary, and verifies focus lands on
   the radio fieldset's prepared container id; the fieldset is programmatically
   focusable with `tabindex="-1"` without entering ordinary tab order.

## The native-validation finding and its toggle (D-023)

Writing test 2 surfaced a finding that could not have appeared under
`LiveViewTest`: the reference theme emits native HTML5 constraint
attributes (`required`, `minlength`) alongside Formentation's own
server-side validation. In a real browser, native validation intercepts a
submit of a blank or invalid form *before* it is ever sent — the click on
Save never reaches the server at all, so Formentation's decode, its
`required` error, and its submit-gated error summary are all unreachable.
`LiveViewTest` has no concept of a browser's constraint-validation UI, so
this gap is invisible to it entirely.

Rather than drop native validation from the reference theme — treated as a
genuine, deliberately-kept feature ([[18-decisions#D-023 — The demo keeps native validation, behind a toggle|D-023]]),
consistent with the number widget's own earlier trade-off toward
`type="text"` ([[18-decisions#D-021 — LiveView integration is wrappers plus a demo, not framework machinery|D-021]]) —
the pump-inspection demo (`demo/formentation_demo/pump_inspection_live.ex`)
gained a checkbox, `#toggle-native-validation`, labeled "Native browser
validation". Checking it (the default) renders the `<.form>` without
`novalidate`; unchecking it flips `novalidate={not @native_validation}` to
`true`. HEEx renders the boolean attribute as `novalidate=""`, so the two
submit-driven tests (2 and 4 above) assert its presence with the CSS
`[novalidate]` selector rather than a value comparison, and both uncheck
the box before clicking Save — otherwise the click never leaves the
browser. The toggle is also an exploration aid on its own: checking it back
on shows native validation's browser-native error bubbles beside
Formentation's accessible summary for direct comparison.

## Wait for the LiveSocket join before interacting

Every test enters through a `visit_connected/2` helper rather than
`visit/2` directly, because `visit/2` returns on the page `load` event
while LiveView attaches its client-side handlers only after the
LiveSocket *joins* — strictly later.

Interacting in that window is silently lost: `fill_in` types into the
input, but no `phx-change` is pushed, so the server never sees an event
and the DOM never patches. The symptom is a later assertion failing with
`Could not find element`, which reads like a slow page but is not — the
event is never coming, so no timeout rescues it. Raising the assertion
timeout from 5s to 30s changed nothing except making failures take 30s.
Diagnosis came from instrumenting the demo's `handle_event("validate", …)`:
on a failing run the log showed the socket connected and **zero** handle-event
lines.

The helper waits on `.phx-connected`, LiveView's own join marker.
Asserting `form#asset-form` does *not* work as a substitute — that element
is in the static render and matches before the join, which is why tests
that already did so still flaked. The join gets a longer (15s) timeout of
its own because it is the one step that legitimately takes a while on a
loaded machine; every later assertion keeps the default 5s so real
regressions still fail fast.

Measured on this suite, whole runs failed out of 8, with half the cores
busy-looping to stand in for a loaded CI runner: **4/8 before, 0/8 after**;
idle, 0/12 after. Under full CPU saturation the join itself starves and
runs still fail — not a regime worth chasing, but the reason the timeout
is generous rather than tight.

This is also why the CI browser job is `continue-on-error: true`, and why
an earlier attempt to fix the same flakiness by raising the timeout
(“Raise browser-test assertion timeout to 5s”) could not have worked.

## Minor gotchas worth knowing

- `click_link`/`click_button` need an explicit `nil` selector argument
  when passed opts: `click_link(nil, "Serial number:", exact: false)` —
  the two-argument form is `click_link(session, text)`, and the three-arg
  form's first position is a CSS selector, not text.
- HEEx renders `novalidate={false}` as no attribute and `novalidate={true}`
  as `novalidate=""`, never `novalidate="true"`/`novalidate="false"` — the
  presence selector `[novalidate]` is therefore the only reliable
  assertion.

## Related notes

- [[test-and-verification-architecture|Test and verification architecture]] — where this suite sits among the other verification mechanisms
- [[18-decisions#D-022 — Browser-real tests are an opt-in, demo-driven Playwright suite|D-022]] · [[18-decisions#D-023 — The demo keeps native validation, behind a toggle|D-023]]
- [[16-open-questions|Open questions]] — the step-7 question this suite answers
- [[Techdocs]] · [[Formentation|Vault entry note]]
