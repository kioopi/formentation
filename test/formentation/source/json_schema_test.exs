defmodule Formentation.Source.JSONSchemaTest do
  use ExUnit.Case, async: true

  alias Formentation.Definition.{Presentation, Semantic}
  alias Formentation.{Info, TemplatePath}
  alias Formentation.Info.Layout, as: PresentationInfo

  defp compile!(schema, opts \\ []) do
    {:ok, definition, _diagnostics} =
      Formentation.compile(schema, [adapter: Formentation.Source.JSONSchema] ++ opts)

    definition
  end

  defp presentation_key(%PresentationInfo.Group{id: id}), do: id
  defp presentation_key(%PresentationInfo.Field{template_path: path}), do: path.segments

  defp schema_with_group do
    %{
      "type" => "object",
      "properties" => %{
        "serial_number" => %{"type" => "string"},
        "voltage" => %{"type" => "number"},
        "insulation_ok" => %{"type" => "boolean"},
        "notes" => %{"type" => "string"}
      }
    }
  end

  defp electrical_hints do
    %{
      "groups" => [
        %{
          "id" => "electrical",
          "title" => "Electrical",
          "fields" => ["voltage", "insulation_ok"]
        }
      ]
    }
  end

  describe "minimal object" do
    test "compiles a root object with one string field" do
      definition =
        compile!(%{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}})

      assert %Semantic.Object{id: "/"} = Info.root(definition)
      assert [%Semantic.Field{name: "name", id: "/name"}] = Info.fields(definition)
      assert Info.diagnostics(definition) == []
    end

    test "also emits native semantic and presentation roots" do
      definition =
        compile!(%{
          "type" => "object",
          "properties" => %{"name" => %{"type" => "string"}}
        })

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

    test "properties without an order hint sort lexicographically by name" do
      definition =
        compile!(%{
          "type" => "object",
          "properties" => %{
            "zeta" => %{"type" => "string"},
            "alpha" => %{"type" => "string"},
            "mid" => %{"type" => "string"}
          }
        })

      assert Enum.map(Info.fields(definition), & &1.name) == ["alpha", "mid", "zeta"]
    end
  end

  describe "labels and origins" do
    test "title becomes the label with a json_schema pointer origin" do
      definition =
        compile!(%{
          "type" => "object",
          "title" => "Pump inspection",
          "properties" => %{
            "serial_number" => %{"type" => "string", "title" => "Serial number"}
          }
        })

      assert %PresentationInfo.Object{label: "Pump inspection"} =
               Info.presentation_root(definition)

      assert {:ok, %PresentationInfo.Field{label: "Serial number"}} =
               Info.presentation_at(definition, ["serial_number"])

      assert Info.origins(definition, ["serial_number"])[:label] ==
               {:json_schema, "/properties/serial_number/title"}
    end

    test "a missing title falls back to a humanized name with an inference origin" do
      definition =
        compile!(%{
          "type" => "object",
          "properties" => %{"serial_number" => %{"type" => "string"}}
        })

      assert {:ok, %PresentationInfo.Field{label: "Serial number"}} =
               Info.presentation_at(definition, ["serial_number"])

      assert Info.origins(definition, ["serial_number"])[:label] == {:inference, :label_from_name}
    end
  end

  describe "scalar types, roles, required, constraints" do
    test "each scalar type gets its default role with an inference origin" do
      definition =
        compile!(%{
          "type" => "object",
          "properties" => %{
            "notes" => %{"type" => "string"},
            "operating_hours" => %{"type" => "integer"},
            "voltage" => %{"type" => "number"},
            "insulation_ok" => %{"type" => "boolean"}
          }
        })

      assert Info.role(definition, ["notes"]) == :text
      assert Info.role(definition, ["operating_hours"]) == :integer
      assert Info.role(definition, ["voltage"]) == :number
      assert Info.role(definition, ["insulation_ok"]) == :boolean
      assert Info.origins(definition, ["notes"])[:role] == {:inference, :string_default}
    end

    test "names in required mark fields required" do
      definition =
        compile!(%{
          "type" => "object",
          "required" => ["serial_number"],
          "properties" => %{
            "serial_number" => %{"type" => "string"},
            "notes" => %{"type" => "string"}
          }
        })

      assert Info.required?(definition, ["serial_number"]) == true
      assert Info.required?(definition, ["notes"]) == false
    end

    test "constraint keywords normalize to the map-source constraint keys" do
      definition =
        compile!(%{
          "type" => "object",
          "properties" => %{
            "serial_number" => %{"type" => "string", "minLength" => 4, "maxLength" => 32},
            "operating_hours" => %{"type" => "integer", "minimum" => 0, "maximum" => 100_000}
          }
        })

      assert Info.node_at(definition, ["serial_number"]).constraints ==
               %{min_length: 4, max_length: 32}

      assert Info.node_at(definition, ["operating_hours"]).constraints ==
               %{min: 0, max: 100_000}
    end

    test "fields carry their scalar value type" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "count" => %{"type" => "integer"},
          "volume" => %{"type" => "number"},
          "active" => %{"type" => "boolean"},
          "when" => %{"type" => "string", "format" => "date"},
          "choice" => %{"type" => "string", "enum" => ["a", "b"]}
        }
      }

      {:ok, definition, []} =
        Formentation.compile(schema, adapter: Formentation.Source.JSONSchema)

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
    end
  end

  describe "schema-document validation and dialect" do
    test "a non-map schema is an invalid_schema error" do
      assert {:error, [%Formentation.Diagnostic{severity: :error, code: :invalid_schema}]} =
               Formentation.compile("not a schema",
                 adapter: Formentation.Source.JSONSchema
               )
    end

    test "a metaschema-invalid document reports every violation and compiles nothing" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "a" => %{"type" => 12},
          "b" => %{"type" => ["not-a-type"]}
        }
      }

      assert {:error, diagnostics} =
               Formentation.compile(schema, adapter: Formentation.Source.JSONSchema)

      assert Enum.count(diagnostics) >= 2
      assert Enum.all?(diagnostics, &(&1.code == :invalid_schema and &1.severity == :error))
    end

    test "a foreign $schema dialect is an unsupported_dialect error" do
      schema = %{
        "$schema" => "http://json-schema.org/draft-07/schema#",
        "type" => "object",
        "properties" => %{}
      }

      assert {:error, [%Formentation.Diagnostic{code: :unsupported_dialect} = diagnostic]} =
               Formentation.compile(schema, adapter: Formentation.Source.JSONSchema)

      assert diagnostic.origin == {:json_schema, "/$schema"}
    end

    test "an absent $schema is assumed to be 2020-12" do
      assert {:ok, _definition, []} =
               Formentation.compile(
                 %{"type" => "object", "properties" => %{"a" => %{"type" => "string"}}},
                 adapter: Formentation.Source.JSONSchema
               )
    end

    test "the pinned dialect passes explicitly" do
      assert {:ok, _definition, []} =
               Formentation.compile(
                 %{
                   "$schema" => "https://json-schema.org/draft/2020-12/schema",
                   "type" => "object",
                   "properties" => %{"a" => %{"type" => "string"}}
                 },
                 adapter: Formentation.Source.JSONSchema
               )
    end
  end

  describe "option sets and formats" do
    test "a string enum compiles to a select field with options" do
      definition =
        compile!(%{
          "type" => "object",
          "properties" => %{
            "condition" => %{"type" => "string", "enum" => ["good", "worn", "defective"]}
          }
        })

      assert %Semantic.Field{options: ["good", "worn", "defective"]} =
               Info.node_at(definition, ["condition"])

      assert Info.role(definition, ["condition"]) == :select
      assert Info.origins(definition, ["condition"])[:role] == {:inference, :enum_select}

      assert Info.origins(definition, ["condition"])[:options] ==
               {:json_schema, "/properties/condition/enum"}
    end

    test "format date, email, and uri become roles with schema origins" do
      definition =
        compile!(%{
          "type" => "object",
          "properties" => %{
            "last_service" => %{"type" => "string", "format" => "date"},
            "contact" => %{"type" => "string", "format" => "email"},
            "homepage" => %{"type" => "string", "format" => "uri"}
          }
        })

      assert Info.role(definition, ["last_service"]) == :date
      assert Info.role(definition, ["contact"]) == :email
      assert Info.role(definition, ["homepage"]) == :uri

      assert Info.origins(definition, ["last_service"])[:role] ==
               {:json_schema, "/properties/last_service/format"}
    end

    test "an unknown format is ignored and the type default applies" do
      definition =
        compile!(%{
          "type" => "object",
          "properties" => %{"code" => %{"type" => "string", "format" => "hostname"}}
        })

      assert Info.role(definition, ["code"]) == :text
      assert Info.origins(definition, ["code"])[:role] == {:inference, :string_default}
      assert Info.diagnostics(definition) == []
    end

    test "format wins over enum" do
      definition =
        compile!(%{
          "type" => "object",
          "properties" => %{
            "day" => %{"type" => "string", "format" => "date", "enum" => ["2026-01-01"]}
          }
        })

      assert Info.role(definition, ["day"]) == :date
      assert %Semantic.Field{options: ["2026-01-01"]} = Info.node_at(definition, ["day"])
    end
  end

  describe "unsupported constructs" do
    test "an unsupported type compiles to an unsupported node plus a warning" do
      {:ok, definition, diagnostics} =
        Formentation.compile(
          %{
            "type" => "object",
            "properties" => %{
              "tags" => %{"type" => "array", "items" => %{"type" => "string"}},
              "notes" => %{"type" => "string"}
            }
          },
          adapter: Formentation.Source.JSONSchema
        )

      assert [%Formentation.Diagnostic{severity: :warning, code: :unsupported_type} = diagnostic] =
               diagnostics

      assert diagnostic.origin == {:json_schema, "/properties/tags/type"}
      assert %Semantic.Unsupported{name: "tags"} = Info.node_at(definition, ["tags"])
      assert Enum.map(Info.fields(definition), & &1.name) == ["notes"]
    end

    test "a property schema without a usable type is unsupported_keyword" do
      {:ok, definition, diagnostics} =
        Formentation.compile(
          %{
            "type" => "object",
            "properties" => %{
              "either" => %{"oneOf" => [%{"type" => "string"}, %{"type" => "integer"}]}
            }
          },
          adapter: Formentation.Source.JSONSchema
        )

      assert [%Formentation.Diagnostic{severity: :warning, code: :unsupported_keyword}] =
               diagnostics

      assert %Semantic.Unsupported{name: "either"} = Info.node_at(definition, ["either"])
    end

    test "a non-string enum is unsupported_keyword" do
      {:ok, definition, diagnostics} =
        Formentation.compile(
          %{
            "type" => "object",
            "properties" => %{"rating" => %{"type" => "integer", "enum" => [1, 2, 3]}}
          },
          adapter: Formentation.Source.JSONSchema
        )

      assert [%Formentation.Diagnostic{severity: :warning, code: :unsupported_keyword}] =
               diagnostics

      assert %Semantic.Unsupported{name: "rating"} = Info.node_at(definition, ["rating"])
    end

    test "an unsupported node keeps required? true when listed in required" do
      {:ok, definition, _diagnostics} =
        Formentation.compile(
          %{
            "type" => "object",
            "required" => ["tags"],
            "properties" => %{"tags" => %{"type" => "array"}}
          },
          adapter: Formentation.Source.JSONSchema
        )

      assert %Semantic.Unsupported{required?: true} = Info.node_at(definition, ["tags"])
    end

    test "a non-object root is an unsupported_type error" do
      assert {:error, [%Formentation.Diagnostic{severity: :error, code: :unsupported_type}]} =
               Formentation.compile(%{"type" => "string"},
                 adapter: Formentation.Source.JSONSchema
               )
    end
  end

  describe "nested objects" do
    test "an object property compiles to a data-nesting group with reachable children" do
      definition =
        compile!(%{
          "type" => "object",
          "properties" => %{
            "dimensions" => %{
              "type" => "object",
              "title" => "Dimensions",
              "required" => ["width"],
              "properties" => %{
                "width" => %{"type" => "integer"},
                "height" => %{"type" => "integer"}
              }
            }
          }
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
  end

  describe "node budget" do
    test "max_nodes: 0 errors immediately with max_nodes_exceeded" do
      schema = %{"type" => "object", "properties" => %{"a" => %{"type" => "string"}}}

      assert {:error, [%Formentation.Diagnostic{code: :max_nodes_exceeded}]} =
               Formentation.compile(schema,
                 adapter: Formentation.Source.JSONSchema,
                 max_nodes: 0
               )
    end

    test "budget consumed inside a nested object carries over to a later sibling" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "a_nested" => %{
            "type" => "object",
            "properties" => %{"x" => %{"type" => "string"}}
          },
          "b_scalar" => %{"type" => "string"}
        }
      }

      assert {:error, [%Formentation.Diagnostic{code: :max_nodes_exceeded}]} =
               Formentation.compile(schema,
                 adapter: Formentation.Source.JSONSchema,
                 max_nodes: 3
               )

      {:ok, definition, diagnostics} =
        Formentation.compile(schema,
          adapter: Formentation.Source.JSONSchema,
          max_nodes: 4
        )

      assert diagnostics == []
      assert Enum.map(Info.fields(definition), & &1.name) == ["x", "b_scalar"]
    end
  end

  describe "ui hints: groups and field overrides" do
    test "a hint group nests members in markup position without nesting data" do
      definition = compile!(schema_with_group(), ui: electrical_hints())

      group = Info.node(definition, "/#electrical")

      assert %Presentation.Group{
               label: "Electrical",
               children: [
                 %Presentation.Field{semantic_id: "/voltage"},
                 %Presentation.Field{semantic_id: "/insulation_ok"}
               ]
             } = group

      assert group.origins[:label] == {:ui_hints, "/groups/0/title"}
      assert {:ok, %PresentationInfo.Field{}} = Info.presentation_at(definition, ["voltage"])
      assert Info.node_at(definition, ["voltage"]).id == "/voltage"
    end

    test "native UI hints split semantic read_only from presentation metadata" do
      hints = %{
        "fields" => %{
          "notes" => %{
            "widget" => "textarea",
            "help" => "Visible to all technicians.",
            "hidden" => true,
            "read_only" => true
          }
        }
      }

      definition = compile!(schema_with_group(), ui: hints)

      assert %Semantic.Field{read_only?: true, origins: semantic_origins} =
               Enum.find(definition.semantic.children, &(&1.name == "notes"))

      assert semantic_origins[:read_only] == {:ui_hints, "/fields/notes/read_only"}
      refute Keyword.has_key?(semantic_origins, :help)
      refute Keyword.has_key?(semantic_origins, :widget)
      refute Keyword.has_key?(semantic_origins, :hidden)

      assert %Presentation.Field{
               help: "Visible to all technicians.",
               widget: :textarea,
               hidden?: true,
               origins: presentation_origins
             } =
               Enum.find(
                 definition.presentation.children,
                 &match?(%Presentation.Field{semantic_id: "/notes"}, &1)
               )

      assert presentation_origins[:help] == {:ui_hints, "/fields/notes/help"}
      assert presentation_origins[:widget] == {:ui_hints, "/fields/notes/widget"}
      assert presentation_origins[:hidden] == {:ui_hints, "/fields/notes/hidden"}
      refute Keyword.has_key?(presentation_origins, :read_only)
    end

    test "native presentation group and order hints change layout only" do
      hints = %{
        "groups" => [%{"id" => "g", "fields" => ["c", "a"]}],
        "order" => ["g", "b"]
      }

      definition =
        compile!(
          %{
            "type" => "object",
            "properties" => %{
              "a" => %{"type" => "string"},
              "b" => %{"type" => "string"},
              "c" => %{"type" => "string"}
            }
          },
          ui: hints
        )

      assert Enum.map(definition.semantic.children, & &1.name) == ["a", "b", "c"]

      assert %Presentation.Object{
               children: [
                 %Presentation.Group{
                   id: "/#g",
                   children: [
                     %Presentation.Field{semantic_id: "/c"},
                     %Presentation.Field{semantic_id: "/a"}
                   ]
                 },
                 %Presentation.Field{semantic_id: "/b"}
               ]
             } = definition.presentation
    end

    test "a group naming an unknown field emits unknown_group_field" do
      hints = %{"groups" => [%{"id" => "electrical", "fields" => ["voltage", "missing"]}]}

      {:ok, _definition, diagnostics} =
        Formentation.compile(schema_with_group(),
          adapter: Formentation.Source.JSONSchema,
          ui: hints
        )

      assert [%Formentation.Diagnostic{severity: :warning, code: :unknown_group_field}] =
               diagnostics
    end

    test "a group naming a known unsupported occurrence does not warn as unknown" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "a" => %{"type" => "string"},
          "att" => %{"type" => "array"}
        }
      }

      hints = %{"groups" => [%{"id" => "g", "fields" => ["a", "att"]}]}

      {:ok, definition, diagnostics} =
        Formentation.compile(schema,
          adapter: Formentation.Source.JSONSchema,
          ui: hints
        )

      assert [%Formentation.Diagnostic{severity: :warning, code: :unsupported_type}] =
               diagnostics

      refute Enum.any?(diagnostics, &(&1.code == :unknown_group_field))

      assert %Presentation.Group{children: [%Presentation.Field{semantic_id: "/a"}]} =
               Info.node(definition, "/#g")

      assert Info.presentation_at(definition, ["att"]) == :unsupported
    end

    test "widget and help overrides carry ui_hints origins" do
      hints = %{
        "fields" => %{
          "notes" => %{"widget" => "textarea", "help" => "Visible to all technicians."}
        }
      }

      definition = compile!(schema_with_group(), ui: hints)

      assert {:ok,
              %PresentationInfo.Field{widget: :textarea, help: "Visible to all technicians."}} =
               Info.presentation_at(definition, ["notes"])

      origins = Info.origins(definition, ["notes"])
      assert origins[:widget] == {:ui_hints, "/fields/notes/widget"}
      assert origins[:help] == {:ui_hints, "/fields/notes/help"}
    end

    test "a field hint and a group hint on the same field both apply" do
      hints =
        electrical_hints()
        |> Map.put("fields", %{"voltage" => %{"widget" => "select"}})

      definition = compile!(schema_with_group(), ui: hints)

      assert %Semantic.Field{} = Info.node_at(definition, ["voltage"])

      assert {:ok, %PresentationInfo.Field{widget: :select}} =
               Info.presentation_at(definition, ["voltage"])

      assert Info.origins(definition, ["voltage"])[:widget] ==
               {:ui_hints, "/fields/voltage/widget"}
    end

    test "duplicate field names in a group's fields hint do not duplicate the member" do
      schema = %{"type" => "object", "properties" => %{"a" => %{"type" => "string"}}}
      hints = %{"groups" => [%{"id" => "g", "fields" => ["a", "a"]}]}

      definition = compile!(schema, ui: hints)

      assert %Presentation.Group{children: [%Presentation.Field{semantic_id: "/a"}]} =
               Info.node(definition, "/#g")

      assert Enum.map(Info.fields(definition), & &1.name) == ["a"]
    end

    test "semantic field order ignores reordered group and order hints" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "a" => %{"type" => "string"},
          "b" => %{"type" => "string"},
          "c" => %{"type" => "string"}
        }
      }

      hints = %{
        "groups" => [%{"id" => "g", "fields" => ["c", "a"]}],
        "order" => ["g", "b"]
      }

      definition = compile!(schema, ui: hints)

      assert %Presentation.Group{children: children} = Info.node(definition, "/#g")
      assert Enum.map(children, & &1.semantic_id) == ["/c", "/a"]

      assert Enum.map(Info.presentation_root(definition).children, &presentation_key/1) == [
               "/#g",
               ["b"]
             ]

      assert Enum.map(Info.fields(definition), & &1.name) == ["a", "b", "c"]
    end

    test "an unknown widget string warns and is ignored" do
      hints = %{"fields" => %{"notes" => %{"widget" => "carousel"}}}

      {:ok, definition, diagnostics} =
        Formentation.compile(schema_with_group(),
          adapter: Formentation.Source.JSONSchema,
          ui: hints
        )

      assert [%Formentation.Diagnostic{severity: :warning, code: :unknown_widget}] = diagnostics

      assert {:ok, %PresentationInfo.Field{widget: nil}} =
               Info.presentation_at(definition, ["notes"])
    end

    test "hints for an unknown property warn with unknown_hint_field" do
      hints = %{"fields" => %{"missing" => %{"widget" => "textarea"}}}

      {:ok, _definition, diagnostics} =
        Formentation.compile(schema_with_group(),
          adapter: Formentation.Source.JSONSchema,
          ui: hints
        )

      assert [%Formentation.Diagnostic{severity: :warning, code: :unknown_hint_field}] =
               diagnostics
    end

    test "a field hint naming an object property is silently skipped" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "serial_number" => %{"type" => "string"},
          "address" => %{
            "type" => "object",
            "properties" => %{"city" => %{"type" => "string"}}
          }
        }
      }

      hints = %{
        "fields" => %{
          "address" => %{
            "widget" => "textarea",
            "help" => "x",
            "hidden" => true,
            "read_only" => true
          }
        }
      }

      {:ok, definition, diagnostics} =
        Formentation.compile(schema,
          adapter: Formentation.Source.JSONSchema,
          ui: hints
        )

      assert diagnostics == []

      assert {:ok, %PresentationInfo.Object{help: nil}} =
               Info.presentation_at(definition, ["address"])
    end

    test "malformed hints are an invalid_ui_hints error" do
      for bad <- [
            "nope",
            %{"groups" => "nope"},
            %{"fields" => []},
            %{"order" => "nope"},
            %{"order" => ["notes", 1]},
            %{"groups" => [%{"id" => "g", "title" => 5, "fields" => []}]}
          ] do
        assert {:error, [%Formentation.Diagnostic{severity: :error, code: :invalid_ui_hints}]} =
                 Formentation.compile(schema_with_group(),
                   adapter: Formentation.Source.JSONSchema,
                   ui: bad
                 )
      end
    end
  end

  describe "ui hints: order" do
    # Baseline without an order hint: properties sort lexicographically
    # (insulation_ok, notes, serial_number, voltage) and the electrical
    # group lands at its first member's position:
    # [electrical(voltage, insulation_ok), notes, serial_number]

    test "the order hint sequences fields and groups by id" do
      hints = Map.put(electrical_hints(), "order", ["serial_number", "electrical", "notes"])
      definition = compile!(schema_with_group(), ui: hints)

      assert [
               %PresentationInfo.Field{template_path: %{segments: ["serial_number"]}},
               %PresentationInfo.Group{id: "/#electrical"},
               %PresentationInfo.Field{template_path: %{segments: ["notes"]}}
             ] = Info.presentation_root(definition).children
    end

    test "children absent from the order hint append in existing deterministic order" do
      hints = Map.put(electrical_hints(), "order", ["notes"])
      definition = compile!(schema_with_group(), ui: hints)

      assert [
               %PresentationInfo.Field{template_path: %{segments: ["notes"]}},
               %PresentationInfo.Group{id: "/#electrical"},
               %PresentationInfo.Field{template_path: %{segments: ["serial_number"]}}
             ] = Info.presentation_root(definition).children
    end

    test "a duplicated order entry does not duplicate the node" do
      hints = %{"order" => ["notes", "notes"]}
      definition = compile!(schema_with_group(), ui: hints)

      assert Enum.map(Info.presentation_root(definition).children, & &1.template_path.segments) ==
               [["notes"], ["insulation_ok"], ["serial_number"], ["voltage"]]
    end

    test "an unknown order entry warns and the rest still applies" do
      hints = Map.put(electrical_hints(), "order", ["bogus", "notes"])

      {:ok, definition, diagnostics} =
        Formentation.compile(schema_with_group(),
          adapter: Formentation.Source.JSONSchema,
          ui: hints
        )

      assert [%Formentation.Diagnostic{severity: :warning, code: :unknown_order_entry}] =
               diagnostics

      assert %PresentationInfo.Field{template_path: %{segments: ["notes"]}} =
               List.first(Info.presentation_root(definition).children)
    end
  end

  describe "annotations" do
    test "description becomes help with a json_schema origin" do
      definition =
        compile!(%{
          "type" => "object",
          "description" => "Recorded at the end of each shift.",
          "properties" => %{
            "reviewed_by" => %{
              "type" => "string",
              "description" => "Full name of the reviewing engineer."
            }
          }
        })

      assert %PresentationInfo.Object{help: "Recorded at the end of each shift."} =
               Info.presentation_root(definition)

      assert {:ok, %PresentationInfo.Field{help: "Full name of the reviewing engineer."}} =
               Info.presentation_at(definition, ["reviewed_by"])

      assert Info.origins(definition, ["reviewed_by"])[:help] ==
               {:json_schema, "/properties/reviewed_by/description"}

      assert Info.origins(definition, [])[:help] == {:json_schema, "/description"}
    end

    test "a help hint overrides a schema description and replaces the help origin" do
      definition =
        compile!(
          %{
            "type" => "object",
            "properties" => %{
              "summary" => %{"type" => "string", "description" => "Short shift summary."}
            }
          },
          ui: %{"fields" => %{"summary" => %{"help" => "Keep it under two sentences."}}}
        )

      assert {:ok, %PresentationInfo.Field{help: "Keep it under two sentences."}} =
               Info.presentation_at(definition, ["summary"])

      origins = Info.origins(definition, ["summary"])
      assert origins[:help] == {:ui_hints, "/fields/summary/help"}
      assert Enum.count(origins, fn {key, _origin} -> key == :help end) == 1
    end

    test "examples and default carry onto the node with json_schema origins" do
      definition =
        compile!(%{
          "type" => "object",
          "properties" => %{
            "reviewed_by" => %{
              "type" => "string",
              "examples" => ["J. Doe"],
              "default" => "unassigned"
            }
          }
        })

      assert %Semantic.Field{examples: ["J. Doe"], default: "unassigned"} =
               Info.node_at(definition, ["reviewed_by"])

      origins = Info.origins(definition, ["reviewed_by"])
      assert origins[:examples] == {:json_schema, "/properties/reviewed_by/examples"}
      assert origins[:default] == {:json_schema, "/properties/reviewed_by/default"}
      assert Info.diagnostics(definition) == []
    end

    test "an explicit null default warns and is dropped" do
      definition =
        compile!(%{
          "type" => "object",
          "properties" => %{"name" => %{"type" => "string", "default" => nil}}
        })

      assert %Semantic.Field{default: nil} = Info.node_at(definition, ["name"])
      refute Keyword.has_key?(Info.origins(definition, ["name"]), :default)

      assert [%{severity: :warning, code: :unsupported_keyword} = warning] =
               Info.diagnostics(definition)

      assert warning.message =~ "null default"
      assert warning.origin == {:json_schema, "/properties/name/default"}
    end

    test "default and examples on an object schema are ignored" do
      definition =
        compile!(%{
          "type" => "object",
          "default" => %{"name" => "x"},
          "examples" => [%{"name" => "x"}],
          "properties" => %{"name" => %{"type" => "string"}}
        })

      assert %Semantic.Object{} = Info.root(definition)
      assert Info.diagnostics(definition) == []
    end

    test "a non-array examples value is rejected by the metaschema pre-pass" do
      {:error, diagnostics} =
        Formentation.compile(
          %{
            "type" => "object",
            "properties" => %{"name" => %{"type" => "string", "examples" => "oops"}}
          },
          adapter: Formentation.Source.JSONSchema
        )

      assert Enum.any?(diagnostics, &(&1.code == :invalid_schema))
    end

    test "a string const compiles to a fixed single-option field" do
      definition =
        compile!(%{
          "type" => "object",
          "properties" => %{"checklist_version" => %{"type" => "string", "const" => "2"}}
        })

      assert %Semantic.Field{options: ["2"], role: :select} =
               Info.node_at(definition, ["checklist_version"])

      origins = Info.origins(definition, ["checklist_version"])
      assert origins[:options] == {:json_schema, "/properties/checklist_version/const"}
      assert origins[:role] == {:inference, :const_select}
      assert Info.diagnostics(definition) == []
    end

    test "format wins over const for the role" do
      definition =
        compile!(%{
          "type" => "object",
          "properties" => %{
            "due" => %{"type" => "string", "format" => "date", "const" => "2026-01-01"}
          }
        })

      assert Info.role(definition, ["due"]) == :date
      assert %Semantic.Field{options: ["2026-01-01"]} = Info.node_at(definition, ["due"])
    end

    test "const wins over enum for the option set" do
      definition =
        compile!(%{
          "type" => "object",
          "properties" => %{
            "condition" => %{"type" => "string", "const" => "good", "enum" => ["good", "worn"]}
          }
        })

      assert %Semantic.Field{options: ["good"]} = Info.node_at(definition, ["condition"])

      assert Info.origins(definition, ["condition"])[:options] ==
               {:json_schema, "/properties/condition/const"}

      assert Info.diagnostics(definition) == []
    end

    test "a non-string const value is unsupported_keyword" do
      definition =
        compile!(%{
          "type" => "object",
          "properties" => %{"version" => %{"type" => "string", "const" => 2}}
        })

      assert %Semantic.Unsupported{} = Info.node_at(definition, ["version"])

      assert [%{severity: :warning, code: :unsupported_keyword} = warning] =
               Info.diagnostics(definition)

      assert warning.message =~ "non-string const"
    end

    test "const on a non-string type is unsupported_keyword" do
      definition =
        compile!(%{
          "type" => "object",
          "properties" => %{"count" => %{"type" => "integer", "const" => 3}}
        })

      assert %Semantic.Unsupported{} = Info.node_at(definition, ["count"])
      assert [%{code: :unsupported_keyword} = warning] = Info.diagnostics(definition)
      assert warning.message =~ "const on a non-string type"
    end

    test "const on an object-typed property is ignored for shape derivation" do
      definition =
        compile!(%{
          "type" => "object",
          "properties" => %{
            "meta" => %{
              "type" => "object",
              "const" => %{"a" => 1},
              "properties" => %{"a" => %{"type" => "integer"}}
            }
          }
        })

      assert %Semantic.Object{} = Info.node_at(definition, ["meta"])
      assert Info.diagnostics(definition) == []
    end
  end

  describe "policy diagnostics" do
    test "warns when a required string permits an empty value" do
      schema = %{
        "type" => "object",
        "required" => ["name"],
        "properties" => %{"name" => %{"type" => "string"}}
      }

      {:ok, _definition, diagnostics} =
        Formentation.compile(schema, adapter: Formentation.Source.JSONSchema)

      assert [%Formentation.Diagnostic{severity: :warning, code: :required_permits_empty} = d] =
               diagnostics

      assert d.message =~ "minLength"
    end

    test "does not warn with minLength or a non-empty enum" do
      for name_schema <- [
            %{"type" => "string", "minLength" => 1},
            %{"type" => "string", "enum" => ["a", "b"]}
          ] do
        schema = %{
          "type" => "object",
          "required" => ["name"],
          "properties" => %{"name" => name_schema}
        }

        {:ok, _definition, diagnostics} =
          Formentation.compile(schema, adapter: Formentation.Source.JSONSchema)

        assert diagnostics == []
      end
    end

    test "warns on reserved transport property names" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "_unused_note" => %{"type" => "string"},
          "_target" => %{"type" => "string"},
          "fine" => %{"type" => "string"}
        }
      }

      {:ok, _definition, diagnostics} =
        Formentation.compile(schema, adapter: Formentation.Source.JSONSchema)

      codes = Enum.map(diagnostics, & &1.code)
      assert Enum.count(codes, &(&1 == :reserved_property_name)) == 2
    end
  end

  describe "diagnostic ordering across the compile pipeline" do
    # The four diagnostic categories are produced at four different stages, and
    # the order they end up in is a compile-pipeline fact rather than an
    # accident of any one stage: the walk accumulates context diagnostics,
    # `Shared.build/2` appends policy warnings as the walk closes,
    # `apply_hints/2` appends hint warnings to the build, and
    # `with_validation/2` appends last (D-052). Every other diagnostics
    # assertion in this suite checks membership or counts, so without this test
    # a reordering passes CI silently — Milestone B adds a fifth category at
    # collection nodes.
    test "runs context, then policy, then hints, then validator" do
      schema = %{
        "type" => "object",
        "properties" => %{
          # context: an unsupported keyword, raised during the walk
          "ref" => %{"$ref" => "#/$defs/missing"},
          # policy: a reserved transport name, judged on the finished tree
          "_target" => %{"type" => "string"}
        }
      }

      # hints: a field hint naming a property that does not exist
      ui = %{"fields" => %{"nope" => %{"widget" => "text"}}}

      {:ok, definition, diagnostics} =
        Formentation.compile(schema, adapter: Formentation.Source.JSONSchema, ui: ui)

      # validator: the dangling $ref also leaves the instance validator unbuildable
      assert Enum.map(diagnostics, & &1.code) == [
               :unsupported_keyword,
               :reserved_property_name,
               :unknown_hint_field,
               :validator_unavailable
             ]

      assert diagnostics == definition.diagnostics
    end
  end

  test "compiled definitions carry an instance validator; map-source ones do not" do
    {:ok, from_json, []} =
      Formentation.compile(
        %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}},
        adapter: Formentation.Source.JSONSchema
      )

    assert %Formentation.Definition.ValidationPlan{
             module: Formentation.Source.JSONSchema.Validator,
             artifact: artifact
           } =
             from_json.validation

    assert Formentation.Source.JSONSchema.Validator.validate(artifact, %{
             "name" => "ok"
           }) == []

    {:ok, from_map, []} =
      Formentation.compile(
        %{kind: :object, properties: [{"name", %{kind: :string}}]},
        adapter: Formentation.Source.Map
      )

    assert from_map.validation == nil
  end

  describe "when the instance validator cannot build" do
    defp dangling_ref_schema do
      %{
        "type" => "object",
        "properties" => %{
          "a" => %{"$ref" => "#/$defs/missing"}
        }
      }
    end

    test "a dangling local $ref still compiles, with a validator_unavailable warning" do
      assert {:ok, definition, diagnostics} =
               Formentation.compile(dangling_ref_schema(),
                 adapter: Formentation.Source.JSONSchema
               )

      assert definition.validation == nil

      codes = Enum.map(diagnostics, & &1.code)
      assert :validator_unavailable in codes
      assert :unsupported_keyword in codes

      warning = Enum.find(diagnostics, &(&1.code == :validator_unavailable))
      assert warning.severity == :warning
      assert diagnostics == definition.diagnostics
    end

    test "a remote $ref also degrades gracefully instead of raising" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "a" => %{"$ref" => "https://example.com/missing.json"}
        }
      }

      assert {:ok, definition, diagnostics} =
               Formentation.compile(schema, adapter: Formentation.Source.JSONSchema)

      assert definition.validation == nil
      assert Enum.any?(diagnostics, &(&1.code == :validator_unavailable))
    end
  end

  describe "hidden and read_only ui hints" do
    defp flags_schema do
      %{
        "$schema" => "https://json-schema.org/draft/2020-12/schema",
        "type" => "object",
        "properties" => %{
          "serial" => %{"type" => "string"},
          "legacy_id" => %{"type" => "string"}
        }
      }
    end

    test "boolean hints compile to node flags with ui-hints origins" do
      {:ok, definition, []} =
        Formentation.compile(flags_schema(),
          adapter: Formentation.Source.JSONSchema,
          ui: %{
            "fields" => %{
              "serial" => %{"read_only" => true},
              "legacy_id" => %{"hidden" => true}
            }
          }
        )

      assert %Semantic.Field{read_only?: true} = Info.node_at(definition, ["serial"])

      assert {:ok, %PresentationInfo.Field{hidden?: false}} =
               Info.presentation_at(definition, ["serial"])

      assert %Semantic.Field{read_only?: false} = Info.node_at(definition, ["legacy_id"])

      assert {:ok, %PresentationInfo.Field{hidden?: true}} =
               Info.presentation_at(definition, ["legacy_id"])

      assert Info.origins(definition, ["serial"])[:read_only] ==
               {:ui_hints, "/fields/serial/read_only"}

      assert Info.origins(definition, ["legacy_id"])[:hidden] ==
               {:ui_hints, "/fields/legacy_id/hidden"}
    end

    test "a non-boolean hint value warns and is ignored" do
      {:ok, definition, diagnostics} =
        Formentation.compile(flags_schema(),
          adapter: Formentation.Source.JSONSchema,
          ui: %{"fields" => %{"serial" => %{"hidden" => "yes"}}}
        )

      assert {:ok, %PresentationInfo.Field{hidden?: false}} =
               Info.presentation_at(definition, ["serial"])

      refute Keyword.has_key?(Info.origins(definition, ["serial"]), :hidden)

      assert [%{severity: :warning, code: :invalid_hint_value} = warning] = diagnostics
      assert warning.message =~ "hidden"
      assert warning.origin == {:ui_hints, "/fields/serial/hidden"}
    end
  end
end
