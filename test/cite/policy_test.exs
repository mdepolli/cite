defmodule Cite.PolicyTest do
  use ExUnit.Case, async: true

  alias Cite.Policy.Build
  alias Cite.TestPolicies.{FocusRole, Household, Riddles, TwoConcerns}
  alias Cite.TestTerms

  describe "Build.read/1" do
    test "defaults category to the concern's name, the fit to its indicator, and exclusive to false" do
      assert Build.read(Riddles) == TestTerms.riddles()
    end

    test "compiles a full policy: filters, both kinds of concern, factors, descriptors" do
      assert Build.read(Household) == TestTerms.household()
    end

    test "compiles two directly screened concerns under exclusive" do
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
end
