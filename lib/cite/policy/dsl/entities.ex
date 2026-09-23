# The structs `Cite.Policy.Dsl` builds from a policy's declarations. They
# live apart from the extension so the transformers that read them
# (`Cite.Policy.Checks`, `Cite.Policy.Build`) depend on these, not on the
# extension that runs them.

defmodule Cite.Policy.Dsl.Criterion do
  @moduledoc false
  defstruct [:what, :not_for, :examples, :__spark_metadata__]
end

defmodule Cite.Policy.Dsl.Noul do
  @moduledoc false
  defstruct [:name, :question, :focus, :yes, :no, :distinct, :__spark_metadata__]
end

defmodule Cite.Policy.Dsl.Filter do
  @moduledoc false
  defstruct [:name, :question, :focus, :yes, :no, :__spark_metadata__]
end

defmodule Cite.Policy.Dsl.Factor do
  @moduledoc false
  defstruct [:name, :question, :focus, :yes, :no, :__spark_metadata__]
end

defmodule Cite.Policy.Dsl.Role do
  @moduledoc false
  defstruct [:name, :factor, :optional, :distinct, :__spark_metadata__]
end

defmodule Cite.Policy.Dsl.Concern do
  @moduledoc false
  defstruct [:name, :category, :detect, :confirm, :__spark_metadata__, roles: [], checks: []]
end

defmodule Cite.Policy.Dsl.Score do
  @moduledoc false
  defstruct [:name, :question, :focus, :levels, :__spark_metadata__]
end

defmodule Cite.Policy.Dsl.Option do
  @moduledoc false
  defstruct [:key, :description, :__spark_metadata__]
end

defmodule Cite.Policy.Dsl.Choice do
  @moduledoc false
  defstruct [:name, :question, :focus, :__spark_metadata__, options: []]
end
