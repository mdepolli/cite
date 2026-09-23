defmodule Cite.SpanTest do
  use ExUnit.Case, async: true

  alias Cite.{Candidate, Span}

  describe "from_candidates/2" do
    test "copies each candidate's source slice with offsets and id" do
      # Arrange
      source = "Hello there world"

      candidates = [
        %Candidate{id: "U000", text: "Hello there", byte_start: 0, byte_end: 11},
        %Candidate{id: "U001", text: "world", byte_start: 12, byte_end: 17}
      ]

      # Act
      spans = Span.from_candidates(source, candidates)

      # Assert
      assert [
               %Span{
                 text: "Hello there",
                 byte_start: 0,
                 byte_end: 11,
                 candidate_id: "U000",
                 class: nil,
                 attributes: %{}
               },
               %Span{
                 text: "world",
                 byte_start: 12,
                 byte_end: 17,
                 candidate_id: "U001",
                 class: nil,
                 attributes: %{}
               }
             ] = spans
    end
  end

  describe "Jason.Encoder" do
    test "encodes enforced fields plus class and attributes" do
      assert Jason.decode!(Jason.encode!(encodable())) == %{
               "text" => "Hello there",
               "byte_start" => 0,
               "byte_end" => 11,
               "candidate_id" => "U000",
               "class" => "life_events",
               "attributes" => %{"review" => true}
             }
    end
  end

  defp encodable do
    %Span{
      text: "Hello there",
      byte_start: 0,
      byte_end: 11,
      candidate_id: "U000",
      class: "life_events",
      attributes: %{"review" => true}
    }
  end
end
