defmodule Muex.ExampleCalculator do
  @moduledoc """
  Example calculator for demonstrating mutation testing.
  """

  def add(a, b), do: a + b
  def subtract(a, b), do: a - b
  def multiply(a, b), do: a * b
  def divide(a, b), do: a / b

  def compare_equal(a, b), do: a == b
  def compare_greater(a, b), do: a > b
end
