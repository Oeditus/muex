defmodule Muex.PresetIntegrationTest do
  use ExUnit.Case, async: true

  alias Muex.Config
  alias Muex.Mutator
  alias Muex.Mutator.Literal

  # Mirrors the representative component from issue #13.
  @component ~S'''
  defmodule MyAppWeb.Components.UI.Card do
    use Phoenix.Component

    import MyAppWeb.ClassMerger, only: [cn: 1]

    attr :class, :string, default: nil
    slot :inner_block, required: true

    def card(assigns) do
      ~H"""
      <div class={cn(["rounded-lg border bg-card", @class])}>
        <%= render_slot(@inner_block) %>
      </div>
      """
    end
  end
  '''

  test "phoenix preset removes alias/DSL literal noise from a component" do
    assert {:ok, config} = Config.from_args(["--preset", "phoenix"])
    ast = Code.string_to_quoted!(@component)

    # Use the literal mutator specifically: it produced the reported noise.
    mutations =
      Mutator.walk(ast, [Literal], %{file: "card.ex", skip_calls: config.skip_calls})

    originals = Enum.map(mutations, & &1.original_ast)

    refute :Phoenix in originals
    refute :Component in originals
    refute :class in originals
    refute :inner_block in originals
    refute Enum.any?(mutations, &(&1.location.line == 0))
  end

  test "without a preset, attr/slot option atoms still produce noise (baseline)" do
    ast = Code.string_to_quoted!(@component)
    mutations = Mutator.walk(ast, [Literal], %{file: "card.ex"})
    originals = Enum.map(mutations, & &1.original_ast)

    assert :class in originals or :inner_block in originals
  end
end
