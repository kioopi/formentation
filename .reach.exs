# Architecture policy for `mix reach.check --arch --smells` (part of `mix ci`).
#
# Layers mirror the package boundaries in Planning/04-architecture.md: a
# source-independent core with adapters on both sides (declaration sources
# in, Phoenix projection out). The core must not depend on Phoenix, and JSV
# stays behind the D-008 swap point.
[
  layers: [
    # Pure structural core: paths, nodes, definition, diagnostics, runtime
    # form state, codecs, transport. Source-independent and framework-free.
    core: [
      "Formentation",
      "Formentation.Codec",
      "Formentation.Definition",
      "Formentation.Definition.*",
      "Formentation.Diagnostic",
      "Formentation.Form",
      "Formentation.Form.*",
      "Formentation.Info",
      "Formentation.Info.*",
      "Formentation.InstancePath",
      "Formentation.Issue",
      "Formentation.JSONPointer",
      "Formentation.NodeId",
      "Formentation.Origin",
      "Formentation.Params",
      "Formentation.Presentation",
      "Formentation.Presentation.*",
      "Formentation.Semantic",
      "Formentation.Semantic.*",
      "Formentation.SubmissionBlocker",
      "Formentation.TemplatePath",
      "Formentation.Transport",
      "Formentation.Transport.*",
      "Formentation.Validation",
      "Formentation.ValidationPlan"
    ],
    # Declaration-source adapters. The map source is the in-core reference
    # adapter (D-004); Source.Shared holds adapter-generic compile helpers.
    source: ["Formentation.Source", "Formentation.Source.*"],
    # JSON Schema adapter — the only namespace allowed to touch JSV (D-008).
    json_schema: ["Formentation.JSONSchema", "Formentation.JSONSchema.*"],
    # Phoenix projection layer (D-017). The FormData protocol impl is named
    # Phoenix.HTML.FormData.Formentation.Form by defimpl, hence the second
    # pattern. Formentation.Phoenix itself (the public component surface)
    # has no trailing segment, so it needs its own literal entry alongside
    # the wildcard for its submodules.
    phoenix: [
      "Formentation.Phoenix",
      "Formentation.Phoenix.*",
      "Phoenix.HTML.FormData.Formentation.*"
    ],
    # Step-7 demo application (spec 2026-07-24): the runnable example and
    # its LiveViewTest fixture. Not library code — may call anything and
    # do server-ish IO; kept as a layer so require_all_modules stays strict.
    demo: [
      "FormentationDemo",
      "FormentationDemo.*",
      "Mix.Tasks.Demo"
    ]
  ],
  deps: [
    forbidden: [
      # Core is presentation-independent; nothing below the projection layer
      # may reach it (04-architecture: "The core must not depend on Phoenix").
      {:core, :phoenix},
      {:source, :phoenix},
      {:json_schema, :phoenix},
      # Core does not call into a source adapter; Formentation.compile/2
      # receives one via the :adapter option.
      #
      # Sanctioned exception (D-046): Formentation.compile/2's resolver maps
      # the built-in selectors :map and :json_schema onto adapter modules, so
      # core does *name* both adapters. Those names are returned as values and
      # dispatched dynamically, so no call edge exists and this rule stays
      # green — the rule constrains calls, not literals. Keep it that way:
      # core must never invoke an adapter function directly.
      {:core, :source},
      # Core never calls an adapter: instance validation dispatches through
      # the Formentation.Validation behaviour (D-025), so there is no
      # sanctioned core->json_schema call edge. See the D-046 note above for
      # the name-only selector exception.
      {:core, :json_schema},
      # The source layer stays adapter-generic.
      {:source, :json_schema},
      # Projection reads compiled core state only, never adapters.
      {:phoenix, :json_schema},
      {:phoenix, :source},
      # The library must never depend on the demo.
      {:core, :demo},
      {:source, :demo},
      {:json_schema, :demo},
      {:phoenix, :demo}
    ]
  ],
  calls: [
    forbidden: [
      # The Phoenix boundary at the external-library level: only the
      # projection layer may call Phoenix modules (Transport is explicitly
      # "zero Phoenix dependency").
      {"Formentation.*", ["Phoenix.*"], except: ["Formentation.Phoenix.*"]},
      # JSV never leaks past its swap point (D-008).
      {"Formentation.*", ["JSV.*"], except: ["Formentation.JSONSchema.Validator"]},
      # Render preparation dispatches state-dependent decisions only through
      # Formentation.Phoenix.StateView (D-027); it must never call into
      # Formentation.Form directly. The {:phoenix, :core} layer dependency
      # is sanctioned (the projector reads Definition/Info/Node freely), so
      # no layer rule can express this narrower obligation — only a
      # per-module call rule can. This closes the alias-evasion gap the
      # render_preparation_test.exs "architectural boundary" grep pin cannot see:
      # `alias Formentation.{Form, ...}` (brace syntax) never produces the
      # literal substring "Formentation.Form" the grep looks for, but Reach
      # resolves calls against the call graph after alias resolution, so it
      # catches a `Form.some_function/arity` call regardless of how the
      # alias was spelled.
      # Formentation.Phoenix.ProjectedForm is the sanctioned exception: it is
      # the companion of the FormData implementation and decodes the native
      # projection (definition + root path) on preparation's behalf. That is
      # metadata, not runtime state — submission, issue visibility, and
      # non-field issues must still cross the StateView seam. Do not relieve
      # pressure on this rule by moving further state-dependent decisions into
      # ProjectedForm; the "architectural boundary" tests in
      # render_preparation_test.exs pin both that ProjectedForm never names
      # StateView and that nothing else spells the private projection key.
      {"Formentation.Phoenix.RenderPreparation", ["Formentation.Form", "Formentation.Form.*"]}
    ]
  ],
  effects: [
    # Reach classifies every IO.* call and Enum.each/2 as :io by convention.
    # These modules only use the pure IO.iodata_to_binary/1 (JSON Pointer
    # building) and Enum.each + raise (argument validation) — no real IO.
    # Module overrides take precedence over by_layer.
    allowed: [
      {"Formentation.InstancePath", [:pure, :exception, :io, :unknown]},
      {"Formentation.TemplatePath", [:pure, :exception, :io, :unknown]},
      {"Formentation.JSONPointer", [:pure, :exception, :io, :unknown]},
      {"Formentation.NodeId", [:pure, :exception, :io, :unknown]}
    ],
    # The whole library is pure data transformation; compilation is
    # deterministic (04-architecture: remote I/O belongs behind an explicit
    # resolver). No layer may acquire IO/write/send effects unnoticed.
    by_layer: [
      core: [:pure, :exception, :unknown],
      source: [:pure, :exception, :unknown],
      json_schema: [:pure, :exception, :unknown],
      phoenix: [:pure, :exception, :unknown],
      # Reach's full effect taxonomy (Reach.Effects.effect/0): :pure,
      # :exception, and :unknown from the brief's list plus every real
      # side-effect kind reach classifies (:read — e.g. File.read! for the
      # JSON declaration — :write, :io, :send, :receive, :nif). The demo
      # is not library code, so it is deliberately unconstrained here
      # rather than enumerated effect-by-effect as the code grows in
      # Task 5 (Known uncertainty 2: "don't constrain it").
      demo: [:pure, :read, :write, :io, :send, :receive, :exception, :nif, :unknown]
    ]
  ],
  boundaries: [
    # Shared compile helpers are implementation detail of the adapters.
    internal: ["Formentation.Source.Shared"],
    internal_callers: [
      {"Formentation.Source.Shared",
       ["Formentation.Source.*", "Formentation.JSONSchema", "Formentation.JSONSchema.*"]}
    ]
  ],
  smells: [
    # Fail the gate on new smell findings, matching the strictness of the
    # rest of mix ci (credo --strict, ex_dna --max-clones 0).
    strict: true,
    behaviour_candidate: [
      # The fixtures implement the extracted Formentation.Fixture
      # behaviour; reach's heuristic cannot see @behaviour declarations,
      # so it would keep proposing the extraction it already got.
      #
      # Formentation.Phoenix.StateView (D-027) is a defprotocol with
      # multiple defimpl blocks (Any, Formentation.Form) sharing its
      # callbacks by design — that is what a protocol is. Reach's
      # macro-fact detection only recognizes @behaviour declarations,
      # not defprotocol/defimpl, so it proposes an extraction the
      # dispatch mechanism already provides.
      ignore: [
        modules: [
          "Formentation.Fixtures.*",
          "Formentation.Phoenix.StateView",
          "Formentation.Phoenix.StateView.*"
        ]
      ]
    ]
  ],
  checks: [
    layer_coverage: [
      require_all_modules: true,
      forbid_multiple_matches: true,
      # test/support modules: on elixirc_paths(:test), so reach sees them
      # when `mix ci` runs, but they are not library code and belong to no
      # layer. Formentation.SourceFixture is the D-027 state-view contract
      # proof; its two defimpl-generated modules need no entry, being
      # covered already by the phoenix layer's FormData and
      # Formentation.Phoenix.* patterns. Formentation.Test.FormHelpers is
      # the submit-decision unwrapper shared by state-oriented tests.
      ignore: [
        "Formentation.Fixture",
        "Formentation.Fixtures.*",
        # Ephemeral-port probe for the browser lane's endpoint; test
        # harness support, not library code.
        "Formentation.FreePort",
        "Formentation.HTMLAssertions",
        "Formentation.SourceFixture",
        "Formentation.Test.FormHelpers",
        # Documentation lint run by `mix ci`; build tooling, not library
        # code, so it participates in no layer.
        "Mix.Tasks.Vault.Links",
        # Development inner-loop command; build tooling, same reasoning.
        "Mix.Tasks.Test.Dev"
      ]
    ]
  ],
  tests: [
    hints: [
      {"lib/formentation/phoenix/**", ["test/formentation/phoenix"]},
      {"lib/formentation/json_schema/**", ["test/formentation/json_schema"]},
      {"lib/formentation/source/**", ["test/formentation/source"]},
      {"lib/formentation/form.ex",
       ["test/formentation/form_test.exs", "test/formentation/form_property_test.exs"]}
    ]
  ]
]
