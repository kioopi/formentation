defmodule Formentation.Form.Submission do
  @moduledoc """
  Classifies preserve-only (unsupported) nodes against a materialized
  candidate into concrete `Formentation.Form.SubmissionBlocker`s (D-028).
  Enumerates unsupported occurrences through
  `Formentation.Occurrence.occurrences/2` over the candidate — a
  deliberately separate enumeration from decoding's walk over the
  incoming params (D-051).
  """

  alias Formentation.{Definition, InstancePath, Issue, Occurrence}
  alias Formentation.Definition.Semantic
  alias Formentation.Form.SubmissionBlocker

  @doc """
  The blockers for `candidate`, in unsupported-node declaration order.
  `issues` is the form's full path-keyed issues map; only
  `source: :validation` issues at or below an unsupported path count as
  owned. Callers guard the no-candidate case — this function always
  receives a real map.

      iex> {:ok, definition, _} =
      ...>   Formentation.compile(
      ...>     %{kind: :object, required: ["attachment"],
      ...>       properties: [{"attachment", %{kind: :file}}]},
      ...>     adapter: Formentation.Source.Map
      ...>   )
      iex> [blocker] = Formentation.Form.Submission.blockers(definition, %{}, %{})
      iex> blocker.code
      :unsupported_required
  """
  @spec blockers(Definition.t(), map(), %{InstancePath.t() => [Issue.t()]}) ::
          [SubmissionBlocker.t()]
  def blockers(%Definition{} = definition, candidate, issues)
      when is_map(candidate) and is_map(issues) do
    definition
    |> Occurrence.occurrences(candidate)
    |> Enum.filter(fn {entry, _path} -> entry.kind == :unsupported end)
    |> Enum.flat_map(fn {entry, path} -> classify(entry.node, path, candidate, issues) end)
  end

  # A preserve-only node blocks when a required value is missing from an
  # active parent, or when it owns authoritative validation issues at/below
  # its path. Missing-required wins the code; owned issues always ride along.
  defp classify(%Semantic.Unsupported{} = node, path, candidate, issues) do
    owned = owned_issues(issues, path)

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
  defp owned_issues(issues, unsupported_path) do
    issues
    |> Enum.filter(fn {issue_path, _list} ->
      InstancePath.ancestor_or_self?(unsupported_path, issue_path)
    end)
    |> Enum.sort_by(fn {issue_path, _list} -> issue_path.segments end)
    |> Enum.flat_map(fn {_path, list} -> Enum.filter(list, &(&1.source == :validation)) end)
  end
end
