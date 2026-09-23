defmodule Cite.Policy.ChecksTest do
  use ExUnit.Case, async: true

  alias Spark.Error.DslError

  # Each policy gets its own module name so the tests can run concurrently.
  defmacrop assert_policy_error(message, do: body) do
    name = Module.concat(__MODULE__, "P#{System.unique_integer([:positive])}")

    quote do
      assert_raise DslError, unquote(message), fn ->
        defmodule unquote(name) do
          use Cite.Policy
          unquote(body)
        end
      end
    end
  end

  describe "indicators and fits" do
    test "a filter without {passage}" do
      assert_policy_error ~r/filter :f must use \{passage\}/ do
        filter :f do
          question "Is the client speaking?"
          yes "y"
          no "n"
        end
      end
    end

    test "a factor naming anything but {passage}" do
      assert_policy_error ~r/factor :f may only use \{passage\}, got \{line\}/ do
        factor :f do
          question "Does {line} mention kids?"
          yes "y"
          no "n"
        end
      end
    end

    test "a fit naming anything but {passage}" do
      assert_policy_error ~r/concern :k fit may only use \{passage\}, got \{line\}/ do
        concern :k do
          indicator do
            question "Does {passage} x?"
            yes "y"
            no "n"
          end

          fit do
            question "Does {line} really x?"
            yes "y"
            no "n"
          end
        end
      end
    end

    test "a missing yes or no" do
      assert_policy_error ~r/filter :f needs yes and no/ do
        filter :f do
          question "Is {passage} x?"
          yes "y"
        end
      end
    end

    test "an indicator missing no" do
      assert_policy_error ~r/concern :k indicator needs yes and no/ do
        concern :k do
          indicator do
            question "Does {passage} x?"
            yes "y"
          end
        end
      end
    end
  end

  describe "concerns" do
    test "a fit on a concern built from roles" do
      assert_policy_error ~r/concern :k: a fit applies only to a concern with an indicator/ do
        factor :f do
          question "Does {passage} x?"
          yes "y"
          no "n"
        end

        concern :k do
          role :a, factor: :f

          fit do
            question "Does {passage} really x?"
            yes "y"
            no "n"
          end

          check :c do
            question "Is {a} fine?"
            yes "y"
            no "n"
          end
        end
      end
    end

    test "a concern with neither an indicator nor roles" do
      assert_policy_error ~r/concern :k needs an indicator or roles, not both/ do
        concern :k do
          category :c
        end
      end
    end

    test "a concern with both an indicator and roles" do
      assert_policy_error ~r/concern :k needs an indicator or roles, not both/ do
        factor :f do
          question "Does {passage} x?"
          yes "y"
          no "n"
        end

        concern :k do
          indicator do
            question "Does {passage} y?"
            yes "y"
            no "n"
          end

          role :a, factor: :f

          check :c do
            question "Is {a} fine?"
            yes "y"
            no "n"
          end
        end
      end
    end

    test "a concern built from factors with no check" do
      assert_policy_error ~r/concern :k needs a check that names only required roles and is not distinct/ do
        factor :f do
          question "Does {passage} x?"
          yes "y"
          no "n"
        end

        concern :k do
          role :a, factor: :f
        end
      end
    end

    test "a concern whose every check could be skipped" do
      assert_policy_error ~r/concern :k needs a check that names only required roles and is not distinct/ do
        factor :f do
          question "Does {passage} x?"
          yes "y"
          no "n"
        end

        concern :k do
          role :a, factor: :f
          role :b, factor: :f
          role :c, factor: :f, optional: true

          check :both do
            distinct true
            question "Do {a} and {b} agree?"
            yes "y"
            no "n"
          end

          check :with_c do
            question "Does {a} agree with {c}?"
            yes "y"
            no "n"
          end
        end
      end
    end
  end

  describe "roles" do
    test "two roles with one name in a concern" do
      assert_policy_error ~r/concern :k declares role :a twice/ do
        factor :f do
          question "Does {passage} x?"
          yes "y"
          no "n"
        end

        concern :k do
          role :a, factor: :f
          role :a, factor: :f

          check :c do
            question "Is {a} fine?"
            yes "y"
            no "n"
          end
        end
      end
    end

    test "a role naming an undeclared factor" do
      assert_policy_error ~r/role :a names factor :missing, which the policy does not declare/ do
        concern :k do
          role :a, factor: :missing

          check :c do
            question "Is {a} fine?"
            yes "y"
            no "n"
          end
        end
      end
    end

    test "a role named passage" do
      assert_policy_error ~r/concern :k: a role cannot be named :passage/ do
        factor :f do
          question "Does {passage} x?"
          yes "y"
          no "n"
        end

        concern :k do
          role :passage, factor: :f

          check :c do
            question "Is {passage} fine?"
            yes "y"
            no "n"
          end
        end
      end
    end
  end

  describe "checks" do
    test "two checks with one name in a concern" do
      assert_policy_error ~r/concern :k declares check :c twice/ do
        factor :f do
          question "Does {passage} x?"
          yes "y"
          no "n"
        end

        concern :k do
          role :a, factor: :f

          check :c do
            question "Is {a} fine?"
            yes "y"
            no "n"
          end

          check :c do
            question "Is {a} really fine?"
            yes "y"
            no "n"
          end
        end
      end
    end

    test "a check naming no role" do
      assert_policy_error ~r/check :c must use at least one of its concern's roles/ do
        factor :f do
          question "Does {passage} x?"
          yes "y"
          no "n"
        end

        concern :k do
          role :a, factor: :f

          check :c do
            question "Is this fine?"
            yes "y"
            no "n"
          end
        end
      end
    end

    test "a check naming an unknown role" do
      assert_policy_error ~r/check :c names unknown role \{earner\}/ do
        factor :f do
          question "Does {passage} x?"
          yes "y"
          no "n"
        end

        concern :k do
          role :a, factor: :f

          check :c do
            question "Does {a} match {earner}?"
            yes "y"
            no "n"
          end
        end
      end
    end

    test "a distinct check naming one role" do
      assert_policy_error ~r/distinct check :c must name at least two roles/ do
        factor :f do
          question "Does {passage} x?"
          yes "y"
          no "n"
        end

        concern :k do
          role :a, factor: :f

          check :c do
            distinct true
            question "Is {a} fine?"
            yes "y"
            no "n"
          end

          check :d do
            question "Is {a} really fine?"
            yes "y"
            no "n"
          end
        end
      end
    end
  end

  describe "names" do
    test "two indicators with one name" do
      assert_policy_error ~r/indicator name :x is declared twice/ do
        filter :x do
          question "Is {passage} x?"
          yes "y"
          no "n"
        end

        factor :x do
          question "Is {passage} x?"
          yes "y"
          no "n"
        end
      end
    end

    test "a name containing a colon" do
      assert_policy_error ~r/names must not contain ":", got :"a:b"/ do
        factor :"a:b" do
          question "Is {passage} x?"
          yes "y"
          no "n"
        end
      end
    end

    test "a check and a descriptor with one name" do
      assert_policy_error ~r/:severity names both a check and a descriptor/ do
        factor :f do
          question "Does {passage} x?"
          yes "y"
          no "n"
        end

        concern :k do
          role :a, factor: :f

          check :severity do
            question "Is {a} fine?"
            yes "y"
            no "n"
          end
        end

        score :severity do
          question "How bad?"
          levels ["a", "b"]
        end
      end
    end
  end

  describe "descriptors" do
    test "a descriptor with a placeholder" do
      assert_policy_error ~r/descriptor :severity must not use placeholders/ do
        score :severity do
          question "How bad is {passage}?"
          levels ["a", "b"]
        end
      end
    end

    test "a score with one level" do
      assert_policy_error ~r/score :s needs 2 to 10 unique levels/ do
        score :s do
          question "How bad?"
          levels ["only one"]
        end
      end
    end

    test "a score with duplicate levels" do
      assert_policy_error ~r/score :s needs 2 to 10 unique levels/ do
        score :s do
          question "How bad?"
          levels ["same", "same"]
        end
      end
    end

    test "a choice with no options" do
      assert_policy_error ~r/choice :c needs at least one option, with unique keys/ do
        choice :c do
          question "Which?"
        end
      end
    end

    test "a choice with duplicate option keys" do
      assert_policy_error ~r/choice :c needs at least one option, with unique keys/ do
        choice :c do
          question "Which?"
          option :a, "first"
          option :a, "again"
        end
      end
    end
  end
end
