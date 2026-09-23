defmodule Cite.Policy do
  @moduledoc """
  A policy: what the source is judged against, declared once in a module.

      defmodule MyApp.Riddles do
        use Cite.Policy

        concern :riddle do
          indicator do
            question "Does {passage} pose a riddle?"
            yes "A question asked to be puzzled over."
            no "A plain question, a statement, or a remark."
          end
        end
      end

  Declarations: `exclusive`, `filter`, `concern` (with `category`,
  `indicator`, `fit`, `role`, `check`), `factor`, `score`, `choice`. Every
  mistake is a compile error. See the policy guide for the full language.
  """

  use Spark.Dsl, default_extensions: [extensions: [Cite.Policy.Dsl]]

  alias Cite.Policy.{Concern, Question}
  alias Spark.Dsl.Extension

  @type t :: %__MODULE__{
          exclusive: boolean(),
          filters: [{atom(), Question.t()}],
          concerns: [Concern.t()],
          factors: [{atom(), Question.t()}],
          descriptors: [{atom(), Question.t()}]
        }

  defstruct exclusive: false, filters: [], concerns: [], factors: [], descriptors: []

  @doc false
  @spec compiled(module()) :: t()
  def compiled(module) when is_atom(module) do
    if Spark.Dsl.is?(module, __MODULE__) do
      Extension.get_persisted(module, :cite_policy)
    else
      raise ArgumentError, "#{inspect(module)} is not a Cite policy; it must `use Cite.Policy`"
    end
  end
end
