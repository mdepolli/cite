defmodule Cite.ResultTest do
  use ExUnit.Case, async: true

  alias Cite.{Error, Result, Span}

  describe "struct" do
    test "requires spans and errors; usage scan and rejected default to nil" do
      result = %Result{spans: [], errors: []}

      assert result.usage == nil
      assert result.scan == nil
      assert result.rejected == nil
    end

    test "holds Select diagnostics and usage" do
      span = %Span{
        text: "hi",
        byte_start: 0,
        byte_end: 2,
        candidate_id: "U000",
        class: "life_events"
      }

      error = Error.from_range(0, 2, :timeout)

      result = %Result{
        spans: [span],
        errors: [error],
        usage: %{input_tokens: 1, output_tokens: 2},
        scan: %{"U000" => %{"life_event" => 0.9}},
        rejected: %{"health:U001" => %{"members" => ["U001"]}}
      }

      assert length(result.spans) == 1
      assert length(result.errors) == 1
      assert result.usage.input_tokens == 1
      assert result.scan["U000"]["life_event"] == 0.9
    end
  end

  describe "JSON.Encoder" do
    test "matches Jason's output" do
      value = encodable()
      assert JSON.decode!(JSON.encode!(value)) == Jason.decode!(Jason.encode!(value))
    end
  end

  describe "Jason.Encoder" do
    test "encodes the full result including nested spans and errors" do
      assert Jason.decode!(Jason.encode!(encodable())) == %{
               "spans" => [
                 %{
                   "text" => "hi",
                   "byte_start" => 0,
                   "byte_end" => 2,
                   "candidate_id" => "U000",
                   "class" => "life_events",
                   "attributes" => %{}
                 }
               ],
               "errors" => [
                 %{
                   "byte_start" => 0,
                   "byte_end" => 2,
                   "candidate_ids" => [],
                   "reason" => "timeout"
                 }
               ],
               "usage" => %{"input_tokens" => 1, "output_tokens" => 2},
               "scan" => %{"U000" => %{"life_event" => 0.9}},
               "rejected" => %{"health:U001" => %{"members" => ["U001"]}}
             }
    end
  end

  defp encodable do
    span = %Span{
      text: "hi",
      byte_start: 0,
      byte_end: 2,
      candidate_id: "U000",
      class: "life_events"
    }

    %Result{
      spans: [span],
      errors: [Error.from_range(0, 2, :timeout)],
      usage: %{input_tokens: 1, output_tokens: 2},
      scan: %{"U000" => %{"life_event" => 0.9}},
      rejected: %{"health:U001" => %{"members" => ["U001"]}}
    }
  end
end
