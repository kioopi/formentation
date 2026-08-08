defmodule Formentation.HTMLAssertions do
  @moduledoc """
  Floki helpers asserting the step-6 accessibility contract (spec
  section "Accessibility contract"). Shared by UI, component, and
  snapshot tests.
  """

  import ExUnit.Assertions

  def parse!(html) when is_binary(html), do: Floki.parse_fragment!(html)

  @doc "Asserts exactly one element matches `selector` and returns it."
  def find_one(doc, selector) do
    case Floki.find(doc, selector) do
      [element] -> element
      other -> flunk("expected exactly one #{inspect(selector)}, got #{length(other)}")
    end
  end

  @doc "Contract item 1: the control has a non-empty <label for>."
  def assert_labelled(doc, id) do
    find_one(doc, ~s([id="#{id}"]))
    label = find_one(doc, ~s(label[for="#{id}"]))
    assert Floki.text(label) != "", "label for ##{id} is empty"
    label
  end

  @doc "The aria-describedby tokens of the element with `id` ([] when absent)."
  def describedby(doc, id) do
    doc
    |> find_one(~s([id="#{id}"]))
    |> Floki.attribute("aria-describedby")
    |> case do
      [] -> []
      [value] -> String.split(value, " ")
    end
  end

  @doc "Contract item 6: no duplicate ids in the document."
  def assert_no_duplicate_ids(doc) do
    ids = doc |> Floki.find("[id]") |> Enum.flat_map(&Floki.attribute(&1, "id"))
    assert Enum.uniq(ids) == ids, "duplicate ids: #{inspect(ids -- Enum.uniq(ids))}"
  end
end
