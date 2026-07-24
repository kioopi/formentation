defmodule Formentation.Phoenix.Theme.Reference do
  @moduledoc """
  The Phase 1 reference theme: plain, accessible, deliberately
  unpolished markup for every projector widget. This is a markup set,
  not a theme contract — the contract is extracted in Phase 3 from a
  second implementation. The D-011 (checkbox hidden input) and D-016
  (readonly/disabled, no hidden mirrors) conformance tests bind these
  components directly.
  """

  use Phoenix.Component
  import Kernel, except: [node: 1]

  alias Formentation.Phoenix.RenderNode

  @doc """
  Dispatches one render node: a `RenderNode.Group` becomes a
  `fieldset.ftn-group` with a legend and recursive children, a
  `RenderNode.Field` delegates to `field/1`.

  ```heex
  <Reference.node :for={child <- @plan.root.children} node={child} />
  ```
  """
  attr(:node, :any, required: true, doc: "a RenderNode.Field or RenderNode.Group")

  def node(%{node: %RenderNode.Group{}} = assigns) do
    ~H"""
    <fieldset class="ftn-group">
      <legend>{@node.legend}</legend>
      <.node :for={child <- @node.children} node={child} />
    </fieldset>
    """
  end

  def node(%{node: %RenderNode.Field{}} = assigns), do: field(assigns)

  @doc """
  The submit-gated error summary (accessibility contract item 5): an
  empty summary renders nothing; entries with an id link to their
  control, root-level entries (nil id) render as plain text.

  ## Example

      iex> import Phoenix.LiveViewTest
      iex> html =
      ...>   render_component(&Formentation.Phoenix.Theme.Reference.error_summary/1,
      ...>     summary: [%{id: "email", label: "Email", message: "is required"}]
      ...>   )
      iex> html =~ ~s(role="alert") and html =~ ~s(href="#email")
      true
  """
  attr(:summary, :list, required: true)

  def error_summary(assigns) do
    ~H"""
    <div :if={@summary != []} class="ftn-error-summary" role="alert">
      <h2>This form has errors</h2>
      <ul>
        <li :for={entry <- @summary}>
          <a :if={entry.id} href={"##{entry.id}"}>{entry.label}: {entry.message}</a>
          <span :if={is_nil(entry.id)}>{entry.message}</span>
        </li>
      </ul>
    </div>
    """
  end

  @doc """
  One labelled, accessible field: wrapper, label, the widget's control,
  help linked via `aria-describedby`, and errors shown only when the
  node's `show_errors?` is set. A `:hidden_input` node renders as a bare
  hidden input with no wrapper or label.
  """
  attr(:node, RenderNode.Field, required: true)

  def field(%{node: %RenderNode.Field{widget: :hidden_input}} = assigns) do
    ~H"""
    <input type="hidden" name={@node.field.name} id={@node.field.id} value={@node.field.value} />
    """
  end

  def field(assigns) do
    assigns = assign(assigns, :describedby, describedby(assigns.node))

    ~H"""
    <div class="ftn-field">
      <label :if={@node.widget not in [:checkbox, :radio_group]} for={@node.field.id}>{@node.label}</label>
      <.control node={@node} describedby={@describedby} />
      <p :if={@node.help} id={help_id(@node)} class="ftn-help">{@node.help}</p>
      <ul :if={@node.show_errors?} id={errors_id(@node)} class="ftn-errors">
        <li :for={{message, _opts} <- @node.errors}>{message}</li>
      </ul>
    </div>
    """
  end

  attr(:node, RenderNode.Field, required: true)
  attr(:describedby, :string, required: true)

  # HTML required on a checkbox means "must be CHECKED" — a different
  # constraint than a required boolean, which the D-011 hidden input
  # already satisfies by always submitting true or false. So :required
  # is dropped from the rendered attributes here.
  defp control(%{node: %RenderNode.Field{widget: :checkbox}} = assigns) do
    ~H"""
    <input :if={not @node.read_only?} type="hidden" name={@node.field.name} value="false" />
    <input
      type="checkbox"
      id={@node.field.id}
      name={@node.field.name}
      value="true"
      checked={@node.field.value in [true, "true"]}
      disabled={@node.read_only?}
      aria-describedby={@describedby}
      aria-invalid={@node.show_errors? && "true"}
      {validation_attrs(@node, [:required])}
    />
    <label for={@node.field.id}>{@node.label}</label>
    """
  end

  defp control(%{node: %RenderNode.Field{widget: :textarea}} = assigns) do
    ~H"""
    <textarea
      id={@node.field.id}
      name={@node.field.name}
      readonly={@node.read_only?}
      aria-describedby={@describedby}
      aria-invalid={@node.show_errors? && "true"}
      {validation_attrs(@node)}
    >{@node.field.value}</textarea>
    """
  end

  defp control(%{node: %RenderNode.Field{widget: :select}} = assigns) do
    assigns = assign(assigns, :current, current_option(assigns.node.field.value))

    ~H"""
    <select
      id={@node.field.id}
      name={@node.field.name}
      disabled={@node.read_only?}
      aria-describedby={@describedby}
      aria-invalid={@node.show_errors? && "true"}
      {validation_attrs(@node)}
    >
      <option value=""></option>
      <option :for={option <- @node.options} value={option} selected={option == @current}>
        {option}
      </option>
    </select>
    """
  end

  defp control(%{node: %RenderNode.Field{widget: :radio_group}} = assigns) do
    assigns = assign(assigns, :current, current_option(assigns.node.field.value))

    ~H"""
    <fieldset
      class="ftn-radio-group"
      role="radiogroup"
      aria-describedby={@describedby}
      aria-invalid={@node.show_errors? && "true"}
    >
      <legend>{@node.label}</legend>
      <div :for={{option, index} <- Enum.with_index(@node.options)} class="ftn-radio">
        <input
          type="radio"
          id={"#{@node.field.id}_#{index}"}
          name={@node.field.name}
          value={option}
          checked={option == @current}
          disabled={@node.read_only?}
          {required_attr(@node)}
        />
        <label for={"#{@node.field.id}_#{index}"}>{option}</label>
      </div>
    </fieldset>
    """
  end

  defp control(assigns) do
    ~H"""
    <input
      type={input_type(@node.widget)}
      inputmode={inputmode(@node.widget)}
      id={@node.field.id}
      name={@node.field.name}
      value={@node.field.value}
      readonly={@node.read_only?}
      aria-describedby={@describedby}
      aria-invalid={@node.show_errors? && "true"}
      {text_validation_attrs(@node)}
    />
    """
  end

  defp input_type(:text_input), do: "text"
  # type="text" + inputmode, not type="number": browsers refuse to
  # DISPLAY non-numeric raw text in number inputs, which breaks
  # raw-input preservation (verified in the step-7 browser check;
  # see 16-open-questions).
  defp input_type(:number_input), do: "text"
  defp input_type(:date_input), do: "date"
  defp input_type(:email_input), do: "email"
  defp input_type(:url_input), do: "url"

  defp inputmode(:number_input), do: "numeric"
  defp inputmode(_widget), do: nil

  defp help_id(node), do: "#{node.field.id}_help"
  defp errors_id(node), do: "#{node.field.id}_errors"

  defp describedby(node) do
    ids =
      Enum.filter(
        [
          node.help && help_id(node),
          node.show_errors? && node.errors != [] && errors_id(node)
        ],
        &is_binary/1
      )

    if ids == [], do: nil, else: Enum.join(ids, " ")
  end

  defp validation_attrs(node, except \\ []) do
    node.validations |> Keyword.drop(except) |> Map.new()
  end

  # min/max/step are number-input attributes; on the type="text" fallback
  # (see input_type/1) they are non-conforming and ignored, so the number
  # widget passes through only its conforming validations.
  defp text_validation_attrs(%RenderNode.Field{widget: :number_input} = node) do
    node.validations |> Keyword.drop([:min, :max, :step]) |> Map.new()
  end

  defp text_validation_attrs(node), do: validation_attrs(node)

  # Radios take only :required from the validation set: constraint attrs
  # like minlength are not conforming on radio inputs, and required-on-radio
  # correctly means "one of this name-group must be selected".
  defp required_attr(node) do
    node.validations |> Keyword.take([:required]) |> Map.new()
  end

  defp current_option(nil), do: nil
  defp current_option(value), do: to_string(value)
end
