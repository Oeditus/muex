# Muex

Mutation testing library for Elixir, Erlang, and other languages.

Muex evaluates test suite quality by introducing deliberate bugs (mutations) into code and verifying that tests catch them. It provides a language-agnostic architecture with dependency injection, making it easy to extend support to new languages.

## Features

- Language-agnostic architecture with pluggable language adapters
- Built-in support for Elixir and Erlang
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

Muex provides 6 comprehensive mutation strategies:

- **Arithmetic**: Mutates `+`, `-`, `*`, `/` operators (swap, remove, identity)
- **Comparison**: Mutates `==`, `!=`, `>`, `<`, `>=`, `<=`, `===`, `!==` operators
- **Boolean**: Mutates `and`, `or`, `&&`, `||`, `true`, `false`, `not` (swap, negate, remove)
- **Literal**: Mutates numbers (±1), strings (empty/append), lists (empty), atoms (change)
- **FunctionCall**: Removes function calls and swaps first two arguments
- **Conditional**: Inverts conditions, removes branches, converts `unless` to `if`

## Supported Languages

- **Elixir**: Full support with ExUnit integration
- **Erlang**: Full support with native BEAM integration

Both languages benefit from hot module swapping for efficient mutation testing.

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

## Output Formats

### Terminal (Default)
Interactive terminal output with progress indicators and summary:
```
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

### JSON Format
Structured JSON for CI/CD integration:
```bash
mix muex --format json
# Outputs: muex-report.json
```

### HTML Format
Interactive HTML report with color-coded results:
```bash
mix muex --format html
# Outputs: muex-report.html
```

## Examples

See the `examples/` directory for example projects:
- `examples/shop/` - Elixir shopping cart with comprehensive tests (48 tests covering realistic business logic)
- `examples/calculator_ex/` - Simple Elixir calculator module
- `examples/calculator.erl` - Basic Erlang example

**Note**: The examples demonstrate the mutation testing concept. For production use, consider integrating Muex into your project's mix.exs as a dependency.

## Documentation

Documentation can be found at <https://hexdocs.pm/muex>.

