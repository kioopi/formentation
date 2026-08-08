defmodule Formentation.Form do
  @moduledoc """
  The authoritative, immutable form state (D-009): per-field transport
  facts and decode operations, form-level usage (D-014), complete issues,
  and the candidate JSON instance. Pure and usable from IEx. Phoenix
  later projects this state through `Phoenix.HTML.FormData` (step 5) and
  never owns decoding.

  Runtime structure comes from semantic queries. `Form`
  decodes, defaults, materializes, and classifies blockers by semantic
  object boundaries and paths, not by presentation groups or layout order.

  ## Example

      iex> {:ok, definition, []} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, properties: [{"age", %{kind: :integer}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> form = Formentation.Form.new(definition)
      iex> {:ok, candidate, submitted_form} =
      ...>   Formentation.Form.submit(form, %{"age" => "42"})
      iex> candidate
      %{"age" => 42}
      iex> Formentation.Form.field(submitted_form, ["age"]).display_value
      "42"
  """

  alias Formentation.{
    Codec,
    Definition,
    Info,
    InstancePath,
    Issue,
    Params,
    SubmissionBlocker,
    Transport,
    ValidationPlan
  }

  alias Formentation.Definition.Semantic
  alias Formentation.Form.FieldState

  @enforce_keys [:definition, :original]
  defstruct [
    :definition,
    :original,
    :params,
    :action,
    transports: %{},
    operations: %{},
    usage: %{},
    issues: %{},
    candidate: :none
  ]

  @type t :: %__MODULE__{
          definition: Definition.t(),
          original: map(),
          params: map() | nil,
          action: nil | :change | :submit,
          transports: %{InstancePath.t() => FieldState.transport()},
          operations: %{InstancePath.t() => FieldState.operation()},
          usage: %{InstancePath.t() => :used | :unused},
          issues: %{InstancePath.t() => [Issue.t()]},
          candidate: {:ok, map()} | :none
        }

  @type submission_status ::
          :ready
          | :undecodable
          | {:invalid, [Issue.t()]}
          | {:blocked, [SubmissionBlocker.t()]}

  @type submit_result ::
          {:ok, candidate :: map(), submitted_form :: t()}
          | {:error, submitted_form :: t()}

  @doc """
  A pristine form over `data`. No transports, operations, or usage yet;
  the candidate is the (possibly defaulted) original data, already
  validated when the definition carries a validation plan.
  `defaults: :apply` fills declared defaults into absent keys — defaults
  never overwrite provided values and never apply again on transitions.
  """
  @spec new(Definition.t(), map(), keyword()) :: t()
  def new(%Definition{} = definition, data \\ %{}, opts \\ []) when is_map(data) do
    original = initial_data(definition, data, Keyword.get(opts, :defaults))

    %__MODULE__{definition: definition, original: original, candidate: {:ok, original}}
    |> revalidate()
  end

  @doc """
  The assembled per-field read model at `segments` — see
  `Formentation.Form.FieldState`. Total: paths the form has never seen
  answer with the defaults (`:not_provided`, `:keep`, `:unknown`, no
  issues).
  """
  @spec field(t(), [InstancePath.segment()]) :: FieldState.t()
  def field(%__MODULE__{} = form, segments) when is_list(segments) do
    path = InstancePath.new!(segments)
    transport = Map.get(form.transports, path, :not_provided)
    operation = Map.get(form.operations, path, :keep)

    %FieldState{
      path: path,
      transport: transport,
      operation: operation,
      usage: Map.get(form.usage, path, :unknown),
      issues: Map.get(form.issues, path, []),
      display_value: display_value(form, path, transport, operation)
    }
  end

  @doc """
  The materialized JSON instance this form would submit, or `:none`
  while any field fails to decode (D-012).
  """
  @spec candidate(t()) :: {:ok, map()} | :none
  def candidate(%__MODULE__{candidate: candidate}), do: candidate

  @doc """
  Every issue on the form, decode and validation alike, regardless of
  visibility — pair with `show_issues?/2` before rendering.
  """
  @spec issues(t()) :: [Issue.t()]
  def issues(%__MODULE__{issues: issues}) do
    issues |> Map.values() |> List.flatten()
  end

  @doc "The issues at exactly `segments`; `[]` when there are none."
  @spec issues(t(), [InstancePath.segment()]) :: [Issue.t()]
  def issues(%__MODULE__{issues: issues}, segments) when is_list(segments) do
    Map.get(issues, InstancePath.new!(segments), [])
  end

  @doc """
  The concrete `Formentation.SubmissionBlocker`s for this form's current
  candidate, in unsupported-node declaration order; `[]` while the
  candidate is `:none` (classification defers with validation, D-012).

  A blocker is derived, never stored: it relates a required-but-absent
  preserve-only value, or authoritative validation issues at or below a
  preserve-only semantic node.
  `issues/1` continues to return every underlying issue unchanged.
  """
  @spec submission_blockers(t()) :: [SubmissionBlocker.t()]
  def submission_blockers(%__MODULE__{candidate: :none}), do: []

  def submission_blockers(%__MODULE__{candidate: {:ok, candidate}} = form) do
    form.definition
    |> Info.unsupported_nodes_with_paths()
    |> Enum.flat_map(fn {path, node} -> classify(form, path, node, candidate) end)
  end

  @doc """
  Whether this form is submittable, and why not. Precedence:
  `:none` candidate → `:undecodable`; any blockers → `{:blocked, blockers}`
  (blockers win over ordinary issues, but nothing is discarded — `issues/1`
  still returns everything); otherwise remaining issues → `{:invalid, issues}`
  ordered by instance path; otherwise `:ready`.

  Readiness data, not visibility policy: independent of `form.action`.

      iex> {:ok, definition, _} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, required: ["attachment"],
      ...>       properties: [{"attachment", %{kind: :file}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> form = Formentation.Form.new(definition, %{})
      iex> match?({:blocked, [%Formentation.SubmissionBlocker{code: :unsupported_required}]},
      ...>   Formentation.Form.submission_status(form))
      true
  """
  @spec submission_status(t()) :: submission_status()
  def submission_status(%__MODULE__{candidate: :none}), do: :undecodable

  def submission_status(%__MODULE__{} = form) do
    case submission_blockers(form) do
      [_ | _] = blockers ->
        {:blocked, blockers}

      [] ->
        case ordered_issues(form) do
          [] -> :ready
          issues -> {:invalid, issues}
        end
    end
  end

  @doc """
  Whether the user has interacted with the field at `segments` (D-014).
  `:unknown` means the transport has not mentioned the path yet — usage
  is never fabricated.
  """
  @spec usage(t(), [InstancePath.segment()]) :: :used | :unused | :unknown
  def usage(%__MODULE__{usage: usage}, segments) when is_list(segments) do
    Map.get(usage, InstancePath.new!(segments), :unknown)
  end

  @doc """
  D-014's visibility rule: existence and visibility never interact with
  storage — `issues/1,2` always returns everything; this answers whether
  a renderer should show them. Scalar-field issues show on submit or
  once the field is used. Group and root issues show only on submit:
  parent usage propagates from descendants, so following `:used` there
  would surface root-level issues on the first keystroke.
  """
  @spec show_issues?(t(), [InstancePath.segment()]) :: boolean()
  def show_issues?(%__MODULE__{} = form, segments) when is_list(segments) do
    form.action == :submit or field_used?(form, segments)
  end

  defp field_used?(form, segments) do
    case Semantic.find(form.definition, segments) do
      %Semantic.Entry{kind: :field} -> usage(form, segments) == :used
      _object_unsupported_or_missing -> false
    end
  end

  @doc """
  Whether the source considers this form submitted, in the semantic
  sense projection needs — not "the Phoenix action equals a particular
  atom". True exactly when the last transition carried `event: :submit`.

      iex> {:ok, definition, []} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, properties: [{"a", %{kind: :string}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> form = Formentation.Form.new(definition)
      iex> {:ok, _candidate, submitted_form} =
      ...>   Formentation.Form.submit(form, %{"a" => "x"})
      iex> {Formentation.Form.submitted?(form), Formentation.Form.submitted?(submitted_form)}
      {false, true}
  """
  @spec submitted?(t()) :: boolean()
  def submitted?(%__MODULE__{action: action}), do: action == :submit

  @doc """
  Applies a full-form replace transition (D-013): normalizes the
  envelope's values, decodes every declared field, merges usage,
  rematerializes the candidate, and revalidates. Raises `ArgumentError`
  on reserved envelope shapes (`:patch` mode, non-root scope) and
  non-map values.
  """
  @spec transition(t(), Params.t()) :: t()
  def transition(%__MODULE__{} = form, %Params{} = params) do
    check_envelope!(params)
    normalized = Transport.normalize(params.values)

    {transports, operations, decode_issues} =
      decode(form.definition, normalized.domain_params)

    %__MODULE__{
      form
      | params: normalized.phoenix_params,
        action: params.event,
        transports: transports,
        operations: operations,
        issues: decode_issues,
        usage: Map.merge(form.usage, normalized.usage),
        candidate: materialize(form, operations)
    }
    |> revalidate()
  end

  @doc """
  Applies a full-form `:change` replace transition — the LiveView
  `phx-change` entry point. `values` is the raw string-keyed params
  subtree for this form (under embedding, the caller plucks it from the
  event params first). Sugar for `transition/2` with a `:change` envelope.

      iex> {:ok, definition, []} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, properties: [{"age", %{kind: :integer}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> form = Formentation.Form.validate(Formentation.Form.new(definition), %{"age" => "42"})
      iex> {form.action, Formentation.Form.candidate(form)}
      {:change, {:ok, %{"age" => 42}}}
  """
  @spec validate(t(), map()) :: t()
  def validate(%__MODULE__{} = form, values) when is_map(values) do
    transition(form, %Params{values: values, event: :change})
  end

  @doc """
  Applies a full-form `:submit` replace transition and returns the
  application-facing submission decision. Only `submission_status/1 ==
  :ready` succeeds; undecodable, blocked, and invalid submitted forms are
  returned for redisplay with raw input, usage, issues, and visibility
  state intact.

      iex> {:ok, definition, []} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, properties: [{"age", %{kind: :integer}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> {:ok, candidate, submitted_form} =
      ...>   Formentation.Form.submit(Formentation.Form.new(definition), %{"age" => "42"})
      iex> {candidate, submitted_form.action}
      {%{"age" => 42}, :submit}
      iex> {:error, submitted_form} =
      ...>   Formentation.Form.submit(Formentation.Form.new(definition), %{"age" => "x"})
      iex> {submitted_form.action, Formentation.Form.candidate(submitted_form)}
      {:submit, :none}
  """
  @spec submit(t(), map()) :: submit_result()
  def submit(%__MODULE__{} = form, values) when is_map(values) do
    submitted_form = transition(form, %Params{values: values, event: :submit})

    case submission_status(submitted_form) do
      :ready ->
        {:ok, candidate} = candidate(submitted_form)
        {:ok, candidate, submitted_form}

      :undecodable ->
        {:error, submitted_form}

      {:blocked, _blockers} ->
        {:error, submitted_form}

      {:invalid, _issues} ->
        {:error, submitted_form}
    end
  end

  defp check_envelope!(%Params{mode: :patch}) do
    raise ArgumentError, ":patch transitions are reserved and not implemented (D-013)"
  end

  defp check_envelope!(%Params{scope: scope}) when scope != [] do
    raise ArgumentError,
          "non-root scope is reserved and not implemented (step-4 spec, decision 7)"
  end

  defp check_envelope!(%Params{values: values}) when is_map(values), do: :ok

  defp check_envelope!(%Params{values: other}) do
    raise ArgumentError, "envelope values must be a map, got: #{inspect(other)}"
  end

  # D-012: raw undecoded text never reaches validation; while any decode
  # fails there is no candidate and validation defers entirely. The
  # validation slot is an opaque, module-owned ValidationPlan; nil means
  # the source provides no authoritative instance validation (map source,
  # for now).
  defp revalidate(%__MODULE__{} = form) do
    %{form | issues: Map.merge(form.issues, validation_issues(form))}
  end

  defp validation_issues(%__MODULE__{candidate: :none}), do: %{}
  defp validation_issues(%__MODULE__{definition: %Definition{validation: nil}}), do: %{}

  defp validation_issues(%__MODULE__{
         candidate: {:ok, instance},
         definition: %Definition{validation: %ValidationPlan{module: module, artifact: artifact}}
       }) do
    artifact
    |> module.validate(instance)
    |> Enum.group_by(& &1.path)
  end

  defp initial_data(definition, data, :apply), do: apply_defaults(Semantic.root(definition), data)
  defp initial_data(_definition, data, _other), do: data

  # Defaults apply only at explicit initialization and never overwrite
  # provided keys; nested objects are created only when a default lands
  # inside them. Transitions never call this — a cleared field stays
  # cleared (the phase's "default never mutates data" caution).
  defp apply_defaults(%Semantic.Entry{kind: :object} = entry, data) do
    entry
    |> Semantic.direct_children()
    |> Enum.reduce(data, fn child, acc -> apply_default(child, acc) end)
  end

  defp apply_default(
         %Semantic.Entry{kind: :field, name: name, node: %Semantic.Field{default: default}},
         acc
       )
       when not is_nil(default) do
    Map.put_new(acc, name, default)
  end

  # A present value at a nesting key is descended into only when it is
  # already a map; any other present value (including an explicit `nil`,
  # which legitimately occurs in original data) is left completely
  # untouched — provided keys are never overwritten.
  defp apply_default(%Semantic.Entry{kind: :object, name: name} = entry, acc)
       when is_binary(name) do
    case Map.fetch(acc, name) do
      {:ok, value} when is_map(value) -> Map.put(acc, name, apply_defaults(entry, value))
      {:ok, _non_map} -> acc
      :error -> put_created_defaults(entry, acc, name)
    end
  end

  defp apply_default(_entry, acc), do: acc

  defp put_created_defaults(entry, acc, name) do
    child = apply_defaults(entry, %{})

    if child == %{} do
      acc
    else
      Map.put(acc, name, child)
    end
  end

  defp decode(definition, domain_params) do
    definition
    |> Semantic.fields()
    |> Enum.reduce({%{}, %{}, %{}}, fn entry, {transports, operations, issues} ->
      path = entry.instance_path
      transport = transport_at(domain_params, path)
      operation = operation_for(entry.node, transport, path)

      issues =
        case operation do
          {:invalid, issue} -> Map.put(issues, path, [issue])
          _other -> issues
        end

      {Map.put(transports, path, transport), Map.put(operations, path, operation), issues}
    end)
  end

  # D-016: read-only fields do not participate in the replace scope —
  # whatever the transport carried, the original value is kept.
  defp operation_for(%Semantic.Field{read_only?: true}, _transport, _path), do: :keep
  defp operation_for(_node, :not_provided, _path), do: :unset
  defp operation_for(node, {:provided, raw}, path), do: Codec.decode(node.value_type, raw, path)

  defp transport_at(params, %InstancePath{segments: segments}) do
    {parent_segments, [name]} = Enum.split(segments, -1)

    case params_at(params, parent_segments) do
      {:ok, parent} -> fetch_transport(parent, name)
      :error -> :not_provided
    end
  end

  defp fetch_transport(params, name) when is_map(params) do
    case Map.fetch(params, name) do
      {:ok, raw} -> {:provided, raw}
      :error -> :not_provided
    end
  end

  defp fetch_transport(_params, _name), do: :not_provided

  defp params_at(params, []), do: {:ok, params}

  defp params_at(params, [segment | rest]) when is_map(params) do
    case Map.fetch(params, segment) do
      {:ok, child} -> params_at(child, rest)
      :error -> :error
    end
  end

  defp params_at(_params, _segments), do: :error

  defp materialize(form, operations) do
    invalid? =
      Enum.any?(operations, fn {_path, operation} -> match?({:invalid, _}, operation) end)

    if invalid? do
      :none
    else
      root = Semantic.root(form.definition)
      {:ok, materialize_object(root, form.original, [], operations)}
    end
  end

  # Declared children rebuild from operations; keys the definition does
  # not describe are preserved from the original data, as are unsupported
  # nodes' values (preserve inactive data — D-009).
  defp materialize_object(%Semantic.Entry{kind: :object} = entry, original, _prefix, operations) do
    original = if is_map(original), do: original, else: %{}

    {declared_result, declared_names} =
      materialize_children(entry, original, operations)

    original
    |> Map.drop(MapSet.to_list(declared_names))
    |> Map.merge(declared_result)
  end

  # Content-derived presence (D-026): a data-nesting object is emitted only
  # when recursive materialization leaves at least one declared or preserved
  # key. `required?` is a validation constraint and never manufactures an
  # object; presence is decided only after declared-child materialization and
  # original unknown/unsupported-data preservation have run. The explicit
  # `:absent | {:present, map()}` result is the extension point for future
  # collections, branches, and group-level presence transport — do not
  # collapse it into an `if value == %{}` at the call site.
  defp materialize_nested_object(entry, original, operations) do
    case materialize_object(entry, original, [], operations) do
      map when map_size(map) == 0 -> :absent
      map -> {:present, map}
    end
  end

  defp materialize_children(%Semantic.Entry{kind: :object} = entry, original, operations) do
    entry
    |> Semantic.direct_children()
    |> Enum.reduce({%{}, MapSet.new()}, fn child, {acc, declared} ->
      materialize_child(child, original, operations, acc, declared)
    end)
  end

  defp materialize_child(
         %Semantic.Entry{kind: :field, name: name, instance_path: path},
         original,
         operations,
         acc,
         declared
       ) do
    declared = MapSet.put(declared, name)

    case Map.get(operations, path, :keep) do
      {:set, value} -> {Map.put(acc, name, value), declared}
      :unset -> {acc, declared}
      :keep -> {put_original(acc, original, name), declared}
    end
  end

  defp materialize_child(
         %Semantic.Entry{kind: :object, name: name} = entry,
         original,
         operations,
         acc,
         declared
       ) do
    # Claim the name even when the object is absent, so an originally
    # present group is not accidentally restored by unknown-key
    # preservation in `materialize_object/4` (D-026).
    declared = MapSet.put(declared, name)

    case materialize_nested_object(entry, Map.get(original, name, %{}), operations) do
      {:present, value} -> {Map.put(acc, name, value), declared}
      :absent -> {acc, declared}
    end
  end

  defp materialize_child(
         %Semantic.Entry{kind: :unsupported, name: name},
         original,
         _operations,
         acc,
         declared
       ) do
    {put_original(acc, original, name), MapSet.put(declared, name)}
  end

  defp put_original(acc, original, name) do
    case Map.fetch(original, name) do
      {:ok, value} -> Map.put(acc, name, value)
      :error -> acc
    end
  end

  # A preserve-only node blocks when a required value is missing from an
  # active parent, or when it owns authoritative validation issues at/below
  # its path. Missing-required wins the code; owned issues always ride along.
  defp classify(form, path, %Semantic.Unsupported{} = node, candidate) do
    owned = owned_issues(form, path)

    cond do
      missing_required?(node, path, candidate) ->
        [blocker(path, node, :unsupported_required, owned)]

      owned != [] ->
        [blocker(path, node, :unsupported_invalid, owned)]

      true ->
        []
    end
  end

  defp blocker(path, node, code, owned) do
    %SubmissionBlocker{
      path: path,
      node_id: node.id,
      code: code,
      message: blocker_message(code),
      issues: owned
    }
  end

  defp blocker_message(:unsupported_required) do
    "This required property cannot be supplied by this form because its declaration is unsupported."
  end

  defp blocker_message(:unsupported_invalid) do
    "This property cannot be corrected by this form because its declaration is unsupported and its original value is preserved."
  end

  # Source-neutral: requiredness and candidate presence are facts on the
  # definition and the post-#1 candidate, not on any validator's code. An
  # inactive nested parent (absent object) makes the child inactive (D-026).
  defp missing_required?(%Semantic.Unsupported{required?: false}, _path, _candidate), do: false

  defp missing_required?(%Semantic.Unsupported{name: name, required?: true}, path, candidate) do
    case parent_object(candidate, path) do
      {:ok, object} when is_map(object) -> not Map.has_key?(object, name)
      _absent_or_non_map -> false
    end
  end

  defp parent_object(candidate, %InstancePath{segments: segments}) do
    fetch_in(candidate, Enum.drop(segments, -1))
  end

  defp fetch_in(value, []), do: {:ok, value}

  defp fetch_in(map, [segment | rest]) when is_map(map) do
    case Map.fetch(map, segment) do
      {:ok, value} -> fetch_in(value, rest)
      :error -> :error
    end
  end

  defp fetch_in(_value, _segments), do: :error

  # Issues at or below the unsupported path, validation-source only, in a
  # deterministic order (by path segments; validator order within a path).
  defp owned_issues(%__MODULE__{issues: issues}, unsupported_path) do
    issues
    |> Enum.filter(fn {issue_path, _list} ->
      InstancePath.ancestor_or_self?(unsupported_path, issue_path)
    end)
    |> Enum.sort_by(fn {issue_path, _list} -> issue_path.segments end)
    |> Enum.flat_map(fn {_path, list} -> Enum.filter(list, &(&1.source == :validation)) end)
  end

  defp ordered_issues(%__MODULE__{issues: issues}) do
    issues
    |> Enum.sort_by(fn {path, _list} -> path.segments end)
    |> Enum.flat_map(fn {_path, list} -> list end)
  end

  defp display_value(form, path, _transport, :keep) do
    form.original |> value_at(path.segments) |> encode_value()
  end

  defp display_value(_form, _path, {:provided, raw}, _operation) when is_binary(raw), do: raw
  defp display_value(_form, _path, {:provided, raw}, _operation), do: encode_value(raw)
  defp display_value(_form, _path, :not_provided, :unset), do: ""

  defp display_value(form, path, :not_provided, _operation) do
    form.original |> value_at(path.segments) |> encode_value()
  end

  defp value_at(data, []), do: data

  defp value_at(data, [segment | rest]) when is_map(data),
    do: value_at(Map.get(data, segment), rest)

  defp value_at(_data, _segments), do: nil

  defp encode_value(nil), do: ""
  defp encode_value(true), do: "true"
  defp encode_value(false), do: "false"
  defp encode_value(value) when is_binary(value), do: value
  defp encode_value(value) when is_integer(value) or is_float(value), do: to_string(value)
  defp encode_value(value), do: inspect(value)
end
