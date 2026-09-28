# Labelling allergens in recipes

This guide builds a policy that reads a recipe and says which major
allergens it contains, citing the lines that carry each one. It suits a
meal-planning app, a meal-kit catalogue, or a menu being labelled: a list
like "contains milk, egg, gluten", where a person can see why.

It assumes you know food and have not used Cite before. The recipe lines
below are invented.

**A word on safety.** An allergen label protects someone's health. Cite
reads what a recipe says, as a careful reader would; it cannot know what a
brand of stock contains or what a kitchen shares. Treat "no allergen
found" as "none found in the text", never as "free of", and have a person
check labels before they reach someone with an allergy.

## What you will build

A policy module, the code that runs it on one recipe, and a result like
this:

| Allergen | Lines |
|---|---|
| gluten | "1 cup plain flour", "Whisk the flour and the egg into a smooth batter." |
| soy | "2 tbsp gluten-free soy sauce" |
| milk | "30 g butter or margarine" (depending on your choice), "Fry in the butter and serve." |
| egg | "1 egg, beaten", "Whisk the flour and the egg into a smooth batter." |

Most of it a lookup table could do. The reason to use a model is the lines
a table gets wrong. "2 tbsp gluten-free soy sauce" carries soy and no
gluten, though a word match on "soy sauce" would add gluten. "A splash of
Worcestershire sauce" carries fish. "Coconut milk" carries no milk.

You write down which allergens count and what carries them, split the
recipe into lines, and build the table from the findings. Cite asks your
questions of every line and cites the ones that fit.

## 1. Decide what counts

Before any code, settle these. They decide your labels more than any
wording will.

**Which allergens, and which definitions.** The US lists nine (milk, egg,
fish, crustacean shellfish, tree nuts, peanuts, wheat, soy, sesame); the
EU lists fourteen, and says "cereals containing gluten" where the US says
wheat. Pick one list and keep its definitions. This guide uses the US nine,
with gluten in the EU sense (wheat, barley, rye, oats) and all shellfish as
one concern.

**Usual composition.** A line carries an allergen when an ingredient it
names ordinarily contains it: ordinary soy sauce is brewed with wheat;
pesto has cheese and pine nuts; Worcestershire sauce has anchovy. A line
naming a free-from form ("gluten-free soy sauce", "dairy-free butter")
carries only what that form still has.

**Alternatives and options.** "30 g butter or margarine" and "optional:
crushed peanuts" may or may not reach the plate. Count them, since someone
may cook them, and flag them so your interface can say "may contain,
depending on your choice".

**What a step carries.** "Stir in the milk" names an ingredient and carries
milk. So does "scatter over the nuts" when the nuts the recipe lists are
walnuts: a general word for one listed ingredient still names it. "Add the
sauce" or "roll out the dough" names something made from several
ingredients. Its allergens are already on the lines that made it, so the
step carries nothing; each allergen is cited where it enters the recipe.

**Composite products.** Barbecue sauce, curry paste, a salad dressing, a
soup mix: what they contain depends on the brand. This guide counts a
prepared food only when its usual recipe settles it (pesto, Worcestershire
sauce, ordinary soy sauce). For the rest, neither a reader nor a model can
tell from the text; decide who checks them, usually against the product's
own label.

Leave out "may contain", cross-contamination, and shared equipment: the
recipe text does not say, and a label that guesses is worse than none.

## 2. Turn a recipe into a source

One recipe is one source, and one line is one passage: ingredient lines
and method steps alike.

```elixir
lines = [
  %{id: "i1", text: "1 cup plain flour", meta: %{section: "ingredients"}},
  %{id: "i2", text: "2 tbsp gluten-free soy sauce", meta: %{section: "ingredients"}},
  %{id: "i3", text: "30 g butter or margarine", meta: %{section: "ingredients"}},
  %{id: "i4", text: "1 egg, beaten", meta: %{section: "ingredients"}},
  %{id: "s1", text: "Whisk the flour and the egg into a smooth batter.", meta: %{section: "method"}},
  %{id: "s2", text: "Fry in the butter and serve.", meta: %{section: "method"}}
]

source = Cite.source(lines, as: "lines", show: [:section])
```

- **One recipe per source.** A finding is "this recipe contains milk", with
  the lines that show it. Judge a catalogue recipe by recipe.
- **Show the section.** Whether a line is an ingredient or a step helps
  the model read "the butter" in a step as the butter already listed.
