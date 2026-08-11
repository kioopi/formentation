defmodule Formentation.Phoenix.Render.Preparation.Widget do
  @moduledoc """
  Resolves a field's renderer-facing widget.

  Not part of the public API — reached only through `Render.Preparation.prepare/2`
  and `prepare_at/3` while projecting a `Layout.Field`. Kept out of the
  published docs by `mix.exs`, but documented here because widget resolution is a
  self-contained decision worth understanding on its own: given a
  presentation-declared widget hint (or none) and the field's semantic shape,
  it picks one of the finite renderer widgets and reports a diagnostic when a
  hint could not be honored.

  Resolution order (spec order): hidden -> hint -> options -> boolean ->
  number -> role -> text. A hint always wins when it is compatible with the
  field's shape; otherwise resolution falls back to inference and a
  `:widget_fallback` diagnostic is emitted. The same order is documented as a
  table in the rendering techdoc, which this module owns.
  """

  alias Formentation.Definition.Semantic
  alias Formentation.Diagnostic
  alias Formentation.Info.Layout

  @type t ::
          :hidden_input
          | :text_input
          | :textarea
          | :select
          | :radio_group
          | :checkbox
          | :number_input
          | :date_input
          | :email_input
          | :url_input

  @doc """
  Resolves `node`'s renderer widget given `presentation`'s hint (if any).

  Returns the resolved widget and any diagnostics raised while resolving it
  (currently at most one: a `:widget_fallback` warning when `presentation.widget`
  could not be honored for `node`'s shape).

  ## Examples

      iex> presentation = %Formentation.Info.Layout.Field{
      ...>   template_path: Formentation.TemplatePath.new!(["a"]),
      ...>   label: nil, help: nil, widget: nil, hidden?: false, origins: []
      ...> }
      iex> node = Formentation.Definition.Semantic.Field.new("a", Formentation.TemplatePath.new!(["a"]), :boolean)
      iex> Formentation.Phoenix.Render.Preparation.Widget.resolve(presentation, node)
      {:checkbox, []}

      iex> presentation = %Formentation.Info.Layout.Field{
      ...>   template_path: Formentation.TemplatePath.new!(["a"]),
      ...>   label: nil, help: nil, widget: :checkbox, hidden?: false, origins: []
      ...> }
      iex> node = Formentation.Definition.Semantic.Field.new("a", Formentation.TemplatePath.new!(["a"]), :string)
      iex> {widget, [diagnostic]} = Formentation.Phoenix.Render.Preparation.Widget.resolve(presentation, node)
      iex> {widget, diagnostic.code}
      {:text_input, :widget_fallback}
  """
  @spec resolve(Layout.Field.t(), Semantic.Field.t()) :: {t(), [Diagnostic.t()]}
  def resolve(%Layout.Field{hidden?: true}, _node), do: {:hidden_input, []}
  def resolve(%Layout.Field{widget: nil}, node), do: {infer_widget(node), []}

  def resolve(%Layout.Field{widget: hint}, node) do
    case hinted_widget(hint, node) do
      {:ok, widget} ->
        {widget, []}

      :fallback ->
        widget = infer_widget(node)
        {widget, [fallback_diagnostic(hint, node, widget)]}
    end
  end

  defp hinted_widget(:text, _node), do: {:ok, :text_input}
  defp hinted_widget(:textarea, _node), do: {:ok, :textarea}
  defp hinted_widget(:select, %Semantic.Field{options: [_ | _]}), do: {:ok, :select}
  defp hinted_widget(:radio, %Semantic.Field{options: [_ | _]}), do: {:ok, :radio_group}
  defp hinted_widget(:checkbox, %Semantic.Field{value_type: :boolean}), do: {:ok, :checkbox}
  defp hinted_widget(_hint, _node), do: :fallback

  # Clause order is the spec's inference order — options, boolean, number,
  # role, text — so a role-bearing integer field stays a `:number_input`.
  defp infer_widget(%Semantic.Field{options: [_ | _]}), do: :select
  defp infer_widget(%Semantic.Field{value_type: :boolean}), do: :checkbox

  defp infer_widget(%Semantic.Field{value_type: type}) when type in [:integer, :number],
    do: :number_input

  defp infer_widget(%Semantic.Field{role: :date}), do: :date_input
  defp infer_widget(%Semantic.Field{role: :email}), do: :email_input
  defp infer_widget(%Semantic.Field{role: :uri}), do: :url_input
  defp infer_widget(%Semantic.Field{}), do: :text_input

  defp fallback_diagnostic(hint, node, widget) do
    %Diagnostic{
      severity: :warning,
      code: :widget_fallback,
      message:
        "widget #{inspect(hint)} cannot render field #{inspect(node.name)}; " <>
          "falling back to #{inspect(widget)}",
      template_path: node.template_path
    }
  end
end
