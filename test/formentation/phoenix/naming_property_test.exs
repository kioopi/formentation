defmodule Formentation.Phoenix.NamingPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  # Every field's input name must round-trip through Plug's param decoder
  # back to its own instance path — otherwise what the browser posts
  # would land somewhere other than where the projection reads.

  alias Formentation.Definition.Semantic
  alias Formentation.{Form, Info}
  alias Phoenix.HTML.FormData

  defp field_name_gen, do: StreamData.string([?a..?z], min_length: 1, max_length: 8)

  defp definition_gen do
    gen all(
          root_names <- StreamData.uniq_list_of(field_name_gen(), min_length: 1, max_length: 4),
          nested_names <-
            StreamData.uniq_list_of(field_name_gen(), min_length: 1, max_length: 3),
          nested_key <- field_name_gen(),
          nested_key not in root_names,
          as_name <- StreamData.one_of([StreamData.constant(nil), field_name_gen()])
        ) do
      nested_properties = Enum.map(nested_names, &{&1, %{kind: :string}})

      properties =
        Enum.map(root_names, &{&1, %{kind: :string}}) ++
          [{nested_key, %{kind: :object, properties: nested_properties}}]

      {:ok, definition, []} =
        Formentation.compile(%{kind: :object, properties: properties},
          adapter: Formentation.Definition.Source.Map
        )

      {definition, as_name}
    end
  end

  property "input names round-trip through Plug's decoder to their instance path" do
    check all({definition, as_name} <- definition_gen()) do
      form_state = Form.new(definition)
      opts = if as_name, do: [as: as_name], else: []
      root = FormData.to_form(form_state, opts)
      prefix = if as_name, do: [as_name], else: []

      for {path, form} <- field_paths(definition, form_state, root) do
        name = form[List.last(path)].name
        decoded = Plug.Conn.Query.decode("#{name}=sentinel")

        assert get_in(decoded, prefix ++ path) == "sentinel"
      end
    end
  end

  defp field_paths(definition, form_state, root) do
    Enum.flat_map(Info.root(definition).children, fn
      %Semantic.Field{name: name} ->
        [{[name], root}]

      %Semantic.Object{name: key} = object ->
        nested = hd(FormData.to_form(form_state, root, key, []))
        for %Semantic.Field{name: name} <- object.children, do: {[key, name], nested}
    end)
  end
end
