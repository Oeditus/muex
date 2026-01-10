# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

Muex is a language-agnostic mutation testing library for Elixir, Erlang, and other languages. It evaluates test suite quality by introducing deliberate bugs (mutations) into code and verifying that tests catch them.

## Common Commands

### Development
```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Run single test file
mix test test/path/to/test_file.exs

# Run single test (by line number)
mix test test/path/to/test_file.exs:42

# Format code (required before commit)
mix format

# Run code quality checks (format, credo, dialyzer)
mix quality

# Run CI quality checks (includes format check)
mix quality.ci
```

### Mutation Testing
```bash
# Run mutation testing on all lib files
mix muex

# Run on specific files
mix muex --files "lib/muex/*.ex"

# Use specific mutators
mix muex --mutators arithmetic,comparison,boolean,literal,function_call,conditional

# Set concurrency and timeout
mix muex --concurrency 4 --timeout 10000

# Fail if mutation score below threshold
mix muex --fail-at 80

# Generate JSON report
mix muex --format json

# Generate HTML report  
mix muex --format html
```

### Analysis Tools
```bash
# Type checking with Dialyzer
mix dialyzer

# Linting with Credo
mix credo --strict

# Test coverage
mix coveralls.json
```

## Architecture

### Core Components

The codebase follows a language-agnostic plugin architecture with clear separation of concerns:

1. **`Muex.Language` behaviour** - Defines interface for language adapters
   - `parse/1` - Converts source code to AST
   - `unparse/1` - Converts AST back to source code
   - `compile/2` - Compiles source and loads into BEAM
   - Implementations: `Muex.Language.Elixir`, `Muex.Language.Erlang` (planned)

2. **`Muex.Mutator` behaviour** - Defines interface for mutation strategies
   - `mutate/2` - Generates mutations for an AST node
   - `name/0` and `description/0` - Metadata
   - Built-in mutators:
     - `Arithmetic`: +/-, *//
     - `Comparison`: ==, !=, >, <, >=, <=
     - `Boolean`: and/or, &&/||, true/false, not
     - `Literal`: numbers, strings, lists, atoms
     - `FunctionCall`: remove calls, swap arguments
     - `Conditional`: if/unless mutations
   - Uses `Macro.prewalk/3` to traverse AST and apply all registered mutators

3. **`Muex.Loader`** - File discovery and parsing
   - Discovers source files by extension
   - Excludes test files and patterns
   - Parses files using language adapter
   - Extracts module names from AST

4. **`Muex.Compiler`** - AST compilation and hot-swapping
   - Applies mutations to AST
   - Compiles mutated code
   - Manages module hot-swapping with `:code.purge/1` and `:code.load_binary/3`
   - Restores original modules after testing

5. **`Muex.Runner`** - Test execution engine
   - Runs tests against mutated code
   - Classifies results: `:killed`, `:survived`, `:invalid`, `:timeout`
   - Parallel execution with `Task.async_stream/3`
   - Manages timing and error handling

6. **`Muex.Reporter`** - Results reporting
   - Terminal output with progress indicators
   - Summary with mutation score calculation
   - Lists survived mutations for review

7. **`Mix.Tasks.Muex`** - CLI entry point
   - Parses command-line options
   - Orchestrates the mutation testing workflow

### Data Flow

1. Loader discovers and parses source files into ASTs
2. Mutators walk ASTs and generate mutation points
3. Compiler applies each mutation and hot-swaps module
4. Runner executes tests against mutated module
5. Compiler restores original module
6. Reporter aggregates and displays results

### Key Design Patterns

- **Dependency injection**: Language adapters and mutators are passed as parameters, not hard-coded
- **Behaviour-based extensibility**: New languages and mutation strategies can be added by implementing behaviours
- **AST manipulation**: All mutations work at the AST level, enabling language-agnostic processing
- **Hot module swapping**: Uses BEAM's code reloading to test mutations without restarting the VM

## Adding New Features

