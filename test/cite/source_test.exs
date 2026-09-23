defmodule Cite.SourceTest do
  use ExUnit.Case, async: true

  alias Cite.{Passage, Source}

  describe "new/2" do
    test "keeps units in order, with the caller's ids, text, and meta" do
      # Arrange
      units = [
        %{id: "U000", text: "We've got two kids.", meta: %{speaker: "B", start: 100}},
        %{id: "U001", text: "I'm on about sixty a year.", meta: %{speaker: "B"}}
      ]

      # Act
      source = Source.new(units, as: "utterances", show: [:speaker])

      # Assert
      assert [%Passage{id: "U000", meta: %{start: 100}}, %Passage{id: "U001"}] = source.passages
      assert source.as == "utterances"
      assert source.show == [:speaker]
    end

    test "accepts bare texts and numbers them P000, P001, ..." do
      source = Source.new(["one", "two"])

      assert Enum.map(source.passages, & &1.id) == ["P000", "P001"]
      assert source.as == "passages"
      assert source.show == []
    end

    test "keeps text byte for byte, surrounding whitespace included" do
      [passage] = Source.new([" yes, that's right \n"]).passages

      assert passage.text == " yes, that's right \n"
    end

    test "defaults meta to an empty map" do
      [passage] = Source.new([%{id: "U1", text: "a"}]).passages

      assert passage.meta == %{}
    end

    test "allows an empty source" do
      assert Source.new([]).passages == []
    end

    test "raises on duplicate ids" do
      assert_raise ArgumentError, ~r/passage ids must be unique, duplicated: \["U1"\]/, fn ->
        Source.new([%{id: "U1", text: "a"}, %{id: "U1", text: "b"}])
      end
    end

    test "raises on blank or invalid UTF-8 text" do
      for text <- ["", "   ", <<0xFF, 0xFE>>] do
        assert_raise ArgumentError, ~r/text must be non-blank valid UTF-8/, fn ->
          Source.new([text])
        end
      end
    end

    test "raises on a unit that is neither a text nor a map with text" do
      for unit <- [:x, %{id: "U1"}, %{text: :x}] do
        assert_raise ArgumentError, ~r/each unit must be a text or %\{text: text\}/, fn ->
          Source.new([unit])
        end
      end
    end

    test "raises on an id or meta of the wrong type" do
      assert_raise ArgumentError, ~r/passage id must be a non-empty binary/, fn ->
        Source.new([%{id: 7, text: "a"}])
      end

      assert_raise ArgumentError, ~r/passage "P000" meta must be a map/, fn ->
        Source.new([%{text: "a", meta: [speaker: "B"]}])
      end
    end

    test "raises on an id that would break a path: a dot, a backtick, or a bracket" do
      for id <- ["3.2.1", "U`1", "U[0]", "U]"] do
        assert_raise ArgumentError, ~r/passage id .* must not contain/, fn ->
          Source.new([%{id: id, text: "a"}])
        end
      end
    end

    test "raises on an as that would break a path" do
      for as <- ["utter.ances", "`u`", "u[0]"] do
        assert_raise ArgumentError, ~r/as .* must not contain/, fn ->
          Source.new(["a"], as: as)
        end
      end
    end

    test "raises on a shown meta value that is not JSON" do
      for value <- [
            ~D[2026-09-23],
            {:ok, 1},
            self(),
            <<0xFF>>,
            [1 | 2],
            %{1 => "x"},
            %{"a" => [%{b: make_ref()}]}
          ] do
        assert_raise ArgumentError,
                     ~r/passage "P000" shows meta :at, so its value must be JSON/,
                     fn ->
                       Source.new([%{text: "a", meta: %{at: value}}], show: [:at])
                     end
      end
    end

    test "accepts shown meta that is JSON, nested or not" do
      # Arrange
      meta = %{about: %{"role" => [%{kind: :client, lead: true}], age: 41.5}, note: nil}

      # Act
      [passage] = Source.new([%{text: "a", meta: meta}], show: [:about, :note]).passages

      # Assert
      assert passage.meta == %{
               about: %{"role" => [%{kind: :client, lead: true}], age: 41.5},
               note: nil
             }
    end

    test "keeps any value in meta it does not show" do
      [passage] = Source.new([%{text: "a", meta: %{at: ~D[2026-09-23]}}]).passages

      assert passage.meta == %{at: ~D[2026-09-23]}
    end

    test "raises when show names id or text" do
      for key <- [:id, :text, "id", "text"] do
        assert_raise ArgumentError, ~r/show must not name id or text/, fn ->
          Source.new(["a"], show: [key])
        end
      end
    end

    test "raises on a blank as or a show that is not a list of keys" do
      assert_raise ArgumentError, ~r/as must be a non-empty binary/, fn ->
        Source.new(["a"], as: "")
      end

      assert_raise ArgumentError, ~r/show must be a list of atom or binary keys/, fn ->
        Source.new(["a"], show: :speaker)
      end
    end

    test "raises on unknown options" do
      assert_raise ArgumentError, fn -> Source.new(["a"], window: 3) end
    end
  end

  test "a passage encodes with Jason as id, text, and meta" do
    [passage] = Source.new([%{id: "U1", text: "a", meta: %{speaker: "B"}}]).passages

    assert Jason.decode!(Jason.encode!(passage)) == %{
             "id" => "U1",
             "text" => "a",
             "meta" => %{"speaker" => "B"}
           }
  end
end