- **Ids you can trace,** such as `i1` for ingredients and `s1` for steps.

## 3. Write one concern per allergen

Each allergen is a concern with a detect: a yes/no question asked of every
line. The `yes` lists what counts, hidden sources included; the `no` lists
the lookalikes and the free-from forms.

Gluten has the most hidden sources and the most free-from forms:

```elixir
concern :gluten do
  detect do
    question "Does {passage} name or use an ingredient that contains gluten: wheat, barley, rye, or oats, or a food ordinarily made from them?"
    yes "The line names wheat, spelt, semolina, couscous, bulgur, farro, barley, malt, rye, or oats, or a food ordinarily made from them: plain flour, bread, breadcrumbs, pasta, wheat or egg noodles, pastry, crackers, seitan, beer, or ordinary soy sauce. An option among alternatives or an ingredient marked optional still counts, and so does a step that uses an ingredient the recipe lists, whether it names it in full (stir in the milk, add the flour, fry the tofu) or by a general word for that one ingredient (the nuts, the oil, the seafood, the cheese) when the ingredient of that kind in this recipe contains it; not by the name of something made from several (the dough, the sauce, the dry ingredients)."
    no "The line names only a gluten-free form (gluten-free flour, tamari, rice noodles, rice or corn flour, oats labelled gluten-free), refers only to something made from the listed ingredients as a whole (the dough, the batter, the sauce, the mixture, the dry ingredients, the filling, the ravioli), which names no ingredient (its ingredient lines already carry a gluten ingredient), or names nothing made from these cereals."
  end
end
```

Milk has the lookalikes a word match trips on:

```elixir
concern :milk do
  detect do
    question "Does {passage} name or use an ingredient that contains milk: dairy milk, butter, cream, cheese, yoghurt, ghee, whey, or a food ordinarily made with them?"
    yes "The line names a dairy ingredient or a preparation that ordinarily contains one: milk, butter, cream, any cheese, yoghurt, ghee, whey, buttermilk, custard, béchamel, milk chocolate, ice cream, pesto. An option among alternatives or an ingredient marked optional still counts, and so does a step that uses an ingredient the recipe lists, whether it names it in full (stir in the milk, add the flour, fry the tofu) or by a general word for that one ingredient (the nuts, the oil, the seafood, the cheese) when the ingredient of that kind in this recipe contains it; not by the name of something made from several (the dough, the sauce, the dry ingredients)."
    no "The line names only a dairy-free, vegan, or plant substitute (oat, soy, almond, or coconut milk, vegan butter, coconut cream), names cocoa butter or a nut butter, refers only to something made from the listed ingredients as a whole (the dough, the batter, the sauce, the mixture, the dry ingredients, the filling, the ravioli), which names no ingredient (its ingredient lines already carry a dairy ingredient), or names no dairy at all."
  end
end
```

A few rules from practice:

- **Each concern names its neighbours.** Peanut's `no` names tree nuts;
  tree nut's names peanuts, coconut, and nutmeg; fish's names shellfish and
  shellfish's names fish. The model then does not have to guess where one
  ends.
- **Your rules from step 1 go in the criteria, word for word.** "An option
  among alternatives still counts" and "refers only to something made from
  the listed ingredients as a whole" are those rules. If the criteria say
  less than your labelling rules, the model fills the gap its own way.
- **Ask about what a line does, not only what it lists.** A first wording
  asked whether a line "calls for" an ingredient, and steps that use one
  ("stir in the milk") read as calling for nothing: they were missed.
  "Name or use" fixed that. Each fix then needed its boundary: a general
  word for a listed ingredient ("the nuts") counts, and a thing made from
  several ("the dough") does not, or every step after the dough is mixed
  gets cited.
- **A line can carry several allergens.** "2 tbsp soy sauce" is gluten and
  soy; "pesto" is milk and tree nut. Each concern judges it on its own.

The full policy is at the end of this guide. More on the language in
[Writing policies](../writing-policies.md).

## 4. Run it

```elixir
client = Cite.client(Cite.Provider.TypeSafe, api_key: System.fetch_env!("JEV_API_KEY"))
report = Cite.judge(client, source, MyApp.Allergens)
```

A recipe of 16 lines is one screening request, which asks all nine
questions of every line, then one judging request per allergen found. A
recipe with four allergens costs five requests.

Keep `threshold` at its default of 0.5 (see
[How judging works](../how-judging-works.md)).

