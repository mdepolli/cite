defmodule Cite.Policy do
  # Spark's reference links its headings as `#policy-...`, but ExDoc gives
  # moduledoc headings `module-` ids. Links followed by `{: ...}` point at
  # ids the reference sets itself, so they stay.
  @reference Cite.Policy.Dsl.sections()
             |> Enum.map_join("\n\n", &Spark.CheatSheet.section_cheat_sheet/1)
             |> then(&Regex.replace(~r/\]\(#(policy[\w-]*)\)(?!\{)/, &1, "](#module-\\1)"))

  @moduledoc """
  A policy: what the source is judged against, declared once in a module.

      defmodule MyApp.Riddles do
        use Cite.Policy

        concern :riddle do
          detect do
            question "Does {passage} pose a riddle?"
            yes "A question asked to be puzzled over."
            no "A plain question, a statement, or a remark."
          end
        end
      end

  Declarations: `filter`, `concern` (with `category`,
  `detect`, `confirm`, `role`, `check`), `factor`, `score`, `choice`. Every
  mistake is a compile error. The policy guide explains the language; the
  reference below, generated from the DSL, lists every declaration's
  arguments, options, and defaults (required ones starred).

  #{@reference}
  """

  use Spark.Dsl, default_extensions: [extensions: [Cite.Policy.Dsl]]
end
