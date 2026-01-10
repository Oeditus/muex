defmodule Muex.Language.Elixir do
  @moduledoc """
  Language adapter for Elixir source code.

  This adapter uses Elixir's built-in `Code` and `Macro` modules to parse,
  unparse, and compile Elixir source code.
  """

  @behaviour Muex.Language

  @impl true
  def parse(source) do
    case Code.string_to_quoted(source) do
      {:ok, ast} -> {:ok, ast}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  @impl true
  def unparse(ast) do
    {:ok, Macro.to_string(ast)}
  rescue
    e -> {:error, e}
  end

  @impl true
  def compile(source, module_name) do
    try do
      [{^module_name, binary}] = Code.compile_string(source)
      :code.purge(module_name)
      {:module, ^module_name} = :code.load_binary(module_name, ~c"nofile", binary)
      {:ok, module_name}
    rescue
      e -> {:error, e}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  @impl true
  def file_extensions, do: [".ex", ".exs"]

  @impl true
  def test_file_pattern, do: ~r/_test\.exs?$/
end
