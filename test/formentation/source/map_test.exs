defmodule Formentation.Source.MapTest do
  use ExUnit.Case, async: true

  alias Formentation.{Info, Node}

  defp compile!(declaration, opts \\ []) do
    {:ok, definition, _diagnostics} =
      Formentation.compile(declaration, [adapter: Formentation.Source.Map] ++ opts)

    definition
  end

  describe "minimal object" do
    test "compiles a root object with one string field" do
      definition = compile!(%{kind: :object, properties: [{"name", %{kind: :string}}]})

      assert %Node.Group{nests_data?: true, id: "/"} = Info.root(definition)
      assert [%Node.Field{name: "name", id: "/name"}] = Info.fields(definition)
      assert Info.diagnostics(definition) == []
    end

    test "node/2 finds nodes by id and node_at/2 by instance path" do
      definition = compile!(%{kind: :object, properties: [{"name", %{kind: :string}}]})

      assert %Node.Field{name: "name"} = Info.node(definition, "/name")
      assert %Node.Field{name: "name"} = Info.node_at(definition, ["name"])
      assert Info.node_at(definition, ["missing"]) == nil
    end

    test "field template paths record the property position" do
      definition = compile!(%{kind: :object, properties: [{"name", %{kind: :string}}]})

      assert %Node.Field{template_path: %Formentation.TemplatePath{segments: ["name"]}} =
               Info.node_at(definition, ["name"])
    end
  end

  describe "labels and origins" do
    test "title becomes the label with a map_source origin" do
      definition =
        compile!(%{
          kind: :object,
          title: "Pump inspection",
          properties: [{"serial_number", %{kind: :string, title: "Serial number"}}]
        })

      assert %Node.Group{label: "Pump inspection"} = Info.root(definition)
      assert %Node.Field{label: "Serial number"} = Info.node_at(definition, ["serial_number"])

      assert Info.origins(definition, ["serial_number"])[:label] ==
               {:map_source, [:properties, "serial_number", :title]}
    end

    test "a missing title falls back to a humanized name with an inference origin" do
      definition =
        compile!(%{kind: :object, properties: [{"serial_number", %{kind: :string}}]})

      assert %Node.Field{label: "Serial number"} = Info.node_at(definition, ["serial_number"])
      assert Info.origins(definition, ["serial_number"])[:label] == {:inference, :label_from_name}
    end

    test "origins/2 returns [] for unknown paths" do
      definition = compile!(%{kind: :object, properties: []})
      assert Info.origins(definition, ["missing"]) == []
    end

    test "an explicit nil title falls back to a humanized name with an inference origin" do
      definition =
        compile!(%{
          kind: :object,
          properties: [{"serial_number", %{kind: :string, title: nil}}]
        })

      assert %Node.Field{label: "Serial number"} = Info.node_at(definition, ["serial_number"])
      assert Info.origins(definition, ["serial_number"])[:label] == {:inference, :label_from_name}
    end
  end

  describe "scalar kinds and roles" do
    test "each scalar kind gets its default role with an inference origin" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"notes", %{kind: :string}},
            {"operating_hours", %{kind: :integer}},
            {"voltage", %{kind: :number}},
            {"insulation_ok", %{kind: :boolean}}
          ]
        })

      assert Info.role(definition, ["notes"]) == :text
      assert Info.role(definition, ["operating_hours"]) == :integer
      assert Info.role(definition, ["voltage"]) == :number
      assert Info.role(definition, ["insulation_ok"]) == :boolean
      assert Info.origins(definition, ["notes"])[:role] == {:inference, :string_default}
      assert Info.origins(definition, ["voltage"])[:role] == {:inference, :number_default}
    end

    test "an explicit role wins over the kind default" do
      definition =
        compile!(%{
          kind: :object,
          properties: [{"last_service", %{kind: :string, role: :date}}]
        })

      assert Info.role(definition, ["last_service"]) == :date

      assert Info.origins(definition, ["last_service"])[:role] ==
               {:map_source, [:properties, "last_service", :role]}
    end

    test "role/2 returns nil for unknown paths" do
      definition = compile!(%{kind: :object, properties: []})
      assert Info.role(definition, ["missing"]) == nil
    end

    test "an explicit nil role falls back to the kind default" do
      definition =
        compile!(%{
          kind: :object,
          properties: [{"last_service", %{kind: :string, role: nil}}]
        })

      assert Info.role(definition, ["last_service"]) == :text
      assert Info.origins(definition, ["last_service"])[:role] == {:inference, :string_default}
    end

    test "fields carry their scalar value type" do
      declaration = %{
        kind: :object,
        properties: [
          {"name", %{kind: :string}},
          {"count", %{kind: :integer}},
          {"volume", %{kind: :number}},
          {"active", %{kind: :boolean}},
          {"when", %{kind: :string, role: :date}},
          {"choice", %{kind: :string, one_of: ["a", "b"]}}
        ]
      }

      {:ok, definition, []} = Formentation.compile(declaration, adapter: Formentation.Source.Map)

      for {name, expected} <- [
            {"name", :string},
            {"count", :integer},
            {"volume", :number},
            {"active", :boolean},
            {"when", :string},
            {"choice", :string}
          ] do
        assert %Formentation.Node.Field{value_type: ^expected} =
                 Formentation.Info.node_at(definition, [name])
      end

      assert %Formentation.Node.Group{} = Formentation.Info.root(definition)
    end
  end

  describe "required fields" do
    test "names in the object's required list mark fields required" do
      definition =
        compile!(%{
          kind: :object,
          required: ["serial_number"],
          properties: [
            {"serial_number", %{kind: :string}},
            {"notes", %{kind: :string}}
          ]
        })

      assert Info.required?(definition, ["serial_number"]) == true
      assert Info.required?(definition, ["notes"]) == false
      assert Info.required?(definition, ["missing"]) == false
    end
  end

  describe "option sets" do
    test "one_of compiles to a select field with options, not a choice node" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"condition", %{kind: :string, one_of: ["good", "worn", "defective"]}}
          ]
        })

      assert %Node.Field{options: ["good", "worn", "defective"]} =
               Info.node_at(definition, ["condition"])

      assert Info.role(definition, ["condition"]) == :select
      assert Info.origins(definition, ["condition"])[:role] == {:inference, :one_of_select}

      assert Info.origins(definition, ["condition"])[:options] ==
               {:map_source, [:properties, "condition", :one_of]}
    end

    test "an explicit role still wins over one_of" do
      definition =
        compile!(%{
          kind: :object,
          properties: [{"condition", %{kind: :string, one_of: ["a"], role: :radio}}]
        })

      assert Info.role(definition, ["condition"]) == :radio
    end

    test "a nil one_of does not infer :select, set options, or stamp an options origin" do
      definition =
        compile!(%{
          kind: :object,
          properties: [{"condition", %{kind: :string, one_of: nil}}]
        })

      assert %Node.Field{options: nil} = Info.node_at(definition, ["condition"])
      assert Info.role(definition, ["condition"]) == :text
      assert Info.origins(definition, ["condition"])[:role] == {:inference, :string_default}
      assert Info.origins(definition, ["condition"])[:options] == nil
    end
  end

  describe "widget, help, and constraints" do
    test "widget and help overrides carry map_source origins" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"notes", %{kind: :string, widget: :textarea, help: "Visible to all technicians."}}
          ]
        })

      assert %Node.Field{widget: :textarea, help: "Visible to all technicians."} =
               Info.node_at(definition, ["notes"])

      origins = Info.origins(definition, ["notes"])
      assert origins[:widget] == {:map_source, [:properties, "notes", :widget]}
      assert origins[:help] == {:map_source, [:properties, "notes", :help]}
    end

    test "presentation-relevant constraints are collected" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"serial_number", %{kind: :string, min_length: 4}},
            {"operating_hours", %{kind: :integer, min: 0}}
          ]
        })

      assert Info.node_at(definition, ["serial_number"]).constraints == %{min_length: 4}
      assert Info.node_at(definition, ["operating_hours"]).constraints == %{min: 0}
    end
  end

  describe "presentation groups" do
    defp grouped_declaration do
      %{
        kind: :object,
        properties: [
          {"serial_number", %{kind: :string}},
          {"voltage", %{kind: :number}},
          {"insulation_ok", %{kind: :boolean}},
          {"notes", %{kind: :string}}
        ],
        groups: [%{id: "electrical", title: "Electrical", fields: ["voltage", "insulation_ok"]}]
      }
    end

    test "a group nests members in markup position without nesting data" do
      definition = compile!(grouped_declaration())

      assert [%Node.Field{name: "serial_number"}, group, %Node.Field{name: "notes"}] =
               Info.root(definition).children

      assert %Node.Group{
               nests_data?: false,
               id: "/#electrical",
               label: "Electrical",
               children: [%Node.Field{name: "voltage"}, %Node.Field{name: "insulation_ok"}]
             } = group

      assert group.template_path.segments == []
    end

    test "members stay reachable by flat instance path and know their group" do
      definition = compile!(grouped_declaration())

      assert %Node.Field{group: "electrical"} = Info.node_at(definition, ["voltage"])
      assert Info.node_at(definition, ["voltage"]).id == "/voltage"
    end

    test "fields/1 keeps declaration order across reordered group boundaries" do
      declaration = %{
        kind: :object,
        properties: [
          {"a", %{kind: :string}},
          {"b", %{kind: :string}},
          {"c", %{kind: :string}},
          {"d", %{kind: :string}}
        ],
        groups: [%{id: "g", fields: ["c", "a"]}]
      }

      definition = compile!(declaration)

      assert %Node.Group{children: children} = Info.node(definition, "/#g")
      assert Enum.map(children, & &1.name) == ["c", "a"]

      assert Enum.map(Info.fields(definition), & &1.name) == ["a", "b", "c", "d"]
    end

    test "a group naming an unknown field emits a warning diagnostic" do
      declaration = %{
        kind: :object,
        properties: [{"voltage", %{kind: :number}}],
        groups: [%{id: "electrical", title: "Electrical", fields: ["voltage", "missing"]}]
      }

      definition = compile!(declaration)

      assert [%Formentation.Diagnostic{severity: :warning, code: :unknown_group_field}] =
               Info.diagnostics(definition)
    end

    test "a group with no known members emits diagnostics but no node" do
      declaration = %{
        kind: :object,
        properties: [{"serial_number", %{kind: :string}}],
        groups: [%{id: "electrical", title: "Electrical", fields: ["voltage", "insulation_ok"]}]
      }

      definition = compile!(declaration)

      assert [%Node.Field{name: "serial_number"}] = Info.root(definition).children
      assert Info.node(definition, "/#electrical") == nil

      assert [
               %Formentation.Diagnostic{code: :unknown_group_field},
               %Formentation.Diagnostic{code: :unknown_group_field}
             ] = Info.diagnostics(definition)
    end

    test "a group whose first member leads the property list becomes the first child" do
      declaration = %{
        kind: :object,
        properties: [
          {"voltage", %{kind: :number}},
          {"insulation_ok", %{kind: :boolean}},
          {"notes", %{kind: :string}}
        ],
        groups: [%{id: "electrical", title: "Electrical", fields: ["voltage", "insulation_ok"]}]
      }

      definition = compile!(declaration)

      assert [%Node.Group{id: "/#electrical"}, %Node.Field{name: "notes"}] =
               Info.root(definition).children
    end

    test "non-adjacent members gather at the first member's position" do
      declaration = %{
        kind: :object,
        properties: [
          {"a", %{kind: :string}},
          {"voltage", %{kind: :number}},
          {"b", %{kind: :string}},
          {"insulation_ok", %{kind: :boolean}},
          {"c", %{kind: :string}}
        ],
        groups: [%{id: "electrical", title: "Electrical", fields: ["voltage", "insulation_ok"]}]
      }

      definition = compile!(declaration)

      assert Enum.map(Info.fields(definition), & &1.name) ==
               ["a", "voltage", "b", "insulation_ok", "c"]
    end

    test "a group without a title has a nil label and no label origin" do
      declaration = %{
        kind: :object,
        properties: [{"voltage", %{kind: :number}}, {"insulation_ok", %{kind: :boolean}}],
        groups: [%{id: "electrical", fields: ["voltage", "insulation_ok"]}]
      }

      definition = compile!(declaration)

      group = Info.node(definition, "/#electrical")
      assert %Node.Group{label: nil} = group
      refute Keyword.has_key?(group.origins, :label)
    end

    test "multiple groups place independently" do
      declaration = %{
        kind: :object,
        properties: [
          {"voltage", %{kind: :number}},
          {"insulation_ok", %{kind: :boolean}},
          {"width", %{kind: :integer}},
          {"height", %{kind: :integer}}
        ],
        groups: [
          %{id: "electrical", title: "Electrical", fields: ["voltage", "insulation_ok"]},
          %{id: "size", title: "Size", fields: ["width", "height"]}
        ]
      }

      definition = compile!(declaration)

      assert [%Node.Group{id: "/#electrical"}, %Node.Group{id: "/#size"}] =
               Info.root(definition).children

      assert Info.node_at(definition, ["width"]).group == "size"
      assert Info.diagnostics(definition) == []
    end

    test "duplicate field names in a group's fields list do not duplicate the member" do
      declaration = %{
        kind: :object,
        properties: [{"a", %{kind: :string}}],
        groups: [%{id: "g", fields: ["a", "a"]}]
      }

      definition = compile!(declaration)

      assert %Node.Group{children: [%Node.Field{name: "a"}]} = Info.node(definition, "/#g")
      assert Enum.map(Info.fields(definition), & &1.name) == ["a"]
    end

    test "group children follow the fields-list order, not declaration order" do
      declaration = %{
        kind: :object,
        properties: [
          {"a", %{kind: :string}},
          {"c", %{kind: :string}}
        ],
        groups: [%{id: "g", fields: ["c", "a"]}]
      }

      definition = compile!(declaration)

      assert %Node.Group{children: children} = Info.node(definition, "/#g")
      assert Enum.map(children, & &1.name) == ["c", "a"]
    end

    test "a group naming a nested object member places it unstamped" do
      declaration = %{
        kind: :object,
        properties: [
          {"voltage", %{kind: :number}},
          {"dimensions", %{kind: :object, properties: [{"width", %{kind: :integer}}]}}
        ],
        groups: [%{id: "electrical", fields: ["voltage", "dimensions"]}]
      }

      definition = compile!(declaration)

      assert Info.diagnostics(definition) == []
      assert %Node.Field{group: "electrical"} = Info.node_at(definition, ["voltage"])
      assert %Node.Group{nests_data?: true} = Info.node_at(definition, ["dimensions"])
    end

    test "semantic order is independent at root and nested object boundaries" do
      declaration = %{
        kind: :object,
        properties: [
          {"title", %{kind: :string}},
          {"dimensions",
           %{
             kind: :object,
             properties: [
               {"width", %{kind: :integer}},
               {"depth", %{kind: :integer}},
               {"height", %{kind: :integer}}
             ],
             groups: [%{id: "size", fields: ["height", "width"]}]
           }},
          {"notes", %{kind: :string}}
        ],
        groups: [%{id: "main", fields: ["dimensions", "title"]}]
      }

      definition = compile!(declaration)

      assert %Node.Group{children: root_group_children} = Info.node(definition, "/#main")
      assert Enum.map(root_group_children, & &1.name) == ["dimensions", "title"]

      assert %Node.Group{children: nested_group_children} =
               Info.node(definition, "/dimensions#size")

      assert Enum.map(nested_group_children, & &1.name) == ["height", "width"]

      assert Enum.map(Info.fields(definition), & &1.name) ==
               ["title", "width", "depth", "height", "notes"]

      assert %Node.Field{} = Info.node_at(definition, ["dimensions", "width"])
      assert Info.node_at(definition, ["main", "dimensions", "width"]) == nil
      assert Info.node_at(definition, ["dimensions", "size", "width"]) == nil
    end
  end

  describe "nested objects" do
    test "an object property compiles to a data-nesting group with reachable children" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"dimensions",
             %{
               kind: :object,
               title: "Dimensions",
               required: ["width"],
               properties: [
                 {"width", %{kind: :integer}},
                 {"height", %{kind: :integer}}
               ]
             }}
          ]
        })

      assert %Node.Group{nests_data?: true, id: "/dimensions", label: "Dimensions"} =
               Info.node_at(definition, ["dimensions"])

      assert %Node.Field{id: "/dimensions/width", role: :integer} =
               Info.node_at(definition, ["dimensions", "width"])

      assert Info.required?(definition, ["dimensions", "width"]) == true
      assert Info.required?(definition, ["dimensions", "height"]) == false

      assert Info.origins(definition, ["dimensions", "width"])[:label] ==
               {:inference, :label_from_name}
    end

    test "a nested object supports its own presentation groups" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"dimensions",
             %{
               kind: :object,
               properties: [
                 {"width", %{kind: :integer}},
                 {"height", %{kind: :integer}}
               ],
               groups: [%{id: "size", title: "Size", fields: ["width", "height"]}]
             }}
          ]
        })

      assert %Node.Group{nests_data?: false, id: "/dimensions#size"} =
               Info.node(definition, "/dimensions#size")

      assert %Node.Field{group: "size", id: "/dimensions/width"} =
               Info.node_at(definition, ["dimensions", "width"])
    end

    test "diagnostics from a nested object propagate to the definition" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"dimensions",
             %{
               kind: :object,
               properties: [{"width", %{kind: :integer}}],
               groups: [%{id: "size", title: "Size", fields: ["missing"]}]
             }}
          ]
        })

      assert [%Formentation.Diagnostic{code: :unknown_group_field, template_path: template_path}] =
               Info.diagnostics(definition)

      assert template_path.segments == ["dimensions"]
    end
  end

  describe "invalid and unsupported declarations" do
    test "a non-object root is an invalid_declaration error" do
      assert {:error, [%Formentation.Diagnostic{severity: :error, code: :invalid_declaration}]} =
               Formentation.compile(%{kind: :string}, adapter: Formentation.Source.Map)
    end

    test "a property spec without a kind is an invalid_declaration error" do
      declaration = %{kind: :object, properties: [{"broken", %{title: "No kind"}}]}

      assert {:error, [%Formentation.Diagnostic{code: :invalid_declaration}]} =
               Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "a non-list properties value is an invalid_declaration error" do
      declaration = %{
        kind: :object,
        properties: %{"b" => %{kind: :string}, "a" => %{kind: :string}}
      }

      assert {:error, [%Formentation.Diagnostic{severity: :error, code: :invalid_declaration}]} =
               Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "duplicate property names are a duplicate_property error" do
      declaration = %{
        kind: :object,
        properties: [{"x", %{kind: :string}}, {"x", %{kind: :integer}}]
      }

      assert {:error,
              [
                %Formentation.Diagnostic{
                  severity: :error,
                  code: :duplicate_property,
                  message: ~s(duplicate property "x"),
                  origin: {:map_source, [:properties, "x"]},
                  template_path: %{segments: ["x"]}
                }
              ]} = Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "nested duplicate property names report the nested path" do
      declaration = %{
        kind: :object,
        properties: [
          {"outer",
           %{
             kind: :object,
             properties: [{"x", %{kind: :string}}, {"x", %{kind: :integer}}]
           }}
        ]
      }

      assert {:error,
              [
                %Formentation.Diagnostic{
                  severity: :error,
                  code: :duplicate_property,
                  message: ~s(duplicate property "x"),
                  origin: {:map_source, [:properties, "outer", :properties, "x"]},
                  template_path: %{segments: ["outer", "x"]}
                }
              ]} = Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "a non-list required value is an invalid_declaration error" do
      declaration = %{
        kind: :object,
        required: "a",
        properties: [{"a", %{kind: :string}}]
      }

      assert {:error, [%Formentation.Diagnostic{severity: :error, code: :invalid_declaration}]} =
               Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "a non-list groups value is an invalid_declaration error" do
      declaration = %{
        kind: :object,
        properties: [{"voltage", %{kind: :number}}],
        groups: %{"electrical" => %{id: "electrical", fields: ["voltage"]}}
      }

      assert {:error, [%Formentation.Diagnostic{severity: :error, code: :invalid_declaration}]} =
               Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "a group entry missing :fields is an invalid_declaration error" do
      declaration = %{
        kind: :object,
        properties: [{"voltage", %{kind: :number}}],
        groups: [%{id: "electrical"}]
      }

      assert {:error, [%Formentation.Diagnostic{severity: :error, code: :invalid_declaration}]} =
               Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "an unknown kind compiles to an unsupported node plus a warning" do
      declaration = %{
        kind: :object,
        properties: [{"gadget", %{kind: :carousel}}, {"notes", %{kind: :string}}]
      }

      {:ok, definition, diagnostics} =
        Formentation.compile(declaration, adapter: Formentation.Source.Map)

      assert [%Formentation.Diagnostic{severity: :warning, code: :unsupported_kind}] =
               diagnostics

      assert diagnostics == Info.diagnostics(definition)
      assert %Node.Unsupported{name: "gadget"} = Info.node_at(definition, ["gadget"])
      assert Enum.map(Info.fields(definition), & &1.name) == ["notes"]
    end

    test "an unsupported node keeps required? true when listed in required" do
      declaration = %{
        kind: :object,
        required: ["gadget"],
        properties: [{"gadget", %{kind: :carousel}}]
      }

      {:ok, definition, _diagnostics} =
        Formentation.compile(declaration, adapter: Formentation.Source.Map)

      assert %Node.Unsupported{required?: true} = Info.node_at(definition, ["gadget"])
    end
  end

  describe "node budget" do
    test "max_nodes: 0 errors immediately with max_nodes_exceeded" do
      declaration = %{kind: :object, properties: [{"a", %{kind: :string}}]}

      assert {:error, [%Formentation.Diagnostic{code: :max_nodes_exceeded}]} =
               Formentation.compile(declaration, adapter: Formentation.Source.Map, max_nodes: 0)
    end

    test "a negative max_nodes errors immediately with max_nodes_exceeded" do
      declaration = %{kind: :object, properties: [{"a", %{kind: :string}}]}

      assert {:error, [%Formentation.Diagnostic{code: :max_nodes_exceeded}]} =
               Formentation.compile(declaration, adapter: Formentation.Source.Map, max_nodes: -1)
    end
  end

  describe "annotations" do
    test "examples and default carry onto the node with map_source origins" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"reviewed_by", %{kind: :string, examples: ["J. Doe"], default: "unassigned"}}
          ]
        })

      assert %Node.Field{examples: ["J. Doe"], default: "unassigned"} =
               Info.node_at(definition, ["reviewed_by"])

      origins = Info.origins(definition, ["reviewed_by"])
      assert origins[:examples] == {:map_source, [:properties, "reviewed_by", :examples]}
      assert origins[:default] == {:map_source, [:properties, "reviewed_by", :default]}
      assert Info.diagnostics(definition) == []
    end

    test "absent examples and default stay nil without origin entries" do
      definition = compile!(%{kind: :object, properties: [{"name", %{kind: :string}}]})

      assert %Node.Field{examples: nil, default: nil} = Info.node_at(definition, ["name"])
      origins = Info.origins(definition, ["name"])
      refute Keyword.has_key?(origins, :examples)
      refute Keyword.has_key?(origins, :default)
    end

    test "a non-list examples value is an invalid_declaration error" do
      {:error, [diagnostic]} =
        Formentation.compile(
          %{kind: :object, properties: [{"name", %{kind: :string, examples: "oops"}}]},
          adapter: Formentation.Source.Map
        )

      assert diagnostic.code == :invalid_declaration
      assert diagnostic.message =~ "examples"
      assert diagnostic.origin == {:map_source, [:properties, "name", :examples]}
    end

    test "an explicit nil default warns and is dropped" do
      definition =
        compile!(%{kind: :object, properties: [{"name", %{kind: :string, default: nil}}]})

      assert %Node.Field{default: nil} = Info.node_at(definition, ["name"])
      refute Keyword.has_key?(Info.origins(definition, ["name"]), :default)

      assert [%{severity: :warning, code: :unsupported_keyword} = warning] =
               Info.diagnostics(definition)

      assert warning.message =~ "nil default"
      assert warning.origin == {:map_source, [:properties, "name", :default]}
    end

    test "examples and default on an object declaration are ignored" do
      definition =
        compile!(%{
          kind: :object,
          examples: [%{"name" => "x"}],
          default: %{"name" => "x"},
          properties: [{"name", %{kind: :string}}]
        })

      assert %Node.Group{} = Info.root(definition)
      assert Info.diagnostics(definition) == []
    end

    test "help on an object declaration carries onto the group node" do
      definition =
        compile!(%{
          kind: :object,
          help: "Recorded at the end of each shift.",
          properties: [
            {"pump",
             %{
               kind: :object,
               help: "One entry per pump.",
               properties: [{"serial", %{kind: :string}}]
             }}
          ]
        })

      assert %Node.Group{help: "Recorded at the end of each shift."} = Info.root(definition)
      assert %Node.Group{help: "One entry per pump."} = Info.node_at(definition, ["pump"])

      assert Info.origins(definition, ["pump"])[:help] ==
               {:map_source, [:properties, "pump", :help]}
    end

    test "an object without help has nil help and no help origin" do
      definition = compile!(%{kind: :object, properties: []})

      assert %Node.Group{help: nil} = Info.root(definition)
      refute Keyword.has_key?(Info.origins(definition, []), :help)
    end

    test "an explicit nil examples value is an invalid_declaration error" do
      {:error, [diagnostic]} =
        Formentation.compile(
          %{kind: :object, properties: [{"name", %{kind: :string, examples: nil}}]},
          adapter: Formentation.Source.Map
        )

      assert diagnostic.code == :invalid_declaration
      assert diagnostic.origin == {:map_source, [:properties, "name", :examples]}
    end

    test "an empty examples list carries as an empty list" do
      definition =
        compile!(%{kind: :object, properties: [{"name", %{kind: :string, examples: []}}]})

      assert %Node.Field{examples: []} = Info.node_at(definition, ["name"])

      assert Info.origins(definition, ["name"])[:examples] ==
               {:map_source, [:properties, "name", :examples]}
    end
  end

  describe "policy diagnostics" do
    test "warns when a required string permits an empty value" do
      declaration = %{
        kind: :object,
        required: ["name"],
        properties: [{"name", %{kind: :string}}]
      }

      {:ok, _definition, diagnostics} =
        Formentation.compile(declaration, adapter: Formentation.Source.Map)

      assert [%Formentation.Diagnostic{severity: :warning, code: :required_permits_empty} = d] =
               diagnostics

      assert d.message =~ "minLength"
    end

    test "does not warn with minLength, without required, or with a non-empty option set" do
      for properties <- [
            [{"name", %{kind: :string, min_length: 1}}],
            [{"name", %{kind: :string, one_of: ["a", "b"]}}]
          ] do
        declaration = %{kind: :object, required: ["name"], properties: properties}

        {:ok, _definition, diagnostics} =
          Formentation.compile(declaration, adapter: Formentation.Source.Map)

        assert diagnostics == []
      end

      {:ok, _definition, []} =
        Formentation.compile(
          %{kind: :object, properties: [{"name", %{kind: :string}}]},
          adapter: Formentation.Source.Map
        )
    end

    test "warns when an option set reintroduces the empty string" do
      declaration = %{
        kind: :object,
        required: ["name"],
        properties: [{"name", %{kind: :string, one_of: ["", "a"]}}]
      }

      {:ok, _definition, diagnostics} =
        Formentation.compile(declaration, adapter: Formentation.Source.Map)

      assert [%Formentation.Diagnostic{code: :required_permits_empty}] = diagnostics
    end

    test "warns on reserved transport property names" do
      declaration = %{
        kind: :object,
        properties: [
          {"_unused_note", %{kind: :string}},
          {"_csrf_token", %{kind: :string}},
          {"fine", %{kind: :string}}
        ]
      }

      {:ok, _definition, diagnostics} =
        Formentation.compile(declaration, adapter: Formentation.Source.Map)

      codes = Enum.map(diagnostics, & &1.code)
      assert Enum.count(codes, &(&1 == :reserved_property_name)) == 2
    end
  end

  describe "hidden and read_only hints" do
    test "boolean hints compile to node flags with origins" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"serial", %{kind: :string, read_only: true}},
            {"legacy_id", %{kind: :string, hidden: true}},
            {"note", %{kind: :string, hidden: false}}
          ]
        })

      assert %Node.Field{read_only?: true, hidden?: false} = Info.node_at(definition, ["serial"])

      assert %Node.Field{hidden?: true, read_only?: false} =
               Info.node_at(definition, ["legacy_id"])

      assert Info.origins(definition, ["serial"])[:read_only] ==
               {:map_source, [:properties, "serial", :read_only]}

      assert Info.origins(definition, ["legacy_id"])[:hidden] ==
               {:map_source, [:properties, "legacy_id", :hidden]}

      # an explicit false is applied and carries an origin — the key was declared
      assert %Node.Field{hidden?: false} = Info.node_at(definition, ["note"])

      assert Info.origins(definition, ["note"])[:hidden] ==
               {:map_source, [:properties, "note", :hidden]}
    end

    test "absent hints leave the flags false without origins" do
      definition = compile!(%{kind: :object, properties: [{"name", %{kind: :string}}]})

      assert %Node.Field{hidden?: false, read_only?: false} = Info.node_at(definition, ["name"])
      refute Keyword.has_key?(Info.origins(definition, ["name"]), :hidden)
      refute Keyword.has_key?(Info.origins(definition, ["name"]), :read_only)
    end

    test "a non-boolean hint value warns and is ignored" do
      definition =
        compile!(%{kind: :object, properties: [{"name", %{kind: :string, read_only: "yes"}}]})

      assert %Node.Field{read_only?: false} = Info.node_at(definition, ["name"])
      refute Keyword.has_key?(Info.origins(definition, ["name"]), :read_only)

      assert [%{severity: :warning, code: :invalid_hint_value} = warning] =
               Info.diagnostics(definition)

      assert warning.message =~ "read_only"
      assert warning.origin == {:map_source, [:properties, "name", :read_only]}
    end

    test "hidden and read_only on an object declaration are ignored" do
      definition =
        compile!(%{
          kind: :object,
          hidden: true,
          read_only: true,
          properties: [{"name", %{kind: :string}}]
        })

      assert Info.diagnostics(definition) == []
      assert %Node.Group{} = Info.node_at(definition, [])
    end
  end
end