## 5. From findings to a label

Each finding is one allergen, citing its lines, each `:holds` or
`:review`:

```elixir
defmodule MyApp.Label do
  alias Cite.{Citation, Finding, Passage, Report}

  # Each allergen found, with the lines that carry it and whether any of
  # them needs a person's look; :unchecked when a request failed.
  def allergens(%Report{errors: [_ | _]}), do: :unchecked

  def allergens(%Report{findings: findings}) do
    for %Finding{concern: allergen, evidence: [_ | _] = evidence} <- findings do
      lines = for %Citation{passage: %Passage{text: text}} <- evidence, do: text
      review? = Enum.any?(evidence, &(&1.verdict == :review))
      {allergen, lines, if(review?, do: :review, else: :holds)}
    end
  end
end
```

- **A failed request means the recipe was not checked.** Its lines land in
  `report.errors`. Never show a recipe with errors as free of anything;
  retry it.
- **Review goes to a person.** A `:review` line is one the model was unsure
  of. For allergens, err towards the label: show it, or check it, but do
  not drop it.
- **Keep the citations.** They are why a label can be trusted and
  corrected: "contains fish" beside "a splash of Worcestershire sauce" tells
  the reader why.
- **Flag alternatives and options in your interface.** The policy counts
  them; say "may contain, depending on your choice" where the cited line
  offers a choice.
- **Send composite products to a person.** A line such as "2 tbsp barbecue
  sauce" can be left uncited, since its usual recipe does not settle it,
  and a citation of one is a guess about the brand. Find those lines
  yourself (a list of such products is enough) and check them against the
  product's label, rather than reading their silence as "free of".

## 6. Check it against labels

Label a few dozen recipes line by line yourself, or have a careful reader
do it blind, using the rules from step 1 written down. Then compare at two
levels:

- **Recipe level**: "contains milk", right or wrong. This is what the label
  shows.
- **Line level**: which lines carry it. This is what the citations show.

Score a lookup table beside the policy: a list of ingredient words per
allergen. It is a strong baseline here, right about most plain lines, and
its false alarms include the free-from lines it reads backwards. What
matters is where the policy beats it: free-from forms, hidden sources,
steps that use an ingredient. Report those cases on their own; a handful
of "gluten-free" recipes can move a total by little and still be the
reason a user trusts the label.

Mark the lines your rules leave open, such as composite products and
alternatives, as borderline, and score them apart. Most of what both the
policy and the table miss is on these lines; mixed in, they hide how well
the clear lines are read.

