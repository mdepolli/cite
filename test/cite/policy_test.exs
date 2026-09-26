defmodule Cite.PolicyTest do
  use ExUnit.Case, async: true

  alias Cite.Policy.Build
  alias Cite.TestPolicies.{FocusRole, Household, Riddles, TwoConcerns}
  alias Cite.TestTerms

  describe "Build.read/1" do
    test "defaults category to the concern's name and the confirm to its detect" do
      assert Build.read(Riddles) == TestTerms.riddles()
    end

    test "compiles a full policy: filters, both kinds of concern, factors, descriptors" do
      assert Build.read(Household) == TestTerms.household()
    end

    test "compiles two directly screened concerns" do
      assert Build.read(TwoConcerns) == TestTerms.two_concerns()
    end

    test "records the roles a check's focus names" do
      assert Build.read(FocusRole) == TestTerms.focus_role()
    end

    test "raises on a module that is not a policy" do
      assert_raise ArgumentError, ~r/Enum is not a Cite policy/, fn ->
        Build.read(Enum)
      end
    end
  end

  describe "the policy language" do
    test "has no exclusive: overlapping concerns are the policy's to separate (ADR 3)" do
      source = """
      defmodule Cite.PolicyTest.Exclusive do
        use Cite.Policy
        exclusive true
      end
      """

      # The compiler's diagnostic is collected for this process only, not
      # printed; its wording is the compiler's, so only the raise is asserted.
      Code.with_diagnostics(fn ->
        assert_raise CompileError, fn -> Code.compile_string(source) end
      end)
    end
  end
end
