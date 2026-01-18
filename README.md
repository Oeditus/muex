# Muex

Mutation testing library for Elixir, Erlang, and other languages.

Muex evaluates test suite quality by introducing deliberate bugs (mutations) into code and verifying that tests catch them. It provides a language-agnostic architecture with dependency injection, making it easy to extend support to new languages.

## Features

- Language-agnostic architecture with pluggable language adapters
- Built-in support for Elixir and Erlang
- Intelligent file filtering to focus on business logic:
  - Analyzes code complexity and characteristics
  - Automatically excludes framework code (behaviours, protocols, supervisors)
  - Skips low-complexity files (Mix tasks, reporters, configurations)
  - Prioritizes files with testable logic (conditionals, arithmetic, pattern matching)
- 6 mutation strategies:
  - Arithmetic operators (+/-, *//)
  - Comparison operators (==, !=, >, <, >=, <=)
  - Boolean logic (and/or, &&/||, true/false, not)
  - Literal values (numbers, strings, lists, atoms)
  - Function calls (remove calls, swap arguments)
  - Conditionals (if/unless mutations)
- Parallel mutation execution with configurable concurrency
- Colored terminal output with mutation scores and detailed reports
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

By default, Muex intelligently filters files to focus on business logic and skip framework code. This dramatically reduces the number of mutations tested.

### File Filtering Options

```bash
# Use intelligent filtering (default)
mix muex

# Show which files are included/excluded
mix muex --verbose

# Adjust minimum complexity score (default: 20)
mix muex --min-score 30

# Disable filtering to test all files
mix muex --no-filter

# Limit total mutations tested
mix muex --max-mutations 500
```

### File Selection

```bash
# Run on specific directory
mix muex --files "lib/myapp"

# Run on specific file
mix muex --files "lib/my_module.ex"

# Run on files matching glob pattern (single level)
mix muex --files "lib/muex/*.ex"

# Run on files matching recursive glob pattern
mix muex --files "lib/**/compiler*.ex"
mix muex --files "lib/{muex,mix}/**/*.ex"
```

### Other Options

```bash
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
Found 24 file(s)
Analyzing files for mutation testing suitability...
Selected 8 file(s) for mutation testing
Skipped 16 file(s) (low complexity or framework code)
Generating mutations...
Testing 342 mutation(s)
Analyzing test dependencies...
Running tests...

Mutation Testing Results
==================================================
Total mutants: 342
Killed: 287 (caught by tests)
Survived: 55 (not caught by tests)
Invalid: 0 (compilation errors)
Timeout: 0
==================================================
Mutation Score: 83.9%
```

With `--verbose` flag:
```
Loading files from lib...
Found 24 file(s)
Analyzing files for mutation testing suitability...
  ✗ lib/mix/tasks/muex.ex (Mix task)
  ✗ lib/muex/application.ex (Application/Supervisor)
  ✓ lib/muex/compiler.ex (score: 91)
  ✓ lib/muex/runner.ex (score: 83)
  ✗ lib/muex/language.ex (Behaviour definition)
  ...
```

## Output Formats

### Terminal (Default)
Colored terminal output with progress indicators and summary:
- Green for killed mutations (tests caught the bug)
- Red for survived mutations (tests missed the bug)
- Yellow for invalid mutations (compilation errors)
- Magenta for timeouts
- Color-coded mutation score (green ≥80%, yellow ≥60%, red <60%)

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