Keep some recipes aside that you never read while rewording.
[Tuning against labels](../writing-policies.md#tuning-against-labels) has the
method.

## 7. When not to use Cite

A lookup table of ingredient words is cheap, fast, and right on most lines.
If your recipes come from one kitchen with a controlled ingredient list, a
table keyed on that list may be all you need.

Cite earns its place on free text from many sources: free-from forms a
word match reads backwards, prepared foods whose allergens the name does
not say, and alternatives a person has to weigh. A sound design runs both:
the table's hits are rarely wrong, and a line the table and the policy
disagree on is exactly the line to show a person.

## The whole policy

```elixir
defmodule MyApp.Allergens do
  use Cite.Policy

  concern :gluten do
    detect do
      question "Does {passage} name or use an ingredient that contains gluten: wheat, barley, rye, or oats, or a food ordinarily made from them?"
      yes "The line names wheat, spelt, semolina, couscous, bulgur, farro, barley, malt, rye, or oats, or a food ordinarily made from them: plain flour, bread, breadcrumbs, pasta, wheat or egg noodles, pastry, crackers, seitan, beer, or ordinary soy sauce. An option among alternatives or an ingredient marked optional still counts, and so does a step that uses an ingredient the recipe lists, whether it names it in full (stir in the milk, add the flour, fry the tofu) or by a general word for that one ingredient (the nuts, the oil, the seafood, the cheese) when the ingredient of that kind in this recipe contains it; not by the name of something made from several (the dough, the sauce, the dry ingredients)."
      no "The line names only a gluten-free form (gluten-free flour, tamari, rice noodles, rice or corn flour, oats labelled gluten-free), refers only to something made from the listed ingredients as a whole (the dough, the batter, the sauce, the mixture, the dry ingredients, the filling, the ravioli), which names no ingredient (its ingredient lines already carry a gluten ingredient), or names nothing made from these cereals."
    end
  end

  concern :milk do
    detect do
      question "Does {passage} name or use an ingredient that contains milk: dairy milk, butter, cream, cheese, yoghurt, ghee, whey, or a food ordinarily made with them?"
      yes "The line names a dairy ingredient or a preparation that ordinarily contains one: milk, butter, cream, any cheese, yoghurt, ghee, whey, buttermilk, custard, béchamel, milk chocolate, ice cream, pesto. An option among alternatives or an ingredient marked optional still counts, and so does a step that uses an ingredient the recipe lists, whether it names it in full (stir in the milk, add the flour, fry the tofu) or by a general word for that one ingredient (the nuts, the oil, the seafood, the cheese) when the ingredient of that kind in this recipe contains it; not by the name of something made from several (the dough, the sauce, the dry ingredients)."
      no "The line names only a dairy-free, vegan, or plant substitute (oat, soy, almond, or coconut milk, vegan butter, coconut cream), names cocoa butter or a nut butter, refers only to something made from the listed ingredients as a whole (the dough, the batter, the sauce, the mixture, the dry ingredients, the filling, the ravioli), which names no ingredient (its ingredient lines already carry a dairy ingredient), or names no dairy at all."
    end
  end

  concern :egg do
    detect do
      question "Does {passage} name or use an ingredient that contains egg: eggs, egg whites or yolks, or a food ordinarily made with them?"
      yes "The line names eggs, egg whites or yolks, or a preparation that ordinarily contains egg: mayonnaise, aioli, meringue, custard, hollandaise, egg noodles, egg wash. An option among alternatives or an ingredient marked optional still counts, and so does a step that uses an ingredient the recipe lists, whether it names it in full (stir in the milk, add the flour, fry the tofu) or by a general word for that one ingredient (the nuts, the oil, the seafood, the cheese) when the ingredient of that kind in this recipe contains it; not by the name of something made from several (the dough, the sauce, the dry ingredients)."
      no "The line names only an egg-free or vegan substitute (flax egg, egg-free mayonnaise, aquafaba), names eggplant, refers only to something made from the listed ingredients as a whole (the dough, the batter, the sauce, the mixture, the dry ingredients, the filling, the ravioli), which names no ingredient (its ingredient lines already carry egg), or names no egg at all."
    end
  end

  concern :peanut do
    detect do
      question "Does {passage} name or use an ingredient that contains peanut: peanuts, groundnuts, peanut butter, or a food ordinarily made with them?"
      yes "The line names peanuts, groundnuts, peanut butter, peanut oil, or a preparation that ordinarily contains peanut, such as satay sauce. An option among alternatives or an ingredient marked optional still counts, and so does a step that uses an ingredient the recipe lists, whether it names it in full (stir in the milk, add the flour, fry the tofu) or by a general word for that one ingredient (the nuts, the oil, the seafood, the cheese) when the ingredient of that kind in this recipe contains it; not by the name of something made from several (the dough, the sauce, the dry ingredients)."
      no "The line names only tree nuts (almonds, cashews, walnuts), a nut-free substitute, refers only to something made from the listed ingredients as a whole (the dough, the batter, the sauce, the mixture, the dry ingredients, the filling, the ravioli), which names no ingredient (its ingredient lines already carry peanut), or names no peanut at all."
    end
  end

  concern :tree_nut do
    detect do
      question "Does {passage} name or use an ingredient that contains tree nuts: almonds, hazelnuts, walnuts, cashews, pecans, pistachios, macadamias, Brazil nuts, pine nuts, chestnuts, or a food ordinarily made from them?"
      yes "The line names a tree nut or a preparation ordinarily made from one: nut butter, almond milk, marzipan, praline, almond extract, pesto, frangipane, or 'nuts' unspecified. An option among alternatives or an ingredient marked optional still counts, and so does a step that uses an ingredient the recipe lists, whether it names it in full (stir in the milk, add the flour, fry the tofu) or by a general word for that one ingredient (the nuts, the oil, the seafood, the cheese) when the ingredient of that kind in this recipe contains it; not by the name of something made from several (the dough, the sauce, the dry ingredients)."
      no "The line names only peanuts, coconut, nutmeg, water chestnuts, or a nut-free substitute, refers only to something made from the listed ingredients as a whole (the dough, the batter, the sauce, the mixture, the dry ingredients, the filling, the ravioli), which names no ingredient (its ingredient lines already carry a nut), or names no nut at all."
    end
  end

  concern :soy do
    detect do
      question "Does {passage} name or use an ingredient that contains soy: soybeans, soy sauce, tofu, tempeh, edamame, miso, soy milk, or a food ordinarily made from them?"
      yes "The line names soybeans or a preparation made from them: soy sauce, tamari, tofu, tempeh, edamame, miso, soy milk, soy flour, textured vegetable protein, soybean oil, soy lecithin. An option among alternatives or an ingredient marked optional still counts, and so does a step that uses an ingredient the recipe lists, whether it names it in full (stir in the milk, add the flour, fry the tofu) or by a general word for that one ingredient (the nuts, the oil, the seafood, the cheese) when the ingredient of that kind in this recipe contains it; not by the name of something made from several (the dough, the sauce, the dry ingredients)."
      no "The line names only a soy-free substitute (coconut aminos), refers only to something made from the listed ingredients as a whole (the dough, the batter, the sauce, the mixture, the dry ingredients, the filling, the ravioli), which names no ingredient (its ingredient lines already carry a soy ingredient), or names no soy at all."
    end
  end

  concern :fish do
    detect do
      question "Does {passage} name or use an ingredient that contains fish: any fish, anchovies, fish sauce, Worcestershire sauce, dashi, or a food ordinarily made from fish?"
      yes "The line names a fish, dried or smoked fish, or a preparation ordinarily made from fish: anchovies, fish sauce, Worcestershire sauce, dashi, fish stock, bonito flakes, surimi, caviar. An option among alternatives or an ingredient marked optional still counts, and so does a step that uses an ingredient the recipe lists, whether it names it in full (stir in the milk, add the flour, fry the tofu) or by a general word for that one ingredient (the nuts, the oil, the seafood, the cheese) when the ingredient of that kind in this recipe contains it; not by the name of something made from several (the dough, the sauce, the dry ingredients)."
      no "The line names only shellfish (shrimp, crab, clams, squid), a vegan or fish-free version of a sauce, refers only to something made from the listed ingredients as a whole (the dough, the batter, the sauce, the mixture, the dry ingredients, the filling, the ravioli), which names no ingredient (its ingredient lines already carry fish), or names no fish at all."
    end
  end

  concern :shellfish do
    detect do
      question "Does {passage} name or use an ingredient that contains shellfish: crustaceans such as shrimp, prawns, crab, lobster, or crayfish, molluscs such as clams, mussels, oysters, scallops, squid, or octopus, or a food ordinarily made from them?"
      yes "The line names a crustacean or a mollusc, or a preparation ordinarily made from one: oyster sauce, shrimp paste, seafood stock, calamari. An option among alternatives or an ingredient marked optional still counts, and so does a step that uses an ingredient the recipe lists, whether it names it in full (stir in the milk, add the flour, fry the tofu) or by a general word for that one ingredient (the nuts, the oil, the seafood, the cheese) when the ingredient of that kind in this recipe contains it; not by the name of something made from several (the dough, the sauce, the dry ingredients)."
      no "The line names only fish (salmon, cod, anchovies, fish sauce), a vegetarian oyster sauce or shellfish-free substitute, refers only to something made from the listed ingredients as a whole (the dough, the batter, the sauce, the mixture, the dry ingredients, the filling, the ravioli), which names no ingredient (its ingredient lines already carry shellfish), or names no shellfish at all."
    end
  end

  concern :sesame do
    detect do
      question "Does {passage} name or use an ingredient that contains sesame: sesame seeds, sesame oil, tahini, or a food ordinarily made from them?"
      yes "The line names sesame seeds, sesame oil, tahini, halva, gomashio, or a preparation ordinarily made with tahini. An option among alternatives or an ingredient marked optional still counts, and so does a step that uses an ingredient the recipe lists, whether it names it in full (stir in the milk, add the flour, fry the tofu) or by a general word for that one ingredient (the nuts, the oil, the seafood, the cheese) when the ingredient of that kind in this recipe contains it; not by the name of something made from several (the dough, the sauce, the dry ingredients)."
      no "The line names only a sesame-free substitute, refers only to something made from the listed ingredients as a whole (the dough, the batter, the sauce, the mixture, the dry ingredients, the filling, the ravioli), which names no ingredient (its ingredient lines already carry sesame), or names no sesame at all."
    end
  end
end
```
