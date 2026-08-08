defmodule Formentation.Phoenix.RenderPreparation.WidgetTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  doctest Formentation.Phoenix.RenderPreparation.Widget

  alias Formentation.Definition.Semantic
  alias Formentation.Info.Layout
  alias Formentation.{InstancePath, TemplatePath}
  alias Formentation.Phoenix.RenderPreparation.Widget

  # These properties deliberately never restate `Widget`'s clause order. An
  # oracle copied from the implementation shares its bugs and goes stale the
  # moment someone keeps it "in sync" by re-copying. Instead they assert
  # relational and shape facts a reader can check against the widget-resolution
  # table in `Techdocs/rendering.md`:
  #
  #   * the resolved widget's shape agrees with the node's shape,
  #   * a fallback lands exactly where the same node with no hint lands
  #     (`Widget` itself is the oracle, on a different input — not a copy of
  #     its internals),
  #   * an honored hint maps to its widget through a data table.

  @widgets [
    :hidden_input,
    :text_input,
    :textarea,
    :select,
    :radio_group,
    :checkbox,
    :number_input,
    :date_input,
    :email_input,
    :url_input
  ]

  # The widget each recognized hint asks for. Data, not control flow: it says
  # nothing about *when* the request is granted, which is what the
  # honored-iff properties below pin down.
  @hint_widgets %{
    text: :text_input,
    textarea: :textarea,
    select: :select,
    radio: :radio_group,
    checkbox: :checkbox
  }

  # Hints outside the theme's widget set. Reachable via the unvalidated map
  # source, and never honorable for any node shape.
  @unrecognized_hints [:fancy_slider, :nonsense]

  defp semantic_field_gen do
    gen all(
          value_type <- StreamData.member_of([:string, :integer, :number, :boolean]),
          role <- StreamData.member_of([nil, :date, :email, :uri]),
          options <- StreamData.member_of([nil, [], ["a", "b"]])
        ) do
      Semantic.Field.new("field", TemplatePath.new!(["field"]), value_type,
        role: role,
        options: options
      )
    end
  end

  defp hint_gen do
    StreamData.member_of([nil | Map.keys(@hint_widgets) ++ @unrecognized_hints])
  end

  defp presentation_field_gen do
    gen all(hint <- hint_gen(), hidden? <- StreamData.boolean()) do
      presentation_field(hint, hidden?)
    end
  end

  defp presentation_field(hint, hidden?) do
    %Layout.Field{
      semantic_path: InstancePath.new!(["field"]),
      label: nil,
      help: nil,
      widget: hint,
      hidden?: hidden?,
      origins: []
    }
  end

  defp options?(%Semantic.Field{options: options}), do: options not in [nil, []]

  property "resolves to a widget in Widget.t()'s value set, and never raises" do
    check all(
            presentation <- presentation_field_gen(),
            node <- semantic_field_gen()
          ) do
      {widget, diagnostics} = Widget.resolve(presentation, node)

      assert widget in @widgets

      assert match?([], diagnostics) or match?([_], diagnostics),
             "expected at most one diagnostic, got #{inspect(diagnostics)}"
    end
  end

  property "a hidden field is a hidden input regardless of hint or node shape" do
    check all(
            presentation <- presentation_field_gen(),
            node <- semantic_field_gen()
          ) do
      assert Widget.resolve(%{presentation | hidden?: true}, node) == {:hidden_input, []}
    end
  end

  # Each implication constrains the *result* against the node, so it holds no
  # matter how resolution is refactored — and it fails loudly if a clause is
  # reordered into a shape it does not belong to. The `:date_input` case is the
  # sharpest: hoisting the role clauses above the numeric one would resolve a
  # `%{role: :date, value_type: :integer}` field to `:date_input`, and this
  # catches it.
  property "the resolved widget's shape agrees with the node's shape" do
    check all(
            hint <- hint_gen(),
            node <- semantic_field_gen()
          ) do
      {widget, _diagnostics} = Widget.resolve(presentation_field(hint, false), node)

      case widget do
        :checkbox -> assert node.value_type == :boolean
        :number_input -> assert node.value_type in [:integer, :number]
        :select -> assert options?(node)
        :radio_group -> assert options?(node)
        :date_input -> assert node.role == :date and node.value_type == :string
        :email_input -> assert node.role == :email and node.value_type == :string
        :url_input -> assert node.role == :uri and node.value_type == :string
        :textarea -> assert hint == :textarea
        # The catch-all of the inference table — no shape constraint to check.
        :text_input -> :ok
        other -> flunk("unreachable widget #{inspect(other)} for a visible field")
      end
    end
  end

  property "a hint is honored exactly when the resolution reports no diagnostic" do
    check all(
            hint <- StreamData.member_of(Map.keys(@hint_widgets) ++ @unrecognized_hints),
            node <- semantic_field_gen()
          ) do
      {widget, diagnostics} = Widget.resolve(presentation_field(hint, false), node)
      honored? = diagnostics == []

      assert honored? == (widget == Map.get(@hint_widgets, hint))
    end
  end

  property "a rejected hint resolves exactly where the same node with no hint resolves" do
    check all(
            hint <- StreamData.member_of(Map.keys(@hint_widgets) ++ @unrecognized_hints),
            node <- semantic_field_gen()
          ) do
      {widget, diagnostics} = Widget.resolve(presentation_field(hint, false), node)

      if diagnostics != [] do
        assert {^widget, []} = Widget.resolve(presentation_field(nil, false), node)
      end
    end
  end

  property "a rejected hint reports one :widget_fallback warning against the node" do
    check all(
            hint <- StreamData.member_of(Map.keys(@hint_widgets) ++ @unrecognized_hints),
            node <- semantic_field_gen()
          ) do
      {_widget, diagnostics} = Widget.resolve(presentation_field(hint, false), node)

      for diagnostic <- diagnostics do
        assert %Formentation.Diagnostic{
                 severity: :warning,
                 code: :widget_fallback,
                 template_path: template_path
               } = diagnostic

        assert template_path == node.template_path
        assert diagnostic.message =~ inspect(hint)
      end
    end
  end

  property "an options hint is honored exactly when the node carries options" do
    check all(
            hint <- StreamData.member_of([:select, :radio]),
            node <- semantic_field_gen()
          ) do
      {_widget, diagnostics} = Widget.resolve(presentation_field(hint, false), node)
      honored? = diagnostics == []

      assert honored? == options?(node)
    end
  end

  property "a :checkbox hint is honored exactly when the node is boolean" do
    check all(node <- semantic_field_gen()) do
      {_widget, diagnostics} = Widget.resolve(presentation_field(:checkbox, false), node)
      honored? = diagnostics == []

      assert honored? == (node.value_type == :boolean)
    end
  end

  property "free-text hints are honored for every node shape" do
    check all(
            hint <- StreamData.member_of([:text, :textarea]),
            node <- semantic_field_gen()
          ) do
      assert {Map.fetch!(@hint_widgets, hint), []} ==
               Widget.resolve(presentation_field(hint, false), node)
    end
  end

  property "an unrecognized hint is never honored" do
    check all(
            hint <- StreamData.member_of(@unrecognized_hints),
            node <- semantic_field_gen()
          ) do
      {_widget, diagnostics} = Widget.resolve(presentation_field(hint, false), node)

      assert [%Formentation.Diagnostic{code: :widget_fallback}] = diagnostics
    end
  end
end
