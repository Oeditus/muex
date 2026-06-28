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
- Sophisticated mutation optimization heuristics (50-70% reduction)
- Colored terminal output with mutation scores and detailed reports
- Integration with ExUnit
- Hot module swapping for efficient testing

## Installation

Muex can be used in three ways:

### 1. As a Mix Dependency (Recommended for CI/CD)

Add `muex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:muex, "~> 0.8", only: [:dev, :test], runtime: false}
  ]
end
```

Then run:

```bash
mix deps.get
mix muex
```

### 2. As a Hex Archive (Recommended for Global Use)

Install globally to use across all your projects:

```bash
mix archive.install hex muex
```

This makes `mix muex` available in any Elixir project without adding it as a dependency.

### 3. As an Escript (Standalone Binary)

For standalone usage or distribution:

```bash
# From muex repository
mix escript.build

# Install system-wide
sudo cp muex /usr/local/bin/

# Use in any project
cd /path/to/your/project
muex
```

For detailed installation instructions and comparison, see [docs/INSTALLATION.md](docs/INSTALLATION.md).

## Usage

Run mutation testing on your project:

```bash
# Using mix task (dependency or hex archive)
mix muex

# Using escript (standalone binary)
muex
```

Both commands accept the same options and produce identical results.

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

# Enable mutation optimization (balanced preset)
mix muex --optimize

# Use conservative optimization (best balance)
mix muex --optimize --optimize-level conservative

# Use aggressive optimization (fastest)
mix muex --optimize --optimize-level aggressive

# Custom optimization settings
mix muex --optimize --min-complexity 3 --max-per-function 15

# Reduce invalid/noisy mutations on framework-heavy projects
mix muex --preset phoenix   # also: ecto, ash

# Only mutate lines changed since a branch/ref (pull-request scoping)
mix muex --since main

# Run only the tests that cover each mutated line
mix muex --coverage-guided

# Disable Trivial Compiler Equivalence (equivalent-mutant skipping)
mix muex --no-tce
```

## Mutation Optimization

Muex includes sophisticated heuristics to reduce the number of mutants tested while maintaining mutation testing effectiveness. This can reduce testing time by 50-70% with minimal impact on mutation score.

### When to Use Optimization

- **CI/CD pipelines**: Use conservative mode for fast feedback with <1% score impact
- **Development iteration**: Use balanced mode for rapid checks
- **Pre-release validation**: Disable optimization for complete coverage

### Optimization Levels

**Conservative** (recommended for CI/CD):
- 50-65% reduction in mutations
- <1% impact on mutation score
- Focuses on high-complexity code
- Preserves boundary condition mutations

```bash
mix muex --optimize --optimize-level conservative
```

**Balanced** (default, good for development):
- 70-85% reduction in mutations
- 5-10% impact on mutation score
- Fast feedback during development
- Focuses on highest-impact mutations

```bash
mix muex --optimize
```

**Aggressive** (rapid checks only):
- 85-95% reduction in mutations
- 10-15% impact on mutation score
- Very fast but may miss edge cases

```bash
mix muex --optimize --optimize-level aggressive
```

### How It Works

The optimizer uses 7 strategies:

1. **Equivalent Mutant Detection**: Filters semantically equivalent mutations
2. **Code Complexity Scoring**: Skips mutations in trivial code (getters, simple guards)
3. **Impact Scoring**: Prioritizes mutations by risk level (1-11 points)
4. **Mutation Clustering**: Groups similar mutations and samples representatives
5. **Per-Function Limits**: Caps mutations per function to prevent explosion
6. **Boundary Prioritization**: Always preserves critical comparison mutations
7. **Pattern-Based Filtering**: Removes known low-value mutations

For detailed information, see [docs/MUTATION_OPTIMIZATION.md](docs/MUTATION_OPTIMIZATION.md).

### Example: Cart Project

Real-world results from the shopping cart example (440 LOC, 84 tests):

| Mode | Mutations | Time | Score | Best For |
|------|-----------|------|-------|----------|
| Baseline | 886 | ~3 min | 99.77% | Final validation |
| Conservative | 308 | ~1 min | 99.35% | CI/CD |
| Balanced | 28 | ~10 sec | 89.29% | Development |

See `examples/cart/OPTIMIZATION_RESULTS.md` for complete analysis.

## Equivalent Mutants, Coverage, and Incremental Runs

In addition to the (lossy) optimizer above, Muex applies sound, always-on
handling that never hides a killable mutant:

- **Equivalent-mutant detection**: AST identity rules (`a + 0` vs `a - 0`,
  `a * 1` vs `a / 1`, bitshift-by-zero) drop mutations that cannot change
  behaviour. They are reported as `Equivalent` and excluded from the score.
- **Trivial Compiler Equivalence (TCE)**: mutants that compile to byte-identical
  BEAM (for example, deleting a `@moduledoc`) are skipped. Disable with
  `--no-tce`.
- **Coverage-guided execution** (`--coverage-guided`): runs only the tests that
  execute the mutated line; a line that no test covers is reported as
  `No coverage` and skipped instead of wasting a full test run.
- **Incremental `--since <ref>`**: scopes mutation testing to the lines changed
  since a git ref (`git diff <ref>...HEAD`), which is ideal for pull-request CI:

```bash
mix muex --since main
```

## Compile-Time Configuration

Custom language adapters and mutators can be registered in your `config/config.exs` so they are available via the CLI flags:

```elixir
# config/config.exs
import Config

