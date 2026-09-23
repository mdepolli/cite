defmodule Cite.Policy.Dsl do
  @moduledoc """
  The Spark extension behind `use Cite.Policy`: its declarations.
  `Cite.Policy.Checks` validates the structs they build (defined in
  `lib/cite/policy/dsl/entities.ex`) and `Cite.Policy.Build` compiles them to
  a policy's `Cite.Policy.Terms`. The `describe` and `doc` texts here are the
  DSL reference in `Cite.Policy`'s docs. Internal.
  """

  alias Cite.Policy.Dsl.{Choice, Concern, Criterion, Factor, Filter, Noul, Option, Role, Score}
  alias Spark.Dsl.{Entity, Section}

  @criterion_schema [
    what: [type: :string, required: true, doc: "What qualifies for this side."],
    not_for: [type: :string, doc: "What a reading of `what` might wrongly include."],
    examples: [type: {:list, :string}, doc: "Short phrasings that qualify."]
  ]

  @yes %Entity{
    name: :yes,
    describe:
      "What makes the answer yes: a string, or a block with `what`, `not_for`, `examples`.",
    target: Criterion,
    args: [{:optional, :what}],
    schema: @criterion_schema
  }

  @no %Entity{
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

  # Every yes/no question takes one `yes` and one `no`.
  @criteria [yes: [@yes], no: [@no]]

  @filter %Entity{
    name: :filter,
    describe: "A yes/no question every evidence passage must pass.",
    target: Filter,
    args: [:name],
    schema: @name_schema ++ @question_schema,
    entities: @criteria,
    singleton_entity_keys: [:yes, :no]
  }

  @factor %Entity{
    name: :factor,
    describe: "A yes/no question that fills a role in a concern built from factors.",
    target: Factor,
    args: [:name],
    schema: @name_schema ++ @question_schema,
    entities: @criteria,
    singleton_entity_keys: [:yes, :no]
  }

  @detect %Entity{
    name: :detect,
    describe: "The concern's round-1 question, asked of every passage.",
    target: Noul,
    schema: @question_schema,
    entities: @criteria,
    singleton_entity_keys: [:yes, :no]
  }

  @confirm %Entity{
    name: :confirm,
    describe: "The concern's round-2 question, deciding which matched passages are cited.",
    target: Noul,
    schema: @question_schema,
    entities: @criteria,
    singleton_entity_keys: [:yes, :no]
  }

  @check %Entity{
    name: :check,
    describe: "A yes/no question across a concern's roles that decides whether it holds.",
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
        ],
    entities: @criteria,
    singleton_entity_keys: [:yes, :no]
  }

  @role %Entity{
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

  @concern %Entity{
    name: :concern,
    describe: "Something a finding can be: screened directly, or built from factors.",
    target: Concern,
    args: [:name],
    schema: @name_schema ++ [category: [type: :atom, doc: "What the finding is reported as."]],
    entities: [detect: [@detect], confirm: [@confirm], roles: [@role], checks: [@check]],
    singleton_entity_keys: [:detect, :confirm]
  }

  @option %Entity{
    name: :option,
    describe: "One option of a Choice.",
    target: Option,
    args: [:key, :description],
    schema: [
      key: [type: :atom, required: true, doc: "The option's key."],
      description: [type: :string, required: true, doc: "What the option means."]
    ]
  }

  @score %Entity{
    name: :score,
    describe: "A descriptor that places each finding on ordered levels.",
    target: Score,
    args: [:name],
    schema:
      @name_schema ++
        @question_schema ++
        [levels: [type: {:list, :string}, required: true, doc: "The levels, lowest first."]]
  }

  @choice %Entity{
    name: :choice,
    describe: "A descriptor that picks one option for each finding.",
    target: Choice,
    args: [:name],
    schema: @name_schema ++ @question_schema,
    entities: [options: [@option]]
  }

  @policy %Section{
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
