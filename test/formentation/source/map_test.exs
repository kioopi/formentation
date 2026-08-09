defmodule Formentation.Source.MapTest do
  use ExUnit.Case, async: true

  alias Formentation.Definition.{Presentation, Semantic}
  alias Formentation.{Info, TemplatePath}
  alias Formentation.Info.Layout, as: PresentationInfo

  defp compile!(declaration, opts \\ []) do
    {:ok, definition, _diagnostics} =
      Formentation.compile(declaration, [adapter: Formentation.Source.Map] ++ opts)

    definition
  end

  describe "minimal object" do
    test "compiles a root object with one string field" do
      definition = compile!(%{kind: :object, properties: [{"name", %{kind: :string}}]})

      assert %Semantic.Object{id: "/"} = Info.root(definition)
      assert [%Semantic.Field{name: "name", id: "/name"}] = Info.fields(definition)
      assert Info.diagnostics(definition) == []
    end

    test "also emits native semantic and presentation roots" do
      definition = compile!(%{kind: :object, properties: [{"name", %{kind: :string}}]})

      assert %Semantic.Object{
               id: "/",
               template_path: %TemplatePath{segments: []},
               children: [
                 %Semantic.Field{
                   id: "/name",
                   name: "name",
                   value_type: :string,
                   template_path: %TemplatePath{segments: ["name"]}
                 }
               ]
             } = definition.semantic

      assert %Presentation.Object{
               semantic_id: "/",
               children: [
                 %Presentation.Field{
                   id: "layout:field:/name",
                   semantic_id: "/name",
                   label: "Name"
                 }
               ]
             } = definition.presentation

      assert definition.semantic_index.by_id["/name"].node == hd(definition.semantic.children)
    end

    test "node/2 finds nodes by id and node_at/2 by instance path" do
      definition = compile!(%{kind: :object, properties: [{"name", %{kind: :string}}]})

      assert %Semantic.Field{name: "name"} = Info.node(definition, "/name")
      assert %Semantic.Field{name: "name"} = Info.node_at(definition, ["name"])
      assert Info.node_at(definition, ["missing"]) == nil
    end

    test "field template paths record the property position" do
      definition = compile!(%{kind: :object, properties: [{"name", %{kind: :string}}]})

      assert %Semantic.Field{template_path: %Formentation.TemplatePath{segments: ["name"]}} =
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

      assert %PresentationInfo.Object{label: "Pump inspection"} =
               Info.presentation_root(definition)

      assert {:ok, %PresentationInfo.Field{label: "Serial number"}} =
               Info.presentation_at(definition, ["serial_number"])

      assert Info.origins(definition, ["serial_number"])[:label] ==
               {:map_source, [:properties, "serial_number", :title]}
    end

    test "a missing title falls back to a humanized name with an inference origin" do
      definition =
        compile!(%{kind: :object, properties: [{"serial_number", %{kind: :string}}]})

      assert {:ok, %PresentationInfo.Field{label: "Serial number"}} =
               Info.presentation_at(definition, ["serial_number"])

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

      assert {:ok, %PresentationInfo.Field{label: "Serial number"}} =
               Info.presentation_at(definition, ["serial_number"])

      assert Info.origins(definition, ["serial_number"])[:label] == {:inference, :label_from_name}
    end

    test "an explicit nil title still falls back to a humanized name" do
      declaration = %{kind: :object, properties: [{"first_name", %{kind: :string, title: nil}}]}

      definition = compile!(declaration)

      assert {:ok, %PresentationInfo.Field{label: "First name"}} =
               Info.presentation_at(definition, ["first_name"])
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

    test "a custom atom role passes through verbatim" do
      declaration = %{kind: :object, properties: [{"contact", %{kind: :string, role: :email}}]}

      definition = compile!(declaration)

      assert %Semantic.Field{role: :email} = Info.node_at(definition, ["contact"])
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

      {:ok, definition, []} =
        Formentation.compile(declaration, adapter: Formentation.Source.Map)

      for {name, expected} <- [
            {"name", :string},
            {"count", :integer},
            {"volume", :number},
            {"active", :boolean},
            {"when", :string},
            {"choice", :string}
          ] do
        assert %Formentation.Definition.Semantic.Field{value_type: ^expected} =
                 Formentation.Info.node_at(definition, [name])
      end

      assert %Formentation.Definition.Semantic.Object{} = Formentation.Info.root(definition)
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

      assert %Semantic.Field{options: ["good", "worn", "defective"]} =
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

    test "a nil one_of is ignored with a warning" do
      declaration = %{
        kind: :object,
        properties: [{"condition", %{kind: :string, one_of: nil}}]
      }

      assert {:ok, definition, diagnostics} =
               Formentation.compile(declaration, adapter: Formentation.Source.Map)

      assert [
               %Formentation.Diagnostic{
                 severity: :warning,
                 code: :unsupported_keyword,
                 message: "nil one_of for property \"condition\" is ignored",
                 origin: {:map_source, [:properties, "condition", :one_of]},
                 template_path: %{segments: ["condition"]}
               }
             ] = diagnostics

      assert %Semantic.Field{options: nil} = Info.node_at(definition, ["condition"])
      assert Info.role(definition, ["condition"]) == :text
      assert Info.origins(definition, ["condition"])[:role] == {:inference, :string_default}
      assert Info.origins(definition, ["condition"])[:options] == nil
    end

    test "a mixed valid list of string, integer, float, and boolean values compiles unchanged" do
      options = ["string", 42, 3.14, true, false]

      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"condition", %{kind: :string, one_of: options}}
          ]
        })

      assert %Semantic.Field{options: ^options} = Info.node_at(definition, ["condition"])
      assert Info.role(definition, ["condition"]) == :select
      assert Info.origins(definition, ["condition"])[:role] == {:inference, :one_of_select}

      assert Info.origins(definition, ["condition"])[:options] ==
               {:map_source, [:properties, "condition", :one_of]}
    end

    test "an invalid map option member fails compilation with structured diagnostic" do
      declaration = %{
        kind: :object,
        properties: [
          {"condition", %{kind: :string, one_of: ["valid", %{a: 1}]}}
        ]
      }

      assert {:error,
              [
                %Formentation.Diagnostic{
                  severity: :error,
                  code: :invalid_declaration,
                  message:
                    "one_of option 1 for property \"condition\" must be a string, number, or boolean, got: %{a: 1}",
                  origin: {:map_source, [:properties, "condition", :one_of, 1]},
                  template_path: %{segments: ["condition"]}
                }
              ]} = Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "a non-list non-nil one_of value fails compilation with structured diagnostic" do
      declaration = %{
        kind: :object,
        properties: [
          {"condition", %{kind: :string, one_of: "oops"}}
        ]
      }

      assert {:error,
              [
                %Formentation.Diagnostic{
                  severity: :error,
                  code: :invalid_declaration,
                  message: "property \"condition\" one_of: expected a list, got: \"oops\"",
                  origin: {:map_source, [:properties, "condition", :one_of]},
                  template_path: %{segments: ["condition"]}
                }
              ]} = Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "unsupported option values return invalid_declaration diagnostic" do
      invalid_values = [
        {[1], "[1]"},
        {{1}, "{1}"},
        {:foo, ":foo"},
        {nil, "nil"}
      ]

      for {invalid_val, desc} <- invalid_values do
        declaration = %{
          kind: :object,
          properties: [
            {"field", %{kind: :string, one_of: [invalid_val]}}
          ]
        }

        assert {:error,
                [
                  %Formentation.Diagnostic{
                    severity: :error,
                    code: :invalid_declaration,
                    origin: {:map_source, [:properties, "field", :one_of, 0]},
                    message: msg
                  }
                ]} =
                 Formentation.compile(declaration, adapter: Formentation.Source.Map)

        assert msg =~ desc
      end
    end

    test "reports the first invalid member in source order deterministically" do
      declaration = %{
        kind: :object,
        properties: [
          {"choice", %{kind: :string, one_of: ["valid1", %{first: 1}, "valid2", %{second: 2}]}}
        ]
      }

      assert {:error,
              [
                %Formentation.Diagnostic{
                  severity: :error,
                  code: :invalid_declaration,
                  origin: {:map_source, [:properties, "choice", :one_of, 1]},
                  message: msg
                }
              ]} = Formentation.compile(declaration, adapter: Formentation.Source.Map)

      assert msg =~ "one_of option 1"
      assert msg =~ "%{first: 1}"
    end

    test "does not return a partial option set or definition on invalid option" do
      declaration = %{
        kind: :object,
        properties: [
          {"choice", %{kind: :string, one_of: ["valid_before", %{invalid: 1}, "valid_after"]}}
        ]
      }

      result = Formentation.compile(declaration, adapter: Formentation.Source.Map)

      assert {:error,
              [
                %Formentation.Diagnostic{
                  code: :invalid_declaration,
                  origin: {:map_source, [:properties, "choice", :one_of, 1]}
                }
              ]} = result

      refute match?({:ok, _, _}, result)
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

      assert {:ok,
              %PresentationInfo.Field{widget: :textarea, help: "Visible to all technicians."}} =
               Info.presentation_at(definition, ["notes"])

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

    test "native facts and origins are split between semantic and presentation storage" do
      definition =
        compile!(%{
          kind: :object,
          properties: [
            {"mode",
             %{
               kind: :string,
               title: "Mode",
               help: "Choose carefully.",
               one_of: ["auto", "manual"],
               widget: :radio,
               hidden: true,
               read_only: true
             }}
          ]
        })

      assert %Semantic.Field{
               options: ["auto", "manual"],
               read_only?: true,
               origins: semantic_origins
             } = hd(definition.semantic.children)

      assert semantic_origins[:options] == {:map_source, [:properties, "mode", :one_of]}
      assert semantic_origins[:read_only] == {:map_source, [:properties, "mode", :read_only]}
      refute Keyword.has_key?(semantic_origins, :label)
      refute Keyword.has_key?(semantic_origins, :help)
      refute Keyword.has_key?(semantic_origins, :widget)
      refute Keyword.has_key?(semantic_origins, :hidden)

      assert %Presentation.Object{
               children: [
                 %Presentation.Field{
                   label: "Mode",
                   help: "Choose carefully.",
                   widget: :radio,
                   hidden?: true,
                   origins: presentation_origins
                 }
               ]
             } = definition.presentation

      assert presentation_origins[:label] == {:map_source, [:properties, "mode", :title]}
      assert presentation_origins[:help] == {:map_source, [:properties, "mode", :help]}
      assert presentation_origins[:widget] == {:map_source, [:properties, "mode", :widget]}
      assert presentation_origins[:hidden] == {:map_source, [:properties, "mode", :hidden]}
      refute Keyword.has_key?(presentation_origins, :read_only)
      refute Keyword.has_key?(presentation_origins, :options)
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

    test "valid groups with unique ids still compile unchanged" do
      definition = compile!(grouped_declaration())

      assert %Presentation.Object{children: children} = definition.presentation
      assert Enum.any?(children, &match?(%Presentation.Group{}, &1))
    end

    test "a group nests members in markup position without nesting data" do
      definition = compile!(grouped_declaration())

      assert [
               %PresentationInfo.Field{semantic_path: %{segments: ["serial_number"]}},
               group,
               %PresentationInfo.Field{semantic_path: %{segments: ["notes"]}}
             ] =
               Info.presentation_root(definition).children

      assert %PresentationInfo.Group{
               id: "/#electrical",
               label: "Electrical",
               children: [
                 %PresentationInfo.Field{semantic_path: %{segments: ["voltage"]}},
                 %PresentationInfo.Field{semantic_path: %{segments: ["insulation_ok"]}}
               ]
             } = group
    end

    test "native presentation groups only rearrange layout children" do
      definition = compile!(grouped_declaration())

      assert %Semantic.Object{
               children: [
                 %Semantic.Field{name: "serial_number"},
                 %Semantic.Field{name: "voltage"},
                 %Semantic.Field{name: "insulation_ok"},
                 %Semantic.Field{name: "notes"}
               ]
             } = definition.semantic

      assert %Presentation.Object{
               children: [
                 %Presentation.Field{semantic_id: "/serial_number"},
                 %Presentation.Group{
                   id: "/#electrical",
                   label: "Electrical",
                   children: [
                     %Presentation.Field{semantic_id: "/voltage"},
                     %Presentation.Field{semantic_id: "/insulation_ok"}
                   ]
                 },
                 %Presentation.Field{semantic_id: "/notes"}
               ]
             } = definition.presentation
    end

    test "members stay reachable by flat instance path and know their group" do
      definition = compile!(grouped_declaration())

      assert %Semantic.Field{} = Info.node_at(definition, ["voltage"])
      assert {:ok, %PresentationInfo.Field{}} = Info.presentation_at(definition, ["voltage"])
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

      assert %Presentation.Group{children: children} = Info.node(definition, "/#g")
      assert Enum.map(children, & &1.semantic_id) == ["/c", "/a"]

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

    test "overlapping groups warn about already consumed members and keep a usable definition" do
      declaration = %{
        kind: :object,
        properties: [
          {"a", %{kind: :string}},
          {"b", %{kind: :string}},
          {"c", %{kind: :string}}
        ],
        groups: [
          %{id: "one", fields: ["a", "b"]},
          %{id: "two", fields: ["b", "c"]}
        ]
      }

      {:ok, definition, diagnostics} =
        Formentation.compile(declaration, adapter: Formentation.Source.Map)

      assert [
               %Formentation.Diagnostic{
                 severity: :warning,
                 code: :unknown_group_field,
                 message: ~s(group "two" references unknown field "b")
               }
             ] = diagnostics

      assert [
               %PresentationInfo.Group{
                 id: "/#one",
                 children: [
                   %PresentationInfo.Field{semantic_path: %{segments: ["a"]}},
                   %PresentationInfo.Field{semantic_path: %{segments: ["b"]}}
                 ]
               },
               %PresentationInfo.Group{
                 id: "/#two",
                 children: [%PresentationInfo.Field{semantic_path: %{segments: ["c"]}}]
               }
             ] = Info.presentation_root(definition).children
    end

    test "an overlapping group with no remaining members only warns" do
      declaration = %{
        kind: :object,
        properties: [
          {"a", %{kind: :string}},
          {"b", %{kind: :string}}
        ],
        groups: [
          %{id: "one", fields: ["a", "b"]},
          %{id: "two", fields: ["b"]}
        ]
      }

      {:ok, definition, diagnostics} =
        Formentation.compile(declaration, adapter: Formentation.Source.Map)

      assert [
               %Formentation.Diagnostic{
                 severity: :warning,
                 code: :unknown_group_field,
                 message: ~s(group "two" references unknown field "b")
               }
             ] = diagnostics

      assert [%PresentationInfo.Group{id: "/#one"}] = Info.presentation_root(definition).children
      assert Info.node(definition, "/#two") == nil
    end

    test "a group naming a known unsupported occurrence does not create a presentation reference" do
      definition =
        compile!(%{
          kind: :object,
          properties: [{"legacy", %{kind: :file}}, {"name", %{kind: :string}}],
          groups: [%{id: "main", fields: ["legacy", "name"]}]
        })

      assert [%Semantic.Unsupported{name: "legacy"}, %Semantic.Field{name: "name"}] =
               definition.semantic.children

      assert %Presentation.Object{
               children: [
                 %Presentation.Group{
                   children: [%Presentation.Field{semantic_id: "/name"}]
                 }
               ]
             } = definition.presentation

      refute Enum.any?(Info.diagnostics(definition), &(&1.code == :unknown_group_field))
    end

    test "native presentation grouping handles escaped semantic ids without parsing" do
      definition =
        compile!(%{
          kind: :object,
          properties: [{"a/b#c", %{kind: :string}}, {"other", %{kind: :string}}],
          groups: [%{id: "main", fields: ["a/b#c"]}]
        })

      assert %Presentation.Object{
               children: [
                 %Presentation.Group{
                   children: [%Presentation.Field{semantic_id: "/a~1b~2c"}]
                 },
                 %Presentation.Field{semantic_id: "/other"}
               ]
             } = definition.presentation
    end

    test "a group with no known members emits diagnostics but no node" do
      declaration = %{
        kind: :object,
        properties: [{"serial_number", %{kind: :string}}],
        groups: [%{id: "electrical", title: "Electrical", fields: ["voltage", "insulation_ok"]}]
      }

      definition = compile!(declaration)

      assert [%Semantic.Field{name: "serial_number"}] = Info.root(definition).children
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

      assert [
               %PresentationInfo.Group{id: "/#electrical"},
               %PresentationInfo.Field{semantic_path: %{segments: ["notes"]}}
             ] = Info.presentation_root(definition).children
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
      assert %Presentation.Group{label: nil} = group
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

      assert [%PresentationInfo.Group{id: "/#electrical"}, %PresentationInfo.Group{id: "/#size"}] =
               Info.presentation_root(definition).children

      assert {:ok, %PresentationInfo.Field{semantic_path: %{segments: ["width"]}}} =
               Info.presentation_at(definition, ["width"])

      assert Info.diagnostics(definition) == []
    end

    test "duplicate field names in a group's fields list do not duplicate the member" do
      declaration = %{
        kind: :object,
        properties: [{"a", %{kind: :string}}],
        groups: [%{id: "g", fields: ["a", "a"]}]
      }

      definition = compile!(declaration)

      assert %Presentation.Group{children: [%Presentation.Field{semantic_id: "/a"}]} =
               Info.node(definition, "/#g")

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

      assert %Presentation.Group{children: children} = Info.node(definition, "/#g")
      assert Enum.map(children, & &1.semantic_id) == ["/c", "/a"]
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
      assert %Semantic.Field{} = Info.node_at(definition, ["voltage"])
      assert %Semantic.Object{} = Info.node_at(definition, ["dimensions"])
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

      assert %Presentation.Group{children: root_group_children} = Info.node(definition, "/#main")
      assert Enum.map(root_group_children, & &1.semantic_id) == ["/dimensions", "/title"]

      assert %Presentation.Group{children: nested_group_children} =
               Info.node(definition, "/dimensions#size")

      assert Enum.map(nested_group_children, & &1.semantic_id) ==
               ["/dimensions/height", "/dimensions/width"]

      assert Enum.map(Info.fields(definition), & &1.name) ==
               ["title", "width", "depth", "height", "notes"]

      assert %Semantic.Field{} = Info.node_at(definition, ["dimensions", "width"])
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

      assert %Semantic.Object{id: "/dimensions"} =
               Info.node_at(definition, ["dimensions"])

      assert {:ok, %PresentationInfo.Object{label: "Dimensions"}} =
               Info.presentation_at(definition, ["dimensions"])

      assert %Semantic.Field{id: "/dimensions/width", role: :integer} =
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

      assert %Presentation.Group{id: "/dimensions#size"} =
               Info.node(definition, "/dimensions#size")

      assert %Semantic.Field{id: "/dimensions/width"} =
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

      assert {:error,
              [
                %Formentation.Diagnostic{
                  severity: :error,
                  code: :invalid_declaration,
                  origin: {:map_source, [:properties]}
                }
              ]} = Formentation.compile(declaration, adapter: Formentation.Source.Map)
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

      assert {:error,
              [
                %Formentation.Diagnostic{
                  severity: :error,
                  code: :invalid_declaration,
                  origin: {:map_source, [:required]}
                }
              ]} = Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "a non-list groups value is an invalid_declaration error" do
      declaration = %{
        kind: :object,
        properties: [{"voltage", %{kind: :number}}],
        groups: %{"electrical" => %{id: "electrical", fields: ["voltage"]}}
      }

      assert {:error,
              [
                %Formentation.Diagnostic{
                  severity: :error,
                  code: :invalid_declaration,
                  origin: {:map_source, [:groups]}
                }
              ]} = Formentation.compile(declaration, adapter: Formentation.Source.Map)
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

    test "a non-binary group id is an invalid_declaration error, not a crash" do
      declaration = %{
        kind: :object,
        properties: [{"voltage", %{kind: :number}}],
        groups: [%{id: :electrical, fields: ["voltage"]}]
      }

      assert {:error,
              [
                %Formentation.Diagnostic{
                  code: :invalid_declaration,
                  origin: {:map_source, [:groups, 0, :id]}
                }
              ]} =
               Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "a non-list group fields value is an invalid_declaration error, not a crash" do
      declaration = %{
        kind: :object,
        properties: [{"voltage", %{kind: :number}}],
        groups: [%{id: "electrical", fields: "voltage"}]
      }

      assert {:error,
              [
                %Formentation.Diagnostic{
                  code: :invalid_declaration,
                  origin: {:map_source, [:groups, 0, :fields]}
                }
              ]} =
               Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "a non-binary group field member is an invalid_declaration error, not a crash" do
      declaration = %{
        kind: :object,
        properties: [{"voltage", %{kind: :number}}],
        groups: [%{id: "electrical", fields: [:voltage]}]
      }

      assert {:error,
              [
                %Formentation.Diagnostic{
                  code: :invalid_declaration,
                  origin: {:map_source, [:groups, 0, :fields, 0]}
                }
              ]} =
               Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "a duplicate group id is an invalid_declaration error, not a finalizer crash" do
      declaration = %{
        kind: :object,
        properties: [{"voltage", %{kind: :number}}, {"current", %{kind: :number}}],
        groups: [
          %{id: "electrical", fields: ["voltage"]},
          %{id: "electrical", fields: ["current"]}
        ]
      }

      assert {:error,
              [
                %Formentation.Diagnostic{
                  code: :invalid_declaration,
                  origin: {:map_source, [:groups, 1, :id]}
                }
              ]} =
               Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "a non-string, non-nil title is an invalid_declaration error" do
      declaration = %{kind: :object, properties: [{"name", %{kind: :string, title: 42}}]}

      assert {:error,
              [
                %Formentation.Diagnostic{
                  code: :invalid_declaration,
                  origin: {:map_source, [:properties, "name", :title]}
                }
              ]} =
               Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "a non-string root title is an invalid_declaration error" do
      declaration = %{kind: :object, title: :oops, properties: [{"name", %{kind: :string}}]}

      assert {:error,
              [
                %Formentation.Diagnostic{
                  code: :invalid_declaration,
                  origin: {:map_source, [:title]}
                }
              ]} =
               Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "a non-string, non-nil help is an invalid_declaration error" do
      declaration = %{kind: :object, properties: [{"name", %{kind: :string, help: ["oops"]}}]}

      assert {:error,
              [
                %Formentation.Diagnostic{
                  code: :invalid_declaration,
                  origin: {:map_source, [:properties, "name", :help]}
                }
              ]} =
               Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "a non-atom, non-nil role is an invalid_declaration error" do
      declaration = %{kind: :object, properties: [{"contact", %{kind: :string, role: "email"}}]}

      assert {:error,
              [
                %Formentation.Diagnostic{
                  code: :invalid_declaration,
                  origin: {:map_source, [:properties, "contact", :role]}
                }
              ]} =
               Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "a non-atom, non-nil widget is an invalid_declaration error" do
      declaration = %{
        kind: :object,
        properties: [{"notes", %{kind: :string, widget: "textarea"}}]
      }

      assert {:error,
              [
                %Formentation.Diagnostic{
                  code: :invalid_declaration,
                  origin: {:map_source, [:properties, "notes", :widget]}
                }
              ]} =
               Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "a non-tuple properties entry is an invalid_declaration error, not a crash" do
      for entry <- [nil, "name", %{kind: :string}, {:name}, {:name, %{kind: :string}, :extra}] do
        declaration = %{kind: :object, properties: [entry]}

        assert {:error,
                [
                  %Formentation.Diagnostic{
                    severity: :error,
                    code: :invalid_declaration,
                    origin: {:map_source, [:properties, 0]}
                  }
                ]} = Formentation.compile(declaration, adapter: Formentation.Source.Map)
      end
    end

    test "a non-binary property name is an invalid_declaration error, not a crash" do
      declaration = %{kind: :object, properties: [{:name, %{kind: :string}}]}

      assert {:error,
              [
                %Formentation.Diagnostic{
                  severity: :error,
                  code: :invalid_declaration,
                  origin: {:map_source, [:properties, 0]}
                }
              ]} = Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "a non-map property spec is an invalid_declaration error, not a crash" do
      declaration = %{kind: :object, properties: [{"name", "not-a-spec"}]}

      assert {:error,
              [
                %Formentation.Diagnostic{
                  severity: :error,
                  code: :invalid_declaration,
                  origin: {:map_source, [:properties, 0]}
                }
              ]} = Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "a malformed nested properties entry reports the nested indexed path" do
      declaration = %{
        kind: :object,
        properties: [{"outer", %{kind: :object, properties: [{"x", %{kind: :string}}, nil]}}]
      }

      assert {:error,
              [
                %Formentation.Diagnostic{
                  severity: :error,
                  code: :invalid_declaration,
                  origin: {:map_source, [:properties, "outer", :properties, 1]}
                }
              ]} = Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "the first malformed entry is reported deterministically" do
      declaration = %{kind: :object, properties: [nil, {:also_bad, %{kind: :string}}]}

      assert {:error, [%Formentation.Diagnostic{origin: {:map_source, [:properties, 0]}}]} =
               Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "a non-binary required member is an invalid_declaration error, not a crash" do
      declaration = %{kind: :object, required: [:name], properties: [{"name", %{kind: :string}}]}

      assert {:error,
              [
                %Formentation.Diagnostic{
                  severity: :error,
                  code: :invalid_declaration,
                  origin: {:map_source, [:required, 0]}
                }
              ]} = Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "a required member naming an undeclared property is an invalid_declaration error" do
      declaration = %{
        kind: :object,
        required: ["missing"],
        properties: [{"name", %{kind: :string}}]
      }

      assert {:error,
              [
                %Formentation.Diagnostic{
                  severity: :error,
                  code: :invalid_declaration,
                  origin: {:map_source, [:required, 0]}
                }
              ]} = Formentation.compile(declaration, adapter: Formentation.Source.Map)
    end

    test "duplicate required members are idempotent, not an error" do
      declaration = %{
        kind: :object,
        required: ["name", "name"],
        properties: [{"name", %{kind: :string, min_length: 1}}]
      }

      {:ok, definition, []} = Formentation.compile(declaration, adapter: Formentation.Source.Map)

      assert %Semantic.Field{required?: true} = Info.node_at(definition, ["name"])
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
      assert %Semantic.Unsupported{name: "gadget"} = Info.node_at(definition, ["gadget"])
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

      assert %Semantic.Unsupported{required?: true} = Info.node_at(definition, ["gadget"])
    end
  end

  describe "node budget" do
    test "max_nodes: 0 errors immediately with max_nodes_exceeded" do
      declaration = %{kind: :object, properties: [{"a", %{kind: :string}}]}

      assert {:error, [%Formentation.Diagnostic{code: :max_nodes_exceeded}]} =
               Formentation.compile(declaration,
                 adapter: Formentation.Source.Map,
                 max_nodes: 0
               )
    end

    test "a negative max_nodes errors immediately with max_nodes_exceeded" do
      declaration = %{kind: :object, properties: [{"a", %{kind: :string}}]}

      assert {:error, [%Formentation.Diagnostic{code: :max_nodes_exceeded}]} =
               Formentation.compile(declaration,
                 adapter: Formentation.Source.Map,
                 max_nodes: -1
               )
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

      assert %Semantic.Field{examples: ["J. Doe"], default: "unassigned"} =
               Info.node_at(definition, ["reviewed_by"])

      origins = Info.origins(definition, ["reviewed_by"])
      assert origins[:examples] == {:map_source, [:properties, "reviewed_by", :examples]}
      assert origins[:default] == {:map_source, [:properties, "reviewed_by", :default]}
      assert Info.diagnostics(definition) == []
    end

    test "absent examples and default stay nil without origin entries" do
      definition = compile!(%{kind: :object, properties: [{"name", %{kind: :string}}]})

      assert %Semantic.Field{examples: nil, default: nil} = Info.node_at(definition, ["name"])
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

      assert %Semantic.Field{default: nil} = Info.node_at(definition, ["name"])
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

      assert %Semantic.Object{} = Info.root(definition)
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

      assert %PresentationInfo.Object{help: "Recorded at the end of each shift."} =
               Info.presentation_root(definition)

      assert {:ok, %PresentationInfo.Object{help: "One entry per pump."}} =
               Info.presentation_at(definition, ["pump"])

      assert Info.origins(definition, ["pump"])[:help] ==
               {:map_source, [:properties, "pump", :help]}
    end

    test "an object without help has nil help and no help origin" do
      definition = compile!(%{kind: :object, properties: []})

      assert %PresentationInfo.Object{help: nil} = Info.presentation_root(definition)
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

      assert %Semantic.Field{examples: []} = Info.node_at(definition, ["name"])

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

      assert %Semantic.Field{read_only?: true} = Info.node_at(definition, ["serial"])

      assert {:ok, %PresentationInfo.Field{hidden?: false}} =
               Info.presentation_at(definition, ["serial"])

      assert %Semantic.Field{read_only?: false} = Info.node_at(definition, ["legacy_id"])

      assert {:ok, %PresentationInfo.Field{hidden?: true}} =
               Info.presentation_at(definition, ["legacy_id"])

      assert Info.origins(definition, ["serial"])[:read_only] ==
               {:map_source, [:properties, "serial", :read_only]}

      assert Info.origins(definition, ["legacy_id"])[:hidden] ==
               {:map_source, [:properties, "legacy_id", :hidden]}

      # an explicit false is applied and carries an origin — the key was declared
      assert {:ok, %PresentationInfo.Field{hidden?: false}} =
               Info.presentation_at(definition, ["note"])

      assert Info.origins(definition, ["note"])[:hidden] ==
               {:map_source, [:properties, "note", :hidden]}
    end

    test "absent hints leave the flags false without origins" do
      definition = compile!(%{kind: :object, properties: [{"name", %{kind: :string}}]})

      assert %Semantic.Field{read_only?: false} = Info.node_at(definition, ["name"])

      assert {:ok, %PresentationInfo.Field{hidden?: false}} =
               Info.presentation_at(definition, ["name"])

      refute Keyword.has_key?(Info.origins(definition, ["name"]), :hidden)
      refute Keyword.has_key?(Info.origins(definition, ["name"]), :read_only)
    end

    test "a non-boolean hint value warns and is ignored" do
      definition =
        compile!(%{kind: :object, properties: [{"name", %{kind: :string, read_only: "yes"}}]})

      assert %Semantic.Field{read_only?: false} = Info.node_at(definition, ["name"])
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
      assert %Semantic.Object{} = Info.node_at(definition, [])
    end
  end
end