# Register a custom language adapter (usable with --language lua)
config :muex, languages: %{"lua" => MyApp.Language.Lua}

# Register custom mutators (usable with --mutators string,regex)
config :muex, mutators: %{
  "string" => MyApp.Mutator.String,
  "regex"  => MyApp.Mutator.Regex
}
```

Language adapter modules must implement the `Muex.Language` behaviour and mutator modules must implement the `Muex.Mutator` behaviour. Custom entries are merged with the built-in ones at compile time; entries with the same key override the built-in default.

## Available Mutators

Muex provides 18 mutation strategies. Core operators work across BEAM languages;
Elixir-specific operators target Elixir AST constructs.

Core:

- **Arithmetic**: Mutates `+`, `-`, `*`, `/` operators (swap, remove, identity)
- **Comparison**: Mutates `==`, `!=`, `>`, `<`, `>=`, `<=`, `===`, `!==` operators
- **Boolean**: Mutates `and`, `or`, `&&`, `||`, `true`, `false`, `not` (swap, negate, remove)
- **Literal**: Mutates numbers (±1), strings (empty/append), lists (empty), atoms (change)
- **FunctionCall**: Removes function calls and swaps first two arguments
- **Conditional**: Inverts conditions, removes branches, converts `unless` to `if`
- **ReturnValue**: Replaces a function or block return value
- **StatementDeletion**: Deletes individual statements from blocks

Elixir-specific:

- **Pipe**: Drops a stage from a pipe chain (`x |> f` becomes `x`)
- **Guard**: Removes a `when` guard by replacing it with `true`
- **CaseClause** / **CondClause** / **WithClause**: Delete a clause from `case` / `cond` / `with`
- **MapSemantics**: Mutates map operations
- **EnumSemantics**: Mutates `Enum` operations
- **ExtendedMath**: Mutates `rem`, `div`, and bitwise operators
- **InvertNegatives**: Drops unary negation (`-x` becomes `x`)
- **NegateConditionals**: Swaps relational operators for their complements

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
- **`examples/cart/`** - Real-world e-commerce shopping cart (recommended)
  - 440 LOC with complex business logic
  - 84 comprehensive tests
  - 99.77% baseline mutation score
  - Demonstrates optimization heuristics
  - See [examples/cart/README.md](examples/cart/README.md)
- `examples/shop/` - Simpler shopping cart example (48 tests)
- `examples/calculator.erl` - Basic Erlang example

**Note**: The examples demonstrate the mutation testing concept. For production use, consider integrating Muex into your project's mix.exs as a dependency.

## Documentation

Documentation can be found at <https://hexdocs.pm/muex>.
