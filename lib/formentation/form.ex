defmodule Formentation.Form do
  @moduledoc """
  The authoritative, immutable form state (D-009): per-field transport
  facts and decode operations, form-level usage (D-014), complete issues,
  and the candidate JSON instance. Pure and usable from IEx. Phoenix
  later projects this state through `Phoenix.HTML.FormData` (step 5) and
  never owns decoding.

  ## Example

      iex> {:ok, definition, []} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, properties: [{"age", %{kind: :integer}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> form = Formentation.Form.new(definition)
      iex> form =
      ...>   Formentation.Form.transition(form, %Formentation.Params{
      ...>     values: %{"age" => "42"},
      ...>     event: :submit
      ...>   })
      iex> Formentation.Form.candidate(form)
      {:ok, %{"age" => 42}}
      iex> Formentation.Form.field(form, ["age"]).display_value
      "42"
  """

  alias Formentation.{Codec, Definition, Info, InstancePath, Issue, Node, Params, Transport}
  alias Formentation.Form.FieldState
  alias Formentation.JSONSchema.Validator

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

  @doc """
  A pristine form over `data`. No transports, operations, or usage yet;
  the candidate is the (possibly defaulted) original data, already
  schema-validated when the definition carries a validator.
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
  Every issue on the form, decode and schema alike, regardless of
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
    case Info.node_at(form.definition, segments) do
      %Node.Field{} -> usage(form, segments) == :used
      _group_root_or_unknown -> false
    end
  end

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
  Applies a full-form `:submit` replace transition — the LiveView
  `phx-submit` entry point. Submit opens the D-014 visibility gate:
  every stored issue, including root and group issues, becomes visible.

      iex> {:ok, definition, []} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, properties: [{"age", %{kind: :integer}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> form = Formentation.Form.submit(Formentation.Form.new(definition), %{"age" => "x"})
      iex> {form.action, Formentation.Form.candidate(form)}
      {:submit, :none}
  """
  @spec submit(t(), map()) :: t()
  def submit(%__MODULE__{} = form, values) when is_map(values) do
    transition(form, %Params{values: values, event: :submit})
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

  # D-012: raw undecoded text never reaches the validator; while any
  # decode fails there is no candidate and schema validation defers
  # entirely. The validator slot is opaque and adapter-owned; nil means
  # the source provides no instance validation (map source, for now).
  defp revalidate(%__MODULE__{} = form) do
    %{form | issues: Map.merge(form.issues, schema_issues(form))}
  end

  defp schema_issues(%__MODULE__{candidate: :none}), do: %{}
  defp schema_issues(%__MODULE__{definition: %Definition{validator: nil}}), do: %{}

  defp schema_issues(%__MODULE__{candidate: {:ok, instance}, definition: definition}) do
    definition.validator
    |> Validator.validate_instance(instance)
    |> Enum.group_by(& &1.path)
  end

  defp initial_data(definition, data, :apply), do: apply_defaults(Info.root(definition), data)
  defp initial_data(_definition, data, _other), do: data

  # Defaults apply only at explicit initialization and never overwrite
  # provided keys; nested objects are created only when a default lands
  # inside them. Transitions never call this — a cleared field stays
  # cleared (the phase's "default never mutates data" caution).
  defp apply_defaults(%Node.Group{} = node, data) do
    Enum.reduce(node.children, data, fn child, acc -> apply_default(child, acc) end)
  end

  defp apply_default(%Node.Field{name: name, default: default}, acc)
       when not is_nil(default) do
    Map.put_new(acc, name, default)
  end

  defp apply_default(%Node.Group{nests_data?: false} = group, acc) do
    apply_defaults(group, acc)
  end

  # A present value at a nesting key is descended into only when it is
  # already a map; any other present value (including an explicit `nil`,
  # which legitimately occurs in original data) is left completely
  # untouched — provided keys are never overwritten.
  defp apply_default(%Node.Group{nests_data?: true, name: name} = group, acc) do
    case Map.fetch(acc, name) do
      {:ok, value} when is_map(value) -> Map.put(acc, name, apply_defaults(group, value))
      {:ok, _non_map} -> acc
      :error -> put_created_defaults(group, acc, name)
    end
  end

  defp apply_default(_node, acc), do: acc

  defp put_created_defaults(group, acc, name) do
    child = apply_defaults(group, %{})

    if child == %{} do
      acc
    else
      Map.put(acc, name, child)
    end
  end

  defp decode(definition, domain_params) do
    definition
    |> Info.root()
    |> field_entries([], domain_params)
    |> Enum.reduce({%{}, %{}, %{}}, fn {path, node, transport},
                                       {transports, operations, issues} ->
      operation = operation_for(node, transport, path)

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
  defp operation_for(%Node.Field{read_only?: true}, _transport, _path), do: :keep
  defp operation_for(_node, :not_provided, _path), do: :unset
  defp operation_for(node, {:provided, raw}, path), do: Codec.decode(node.value_type, raw, path)

  # [{path, node, transport}] for every scalar field, walking through
  # presentation groups without a path segment and into data-nesting
  # groups with one. Unsupported nodes never decode. `reversed_prefix`
  # carries path segments nearest-first (prepended, O(1) per level); the
  # real path is only materialized at the leaf, where it's reversed once.
  defp field_entries(%Node.Group{} = node, reversed_prefix, params) do
    Enum.flat_map(node.children, fn
      %Node.Field{name: name} = child ->
        path = InstancePath.new!(Enum.reverse([name | reversed_prefix]))
        [{path, child, fetch_transport(params, name)}]

      %Node.Group{nests_data?: false} = child ->
        field_entries(child, reversed_prefix, params)

      %Node.Group{nests_data?: true, name: name} = child ->
        field_entries(child, [name | reversed_prefix], child_params(params, name))

      %Node.Unsupported{} ->
        []
    end)
  end

  defp fetch_transport(params, name) when is_map(params) do
    case Map.fetch(params, name) do
      {:ok, raw} -> {:provided, raw}
      :error -> :not_provided
    end
  end

  defp fetch_transport(_params, _name), do: :not_provided

  defp child_params(params, name) when is_map(params), do: Map.get(params, name, %{})
  defp child_params(_params, _name), do: %{}

  defp materialize(form, operations) do
    invalid? =
      Enum.any?(operations, fn {_path, operation} -> match?({:invalid, _}, operation) end)

    if invalid? do
      :none
    else
      root = Info.root(form.definition)
      {:ok, materialize_object(root, form.original, [], operations)}
    end
  end

  # Declared children rebuild from operations; keys the definition does
  # not describe are preserved from the original data, as are unsupported
  # nodes' values (preserve inactive data — D-009). `reversed_prefix`
  # carries path segments nearest-first (prepended, O(1) per level); the
  # real path is only materialized at the leaf, where it's reversed once.
  defp materialize_object(%Node.Group{} = node, original, reversed_prefix, operations) do
    original = if is_map(original), do: original, else: %{}

    {declared_result, declared_names} =
      materialize_children(node, original, reversed_prefix, operations)

    original
    |> Map.drop(MapSet.to_list(declared_names))
    |> Map.merge(declared_result)
  end

  defp materialize_children(%Node.Group{} = node, original, reversed_prefix, operations) do
    Enum.reduce(node.children, {%{}, MapSet.new()}, fn child, {acc, declared} ->
      materialize_child(child, original, reversed_prefix, operations, acc, declared)
    end)
  end

  defp materialize_child(
         %Node.Field{name: name},
         original,
         reversed_prefix,
         operations,
         acc,
         declared
       ) do
    declared = MapSet.put(declared, name)
    path = InstancePath.new!(Enum.reverse([name | reversed_prefix]))

    case Map.get(operations, path, :keep) do
      {:set, value} -> {Map.put(acc, name, value), declared}
      :unset -> {acc, declared}
      :keep -> {put_original(acc, original, name), declared}
    end
  end

  defp materialize_child(
         %Node.Group{nests_data?: false} = group,
         original,
         reversed_prefix,
         operations,
         acc,
         declared
       ) do
    {sub, sub_declared} = materialize_children(group, original, reversed_prefix, operations)
    {Map.merge(acc, sub), MapSet.union(declared, sub_declared)}
  end

  defp materialize_child(
         %Node.Group{nests_data?: true, name: name} = group,
         original,
         reversed_prefix,
         operations,
         acc,
         declared
       ) do
    value =
      materialize_object(
        group,
        Map.get(original, name, %{}),
        [name | reversed_prefix],
        operations
      )

    {Map.put(acc, name, value), MapSet.put(declared, name)}
  end

  defp materialize_child(
         %Node.Unsupported{name: name},
         original,
         _prefix,
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
