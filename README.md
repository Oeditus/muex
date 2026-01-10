# Muex

Mutation testing library for Elixir, Erlang, and other languages.

Muex evaluates test suite quality by introducing deliberate bugs (mutations) into code and verifying that tests catch them. It provides a language-agnostic architecture with dependency injection, making it easy to extend support to new languages.

## Features

- Language-agnostic architecture with pluggable language adapters
- Built-in support for Elixir (Erlang planned)
- 6 mutation strategies:
  - Arithmetic operators (+/-, *//)
  - Comparison operators (==, !=, >, <, >=, <=)
  - Boolean logic (and/or, &&/||, true/false, not)
  - Literal values (numbers, strings, lists, atoms)
  - Function calls (remove calls, swap arguments)
  - Conditionals (if/unless mutations)
- Parallel mutation execution with configurable concurrency
- Terminal output with mutation scores and detailed reports
- Integration with ExUnit
- Hot module swapping for efficient testing

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
# Run on specific files
mix muex --files "lib/my_module.ex"

# Use specific mutators
mix muex --mutators arithmetic,comparison,boolean

# Set concurrency and timeout
mix muex --concurrency 4 --timeout 10000

# Fail if mutation score below threshold
mix muex --fail-at 80
```

## Available Mutators

- **Arithmetic**: Mutates `+`, `-`, `*`, `/` operators
- **Comparison**: Mutates `==`, `!=`, `>`, `<`, `>=`, `<=` operators
- **Boolean**: Mutates `and`, `or`, `&&`, `||`, `true`, `false`, `not`
- **Literal**: Mutates numbers, strings, lists, and atoms
- **FunctionCall**: Removes function calls and swaps arguments
- **Conditional**: Mutates `if`/`unless` statements

## Example Output

```
Loading files from lib...
Found 3 file(s)
Generating mutations...
Generated 25 mutation(s)
Running tests...

Mutation Testing Results
==================================================
Total mutants: 25
Killed: 20 (caught by tests)
Survived: 5 (not caught by tests)
Invalid: 0 (compilation errors)
Timeout: 0
==================================================
Mutation Score: 80.0%
```

## Documentation

Documentation can be found at <https://hexdocs.pm/muex>.

