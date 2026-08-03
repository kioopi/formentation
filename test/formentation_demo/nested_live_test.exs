defmodule FormentationDemo.NestedLiveTest do
  use ExUnit.Case, async: true

  import Formentation.HTMLAssertions
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint FormentationDemo.Endpoint

  alias Formentation.{InstancePath, Phoenix.DOMIdentity}

  defp mount! do
    {:ok, lv, html} = live(build_conn(), "/nested")
    {lv, html}
  end

  defp field_id(path, part), do: DOMIdentity.field("payload", InstancePath.new!(path), part)

  test "renders the nested object under nested names with unique ids" do
    {_lv, html} = mount!()
    doc = parse!(html)

    assert_no_duplicate_ids(doc)
    assert [_street] = Floki.find(doc, "input[name='payload[address][street]']")
    assert [_number] = Floki.find(doc, "input[name='payload[address][number]']")
  end

  test "nested change lands values, usage, and errors on the nested nodes" do
    {lv, _html} = mount!()

    html =
      lv
      |> form("#nested-form", %{"payload" => %{"address" => %{"street" => "ab"}}})
      |> render_change()

    doc = parse!(html)
    assert [street] = Floki.find(doc, "input[name='payload[address][street]']")
    assert Floki.attribute(street, "value") == ["ab"]
    # touched and below minLength 3: visible on the nested node
    assert [_errors] = Floki.find(doc, "##{field_id(["address", "street"], :errors)}")
    # nested sibling stays quiet: `number` is not part of this change, so
    # `Phoenix.LiveViewTest`'s form serialization resends it as "" (its current
    # DOM value); for an integer field that decodes as :unset (D-010), which
    # produces no issue at all — quiet because there is nothing to report, not
    # because usage-gating is hiding an issue.
    assert Floki.find(doc, "##{field_id(["address", "number"], :errors)}") == []
    # Whole-form re-serialization also delivers title as "" — a string, so
    # D-010 decodes {:set, ""} (unlike number's unset) and the real minLength
    # violation renders on the marker-less, therefore :used, field.
    assert [_title_errors] = Floki.find(doc, "##{field_id(["title"], :errors)}")
  end

  test "editing after a successful submit clears the decoded candidate" do
    {lv, _html} = mount!()

    valid_payload = %{
      "title" => "HQ",
      "address" => %{"street" => "Main Street", "number" => "12"}
    }

    lv
    |> form("#nested-form", %{"payload" => valid_payload})
    |> render_submit()

    html =
      lv
      |> form("#nested-form", %{"payload" => %{"title" => "HQ changed"}})
      |> render_change()

    refute html =~ "decoded-candidate"
  end

  test "nested decode failure preserves raw input; valid submit nests the candidate" do
    {lv, _html} = mount!()

    html =
      lv
      |> form("#nested-form", %{"payload" => %{"address" => %{"number" => "12x"}}})
      |> render_change()

    doc = parse!(html)
    assert [number] = Floki.find(doc, "input[name='payload[address][number]']")
    assert Floki.attribute(number, "value") == ["12x"]
    assert [_errors] = Floki.find(doc, "##{field_id(["address", "number"], :errors)}")

    html =
      lv
      |> form("#nested-form", %{
        "payload" => %{
          "title" => "HQ",
          "address" => %{"street" => "Main Street", "number" => "12"}
        }
      })
      |> render_submit()

    doc = parse!(html)
    assert [pre] = Floki.find(doc, "pre#decoded-candidate")
    decoded = JSON.decode!(Floki.text(pre))
    assert decoded["title"] == "HQ"
    assert decoded["address"]["street"] == "Main Street"
    assert decoded["address"]["number"] == 12
  end

  test "a failed submit after success clears the decoded candidate" do
    {lv, _html} = mount!()

    valid_payload = %{
      "title" => "HQ",
      "address" => %{"street" => "Main Street", "number" => "12"}
    }

    lv
    |> form("#nested-form", %{"payload" => valid_payload})
    |> render_submit()

    html =
      lv
      |> form("#nested-form", %{"payload" => %{"title" => "", "address" => %{"number" => "12x"}}})
      |> render_submit()

    doc = parse!(html)
    assert Floki.find(doc, "pre#decoded-candidate") == []
    assert [number] = Floki.find(doc, "input[name='payload[address][number]']")
    assert Floki.attribute(number, "value") == ["12x"]
    assert [_errors] = Floki.find(doc, "##{field_id(["address", "number"], :errors)}")
  end
end
