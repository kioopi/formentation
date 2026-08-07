defmodule Formentation.Phoenix.ReferenceComponents do
  @moduledoc false

  use Phoenix.Component
  import Kernel, except: [node: 1]

  alias Formentation.Phoenix.RenderNode

  @doc """
  Dispatches one render node: a `RenderNode.Group` becomes a
  `fieldset.ftn-group` with a legend, optional associated help, and recursive children, a
  `RenderNode.Field` delegates to `field/1`.

  ```heex
  <ReferenceComponents.node :for={child <- @plan.root.children} node={child} />
  ```
  """
  attr(:node, :any, required: true, doc: "a RenderNode.Field or RenderNode.Group")

  def node(%{node: %RenderNode.Group{}} = assigns) do
    # Keep these elements contiguous: HEEx removes :if elements but retains
    # surrounding whitespace, and the no-help snapshot is byte-exact.
    ~H"""
    <fieldset
      id={@node.dom.container}
      class="ftn-group"
      aria-describedby={@node.help && @node.dom.help}
    >
      <legend>{@node.legend}</legend><p :if={@node.help} id={@node.dom.help} class="ftn-group-help">
        {@node.help}
      </p>
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
      ...>   render_component(&Formentation.Phoenix.ReferenceComponents.error_summary/1,
      ...>     summary: [%Formentation.Phoenix.RenderPlan.SummaryEntry{id: "email", label: "Email", message: "is required"}]
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
    <input type="hidden" name={@node.field.name} id={@node.dom.control} value={@node.field.value} />
    """
  end

  def field(assigns) do
    assigns = assign(assigns, :describedby, describedby(assigns.node))

    ~H"""
    <div class="ftn-field">
      <label :if={@node.widget not in [:checkbox, :radio_group]} for={@node.dom.control}>{@node.label}</label>
      <.control node={@node} describedby={@describedby} />
      <p :if={@node.help} id={@node.dom.help} class="ftn-help">{@node.help}</p>
      <ul :if={@node.show_errors?} id={@node.dom.errors} class="ftn-errors">
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
      id={@node.dom.control}
      name={@node.field.name}
      value="true"
      checked={@node.field.value in [true, "true"]}
      disabled={@node.read_only?}
      aria-describedby={@describedby}
      aria-invalid={@node.show_errors? && "true"}
      {validation_attrs(@node, [:required])}
    />
    <label for={@node.dom.control}>{@node.label}</label>
    """
  end

  defp control(%{node: %RenderNode.Field{widget: :textarea}} = assigns) do
    ~H"""
    <textarea
      id={@node.dom.control}
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
      id={@node.dom.control}
      name={@node.field.name}
      disabled={@node.read_only?}
      aria-describedby={@describedby}
      aria-invalid={@node.show_errors? && "true"}
      {validation_attrs(@node)}
    >
      <option value=""></option>
      <option
        :for={option <- @node.options}
        value={option_value(option)}
        selected={option_value(option) == @current}
      >
        {option}
      </option>
    </select>
    """
  end

  defp control(%{node: %RenderNode.Field{widget: :radio_group}} = assigns) do
    assigns = assign(assigns, :current, current_option(assigns.node.field.value))

    ~H"""
    <fieldset
      id={@node.dom.container}
      tabindex="-1"
      class="ftn-radio-group"
      role="radiogroup"
      aria-describedby={@describedby}
      aria-invalid={@node.show_errors? && "true"}
    >
      <legend>{@node.label}</legend>
      <div :for={{option, id} <- Enum.zip(@node.options, @node.dom.options)} class="ftn-radio">
        <input
          type="radio"
          id={id}
          name={@node.field.name}
          value={option_value(option)}
          checked={option_value(option) == @current}
          disabled={@node.read_only?}
          {required_attr(@node)}
        />
        <label for={id}>{option}</label>
      </div>
    </fieldset>
    """
  end

  defp control(assigns) do
    ~H"""
    <input
      type={input_type(@node.widget)}
      inputmode={inputmode(@node)}
      id={@node.dom.control}
      name={@node.field.name}
      value={@node.field.value}
      readonly={@node.read_only?}
      aria-describedby={@describedby}
      aria-invalid={@node.show_errors? && "true"}
      {validation_attrs(@node)}
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

  defp inputmode(%RenderNode.Field{widget: :number_input, value_type: :integer}), do: "numeric"
  defp inputmode(%RenderNode.Field{widget: :number_input, value_type: :number}), do: "decimal"
  defp inputmode(%RenderNode.Field{}), do: nil

  defp describedby(node) do
    ids =
      Enum.filter(
        [
          node.help && node.dom.help,
          node.show_errors? && node.errors != [] && node.dom.errors
        ],
        &is_binary/1
      )

    if ids == [], do: nil, else: Enum.join(ids, " ")
  end

  defp validation_attrs(node, except \\ [])

  # Keyed to semantic type so an explicit widget cannot reintroduce these
  # attributes: :number_input and :text_input render text controls, while
  # textareas and selects do not accept min/max/step. Radio groups use their
  # separate required-only policy below.
  defp validation_attrs(%RenderNode.Field{value_type: value_type} = node, except)
       when value_type in [:integer, :number] do
    node.validations |> Keyword.drop([:min, :max, :step | except]) |> Map.new()
  end

  defp validation_attrs(node, except) do
    node.validations |> Keyword.drop(except) |> Map.new()
  end

  # Radios take only :required from the validation set: constraint attrs
  # like minlength are not conforming on radio inputs, and required-on-radio
  # correctly means "one of this name-group must be selected".
  defp required_attr(node) do
    node.validations |> Keyword.take([:required]) |> Map.new()
  end

  defp current_option(nil), do: nil
  defp current_option(value), do: option_value(value)

  # Options retain their source scalar values, while Phoenix form values are
  # strings. Both sides must use this representation; canonicalizing only one
  # silently unselects non-string options after a round trip.
  defp option_value(value), do: to_string(value)
end
