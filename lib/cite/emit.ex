defmodule Cite.Emit do
  @moduledoc """
  Accepted clusters to grounded spans.

  One `Cite.Span` per grounded member, byte-exact from the source, carrying
  the cluster's class and its labelled answers as attributes. Pure. Internal.
  """

  alias Cite.{Answer, Cluster, Compare, Span}

  @doc """
  One span per grounded member, byte-exact from `source`, carrying the
  cluster's class and the labelled compare answers as attributes.
  """
  @spec spans(String.t(), [Compare.accepted()], number()) :: [Span.t()]
  def spans(source, accepted, confidence_floor) do
    Enum.flat_map(accepted, fn %{
                                 cluster: cluster,
                                 members: members,
                                 answers: answers,
                                 review?: review?
                               } ->
      attributes = attributes(cluster, answers, review?, confidence_floor)

      source
      |> Span.from_candidates(members)
      |> Enum.map(fn %Span{} = span ->
        %Span{span | class: cluster.class, attributes: attributes}
      end)
    end)
  end

  defp attributes(%Cluster{questions: questions} = cluster, answers, review?, floor) do
    labels =
      for {key, question} <- questions,
          label = Answer.label(question, answers[key], floor),
          label != nil,
          into: %{},
          do: {key, label}

    Map.merge(labels, %{
      "cluster_id" => cluster.id,
      "compare" => answers,
      "review" => review?
    })
  end
end
