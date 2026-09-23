defmodule Cite.Policy.Dsl do
  @moduledoc """
  The Spark extension behind `use Cite.Policy`: its declarations.
  `Cite.Policy.Checks` validates the structs they build (defined in
  `lib/cite/policy/dsl/entities.ex`) and `Cite.Policy.Build` compiles them to
  a policy's `Cite.Policy.Terms`. Internal.
  """

  alias Cite.Policy.Dsl.{Choice, Concern, Criterion, Factor, Filter, Noul, Option, Role, Score}

  @criterion_schema [
    what: [type: :string, required: true, doc: "What qualifies for this side."],
    not_for: [type: :string, doc: "What a reading of `what` might wrongly include."],
    examples: [type: {:list, :string}, doc: "Short phrasings that qualify."]
  ]

  @yes %Spark.Dsl.Entity{
    name: :yes,
    describe:
      "What makes the answer yes: a string, or a block with `what`, `not_for`, `examples`.",
    target: Criterion,
    args: [{:optional, :what}],
    schema: @criterion_schema
  }

  @no %Spark.Dsl.Entity{
    name: :no,
    describe:
      "What makes the answer no: a string, or a block with `what`, `not_for`, `examples`.",
    target: Criterion,
    args: [{:optional, :what}],
    schema: @criterion_schema
  }

  @question_schema [
    question: [
      type: :string,
      required: true,
      doc: "The question, naming what it reads by placeholder."
    ],
    focus: [type: :string, doc: "One line on what to attend to."]
  ]

  @name_schema [name: [type: :atom, required: true, doc: "The name."]]

  @criteria [entities: [yes: [@yes], no: [@no]], singleton_entity_keys: [:yes, :no]]

  @filter struct!(
            Spark.Dsl.Entity,
            [
              name: :filter,
              describe: "A yes/no question every evidence passage must pass.",
              target: Filter,
              args: [:name],
              schema: @name_schema ++ @question_schema
            ] ++ @criteria
          )

  @factor struct!(
            Spark.Dsl.Entity,
            [
              name: :factor,
              describe: "A yes/no question that fills a role in a concern built from factors.",
              target: Factor,
              args: [:name],
              schema: @name_schema ++ @question_schema
            ] ++ @criteria
          )

  @indicator struct!(
               Spark.Dsl.Entity,
               [
                 name: :indicator,
                 describe: "The concern's round-1 question, asked of every passage.",
                 target: Noul,
                 schema: @question_schema
               ] ++ @criteria
             )

  @fit struct!(
         Spark.Dsl.Entity,
         [
           name: :fit,
           describe: "The concern's round-2 question, deciding which matched passages are cited.",
           target: Noul,
           schema: @question_schema
         ] ++ @criteria
       )

  @check struct!(
           Spark.Dsl.Entity,
           [
             name: :check,
             describe:
               "A yes/no question across a concern's roles that decides whether it holds.",
             target: Noul,
             args: [:name],
             schema:
               @name_schema ++
                 @question_schema ++
                 [
                   distinct: [
                     type: :boolean,
                     default: false,
                     doc: "Ask only when the named roles are different passages."
                   ]
                 ]
           ] ++ @criteria
         )

  @role %Spark.Dsl.Entity{
    name: :role,
    describe: "A role in a concern built from factors, filled by a factor's strongest match.",
    target: Role,
    args: [:name],
    schema:
      @name_schema ++
        [
          factor: [type: :atom, required: true, doc: "The factor that fills the role."],
          optional: [type: :boolean, default: false, doc: "The finding may stand without it."],
          distinct: [
            type: :boolean,
            default: false,
            doc: "It must be a passage no other role holds."
          ]
        ]
  }

  @concern %Spark.Dsl.Entity{
    name: :concern,
    describe: "Something a finding can be: screened directly, or built from factors.",
    target: Concern,
    args: [:name],
    schema: @name_schema ++ [category: [type: :atom, doc: "What the finding is reported as."]],
    entities: [indicator: [@indicator], fit: [@fit], roles: [@role], checks: [@check]],
    singleton_entity_keys: [:indicator, :fit]
  }

  @option %Spark.Dsl.Entity{
    name: :option,
    describe: "One option of a Choice.",
    target: Option,
    args: [:key, :description],
    schema: [
      key: [type: :atom, required: true, doc: "The option's key."],
      description: [type: :string, required: true, doc: "What the option means."]
    ]
  }

  @score %Spark.Dsl.Entity{
    name: :score,
    describe: "A descriptor that places each finding on ordered levels.",
    target: Score,
    args: [:name],
    schema:
      @name_schema ++
        @question_schema ++
        [levels: [type: {:list, :string}, required: true, doc: "The levels, lowest first."]]
  }

  @choice %Spark.Dsl.Entity{
    name: :choice,
    describe: "A descriptor that picks one option for each finding.",
    target: Choice,
    args: [:name],
    schema: @name_schema ++ @question_schema,
    entities: [options: [@option]]
  }

  @policy %Spark.Dsl.Section{
    name: :policy,
    describe: "What the source is judged against.",
    top_level?: true,
    schema: [
      exclusive: [
        type: :boolean,
        default: false,
        doc: "A passage is evidence for at most one directly screened concern."
      ]
    ],
    entities: [@filter, @concern, @factor, @score, @choice]
  }

  use Spark.Dsl.Extension,
    sections: [@policy],
    transformers: [Cite.Policy.Checks],
    persisters: [Cite.Policy.Build]
end
