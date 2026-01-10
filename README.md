# Muex

Mutation testing library for Elixir, Erlang, and other languages.

Muex evaluates test suite quality by introducing deliberate bugs (mutations) into code and verifying that tests catch them. It provides a language-agnostic architecture with dependency injection, making it easy to extend support to new languages.

## Features

- Language-agnostic architecture with pluggable language adapters
- Built-in support for Elixir and Erlang
- Configurable mutation strategies (arithmetic, comparison, boolean operators, literals)
- Parallel mutation execution
- Multiple output formats (terminal, HTML, JSON)
- Integration with ExUnit

## Installation

Add `muex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:muex, "~> 0.1.0"}
  ]
end
```

## Usage

Run mutation testing on your project:

```bash
mix muex
```

With options:

```bash
mix muex --files "lib/**/*.ex" --format html --fail-at 80
```

## Documentation

Documentation can be found at <https://hexdocs.pm/muex>.

