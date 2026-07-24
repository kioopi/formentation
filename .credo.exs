%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "demo/"]
      },
      plugins: [{ExSlop, []}],
      checks: [
        {Credo.Check.Design.AliasUsage, false},
        {ExSlop.Check.Readability.NarratorDoc, false}
      ]
    }
  ]
}
