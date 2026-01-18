defmodule Muex.Language.Erlang do
  @moduledoc """
  Language adapter for Erlang source code.

  This adapter uses Erlang's built-in parsing modules (:erl_scan, :erl_parse, :erl_prettypr)
  to parse, unparse, and compile Erlang source code.
  """
  @behaviour Muex.Language
  @impl true
  def parse(source) do
    with {:ok, tokens, _} <- :erl_scan.string(String.to_charlist(source)),
         {:ok, forms} <- :erl_parse.parse_form(tokens) do
      {:ok, forms}
    else
      {:error, error_info, _} -> {:error, error_info}
      {:error, error_info} -> {:error, error_info}
    end
  rescue
    e -> {:error, e}
  end

  @impl true
  def unparse(ast) do
    source = :erl_prettypr.format(ast) |> to_string()
    {:ok, source}
  rescue
    e -> {:error, e}
  end

  @impl true
  def compile(source, module_name) do
    {:ok, tokens, _} = :erl_scan.string(String.to_charlist(source))
    {:ok, forms} = :erl_parse.parse_form(tokens)

    case :compile.forms([forms], [:binary, :return_errors]) do
      {:ok, ^module_name, binary} ->
        :code.purge(module_name)
        :code.delete(module_name)

        case :code.load_binary(module_name, ~c"nofile", binary) do
          {:module, ^module_name} -> {:ok, module_name}
          {:error, reason} -> {:error, reason}
        end

      {:error, errors, _warnings} ->
        {:error, errors}
    end
  rescue
    e -> {:error, e}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  @impl true
  def file_extensions do
    [".erl"]
  end

  @impl true
  def test_file_pattern do
    ~r/_test\.erl$/
  end
end