### Creating a Language Adapter

Implement the `Muex.Language` behaviour in `lib/muex/language/your_language.ex`:

```elixir
defmodule Muex.Language.YourLanguage do
  @behaviour Muex.Language

  @impl true
  def parse(source), do: # Parse source to AST

  @impl true
  def unparse(ast), do: # Convert AST to source

  @impl true
  def compile(source, module_name), do: # Compile and load module

  @impl true
  def file_extensions, do: [".ext"]

  @impl true
  def test_file_pattern, do: ~r/_test\.ext$/
end
```

Register in `Mix.Tasks.Muex.get_language_adapter/1`.

### Creating a Mutator

Implement the `Muex.Mutator` behaviour in `lib/muex/mutator/your_mutator.ex`:

```elixir
defmodule Muex.Mutator.YourMutator do
  @behaviour Muex.Mutator

  @impl true
  def name, do: "YourMutator"

  @impl true
  def description, do: "Description of mutation strategy"

  @impl true
  def mutate(ast, context) do
    # Pattern match on AST nodes and return list of mutations
    # Each mutation is a map with: ast, mutator, description, location
    case ast do
      {pattern, meta, args} ->
        line = Keyword.get(meta, :line, 0)
        [build_mutation(mutated_ast, "description", context, line)]
      _ ->
        []
    end
  end
end
```

Register in `Mix.Tasks.Muex.get_mutators/1`.

## Available Mutators

### Arithmetic Mutator
Mutates arithmetic operators:
- `+` ↔ `-`
- `*` ↔ `/`
- `+` → `0` (remove addition)
- `-` → `0` (remove subtraction)
- `*` → `1` (identity)
- `/` → `1` (identity)

### Comparison Mutator
Mutates comparison operators:
- `==` ↔ `!=`
- `>` ↔ `<`, `>` ↔ `>=`
- `<` ↔ `>`, `<` ↔ `<=`
- `>=` ↔ `<=`, `>=` ↔ `>`
- `<=` ↔ `>=`, `<=` ↔ `<`
- `===` ↔ `!==`

### Boolean Mutator
Mutates boolean operators and literals:
- `and` ↔ `or`
- `&&` ↔ `||`
- `true` ↔ `false`
- `not x` → `x` (remove negation)

### Literal Mutator
Mutates literal values:
- Numbers: increment/decrement by 1
- Strings: empty string, append character
- Lists: mutate empty list
- Atoms: change to different atom (except special atoms like `nil`, `:ok`, `:error`)

### FunctionCall Mutator
Mutates function calls:
- Remove function call (replace with `nil`)
- Swap first two arguments
- Does not mutate special forms (def, defmodule, if, etc.)

### Conditional Mutator
Mutates conditional expressions:
- Invert `if` conditions: `if x` → `if not x`
- Remove branches: always take true/false branch
- Convert `unless` to `if`
- Remove entire `if` statement

## Testing Guidelines

- Test files are located in `test/` mirroring `lib/` structure
- Use pattern matching over `length/1` for small list assertions (see global rules)
- All mutators and language adapters should have corresponding test coverage
- Tests should be fast and isolated

## CI/CD

GitHub Actions workflow (`.github/workflows/ci.yml`) runs:
- Matrix tests across Elixir 1.14-1.16 and OTP 25-26
- Quality checks: format validation, credo, dialyzer
- Test coverage with coveralls

## Development Workflow

1. Make changes to code
2. Run `mix format` to format code
3. Run `mix test` to verify tests pass
4. Run `mix quality` to check code quality (format, credo, dialyzer)
5. Commit with comprehensive message including co-author line
6. Do NOT commit changes unless explicitly asked

## Project Configuration

- Elixir version: ~> 1.14
- Dependencies: credo, dialyxir, excoveralls, ex_doc (all dev/test/ci only)
- Dialyzer PLT: `.dialyzer/dialyzer.plt`
- Test paths: `elixirc_paths(:test)` includes `test/support`
