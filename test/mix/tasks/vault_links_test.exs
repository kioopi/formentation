defmodule Mix.Tasks.Vault.LinksTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Vault.Links

  doctest Mix.Tasks.Vault.Links

  describe "split_links/1" do
    test "flags a line that opens a wikilink it does not close" do
      assert Links.split_links("See [[a-note|the\nnote]] for detail.") ==
               [{1, "See [[a-note|the"}]
    end

    test "accepts links that open and close on the same line" do
      assert Links.split_links("See [[a-note]] and [[b-note|b]].") == []
    end

    test "flags a line that closes one link and opens another" do
      assert Links.split_links("[[a]] then [[b|c\nd]]") == [{1, "[[a]] then [[b|c"}]
    end

    test "reports every offender with its line number" do
      content = "ok\n\nSee [[a|b\nc]]\n\nand [[d|e\nf]]\n"

      assert Links.split_links(content) == [{3, "See [[a|b"}, {6, "and [[d|e"}]
    end

    test "trims indentation from the reported line" do
      assert Links.split_links("  - see [[a|b\n    c]]") == [{1, "- see [[a|b"}]
    end

    # A vault about a wikilink-using tool describes wikilink syntax, and code
    # samples contain brackets. Neither is a link.
    test "ignores fenced code blocks" do
      assert Links.split_links("```elixir\nx = [[1, 2]\n]\n```") == []
    end

    test "ignores inline code spans" do
      assert Links.split_links("A `[[wikilink]]` needs `[[` and `]]` on one line.") == []
    end
  end

  describe "run/1" do
    @tag :tmp_dir
    test "raises naming the file, line, and text of each split link", %{tmp_dir: tmp} do
      File.mkdir_p!(Path.join(tmp, "Techdocs"))
      File.write!(Path.join(tmp, "Techdocs/note.md"), "See [[a-note|the\nnote]].\n")

      error = assert_raise Mix.Error, fn -> Links.run([tmp]) end

      assert error.message =~ "Techdocs/note.md:1"
      assert error.message =~ "See [[a-note|the"
    end

    @tag :tmp_dir
    test "passes when every wikilink sits on one line", %{tmp_dir: tmp} do
      File.write!(Path.join(tmp, "note.md"), "See [[a-note|the note]].\n")

      assert capture_io(fn -> assert Links.run([tmp]) == :ok end) =~ "OK"
    end

    @tag :tmp_dir
    test "ignores files that are not markdown", %{tmp_dir: tmp} do
      File.write!(Path.join(tmp, "notes.txt"), "See [[a-note|the\nnote]].\n")

      assert capture_io(fn -> assert Links.run([tmp]) == :ok end) =~ "OK"
    end
  end
end
