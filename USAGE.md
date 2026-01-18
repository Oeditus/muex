# Muex Usage Guide

Muex is a mutation testing library that helps you evaluate the quality of your test suite by introducing deliberate bugs into your code and verifying that your tests catch them.

## Table of Contents

1. [What is Mutation Testing?](#what-is-mutation-testing)
2. [Why Use Muex?](#why-use-muex)
3. [Key Features](#key-features)
4. [Getting Started](#getting-started)
5. [Basic Usage](#basic-usage)
6. [Advanced Features](#advanced-features)
7. [Mutation Strategies](#mutation-strategies)
8. [Intelligent File Filtering](#intelligent-file-filtering)
9. [Test Optimization](#test-optimization)
10. [Output Formats](#output-formats)
11. [Best Practices](#best-practices)
12. [Performance Tuning](#performance-tuning)
13. [CI/CD Integration](#cicd-integration)
14. [Troubleshooting](#troubleshooting)

## What is Mutation Testing?

Mutation testing is a technique to evaluate the effectiveness of your test suite. It works by:

1. Creating "mutants" - versions of your code with deliberate bugs
2. Running your test suite against each mutant
3. Checking if your tests catch the introduced bugs

**Key terms:**

- **Mutant**: A version of your code with a single deliberate bug
- **Killed**: A mutant caught by your tests (good!)
- **Survived**: A mutant not caught by your tests (indicates weak test coverage)
- **Invalid**: A mutant that causes compilation errors
- **Mutation Score**: Percentage of mutants killed by your tests

A high mutation score (typically 80%+) indicates that your tests are effective at catching real bugs.

## Why Use Muex?

Traditional code coverage tools (like `mix test --cover`) measure which lines of code are executed during tests, but they don't tell you if those tests actually verify the behavior of your code.

**Consider this example:**

```elixir
def calculate_discount(price, percentage) do
  price * percentage / 100  # Bug: should be price - (price * percentage / 100)
end

# Test with 100% line coverage but weak assertions
test "calculate_discount runs" do
  result = calculate_discount(100, 10)
  assert is_number(result)  # Passes but doesn't verify correctness!
end
```

This test has 100% line coverage but doesn't actually verify the discount calculation is correct. Muex would expose this by mutating the arithmetic operators and finding that the test still passes.

**Benefits of Muex:**

- **Find weak tests**: Identify tests that execute code but don't verify behavior
- **Improve test quality**: Get actionable feedback on which tests need stronger assertions
- **Increase confidence**: Know your tests actually catch bugs, not just exercise code
- **Prevent regressions**: Ensure critical business logic is thoroughly tested
- **Language-agnostic**: Works with Elixir, Erlang, and extensible to other languages

## Key Features

### 1. Language-Agnostic Architecture

Muex uses a pluggable architecture that supports multiple languages:

- **Elixir**: Full support with ExUnit integration
- **Erlang**: Native BEAM integration
- **Extensible**: Add new languages by implementing the `Muex.Language` behaviour

All mutation strategies work across all supported languages.

### 2. Comprehensive Mutation Strategies

Six built-in mutation strategies covering common bug patterns:

- **Arithmetic**: `+` ↔ `-`, `*` ↔ `/`, identity mutations
- **Comparison**: `==` ↔ `!=`, `>` ↔ `<`, boundary conditions
- **Boolean**: `and` ↔ `or`, `true` ↔ `false`, negation removal
- **Literal**: Numbers (±1), strings (empty/append), lists, atoms
- **Function Calls**: Remove calls, swap arguments
- **Conditionals**: Invert conditions, remove branches

### 3. Intelligent File Filtering

Muex automatically identifies which files contain testable business logic and skips framework boilerplate:

- **Analyzes code complexity**: Calculates scores based on conditionals, arithmetic, comparisons
- **Excludes framework code**: Behaviours, protocols, supervisors, applications
- **Skips low-value files**: Mix tasks, reporters, configuration modules
- **Prioritizes business logic**: Focuses on files with significant computational logic

This dramatically reduces mutation testing time by focusing on code that matters.

### 4. Parallel Execution

- Worker pool for concurrent mutation testing
- Configurable concurrency levels
- Efficient hot module swapping using BEAM's code reloading

### 5. Test Dependency Analysis

Muex analyzes your test suite to understand which tests cover which modules:

- **Smart test execution**: Only runs tests affected by a specific mutation
- **Faster results**: Avoids running the entire test suite for every mutation
- **Accurate coverage**: Ensures relevant tests are executed

### 6. Multiple Output Formats

- **Terminal**: Colored, interactive output for development
- **JSON**: Structured data for CI/CD integration
- **HTML**: Interactive reports for sharing with team

## Getting Started

### Installation

Add `muex` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:muex, "~> 0.1.0"}
  ]
end
```

Then install:

```bash
mix deps.get
```

### First Run

Run mutation testing on your entire project:

```bash
mix muex
```

Muex will:
1. Discover source files in `lib/`
2. Analyze and filter files (intelligent filtering enabled by default)
3. Generate mutations for each file
4. Run tests against each mutation
5. Display results with mutation score

## Basic Usage

### Run on All Files (with Intelligent Filtering)

```bash
mix muex
```

By default, Muex uses intelligent filtering to focus on business logic and skip framework code.

### Run on Specific Directory

```bash
mix muex --files "lib/myapp/core"
```

### Run on Specific File

```bash
mix muex --files "lib/my_module.ex"
```

### Run on Multiple Files with Glob Patterns

```bash
# Single directory level
mix muex --files "lib/muex/*.ex"

# Recursive patterns
mix muex --files "lib/**/calculator*.ex"

# Multiple patterns
mix muex --files "lib/{core,utils}/**/*.ex"
```

### Disable Intelligent Filtering

To test all files without filtering:

```bash
mix muex --no-filter
```

### View File Analysis Details

See which files are included/excluded and why:

```bash
mix muex --verbose
```

Output:
```
Analyzing files for mutation testing suitability...
  ✓ lib/muex/compiler.ex (score: 91)
  ✓ lib/muex/runner.ex (score: 83)
  ✗ lib/mix/tasks/muex.ex (Mix task)
  ✗ lib/muex/language.ex (Behaviour definition)
  - lib/muex/loader.ex (score: 15, below threshold)
```

## Advanced Features

### Select Specific Mutation Strategies

Run only specific mutators:

```bash
# Only arithmetic and comparison
mix muex --mutators arithmetic,comparison

# Only boolean logic
mix muex --mutators boolean

# All available mutators
mix muex --mutators arithmetic,comparison,boolean,literal,function_call,conditional
```

### Adjust Concurrency

Control parallel execution:

```bash
# Use 8 parallel workers
mix muex --concurrency 8

# Use single worker (sequential)
mix muex --concurrency 1
```

Default: Number of CPU schedulers (`System.schedulers_online()`)

### Set Test Timeout

Prevent hanging tests:

```bash
# 10 second timeout per mutation
mix muex --timeout 10000

# 30 second timeout for slow tests
mix muex --timeout 30000
```

Default: 5000ms (5 seconds)

### Enforce Minimum Mutation Score

Fail CI builds if score is too low:

```bash
# Require 80% mutation score
mix muex --fail-at 80

# Require 90% mutation score
mix muex --fail-at 90
```

This will exit with a non-zero status code if the mutation score is below the threshold, making it perfect for CI/CD pipelines.

### Adjust Complexity Threshold

Fine-tune which files to include based on complexity:

```bash
# More restrictive (only high-complexity files)
mix muex --min-score 40

# More inclusive (include lower-complexity files)
mix muex --min-score 10
```

Default: 20

Files are scored 0-100 based on:
- Number of functions
- Presence of conditionals (if, case, cond, unless)
- Arithmetic operations
- Comparison operations
- Pattern matching complexity
- Cyclomatic complexity estimate

### Limit Total Mutations

For large projects, limit the number of mutations tested:

```bash
# Test only first 500 mutations
mix muex --max-mutations 500

# Test only first 100 mutations (quick feedback)
mix muex --max-mutations 100
```

Default: 0 (unlimited)

This is useful for getting quick feedback during development or when first integrating Muex into a large project.

## Mutation Strategies

### Arithmetic Mutator

Mutates arithmetic operators to catch calculation bugs.

**Mutations:**
- `+` ↔ `-`
- `*` ↔ `/`
- `+` → `0` (remove addition)
- `-` → `0` (remove subtraction)
- `*` → `1` (identity)
- `/` → `1` (identity)

**Example:**
```elixir
# Original
def total(a, b), do: a + b

# Mutant 1: + → -
def total(a, b), do: a - b

# Mutant 2: + → 0
def total(a, b), do: 0
```

**What it catches:**
- Missing assertions on calculation results
- Tests that check only for non-nil/non-error rather than correct values

### Comparison Mutator

Mutates comparison operators to catch boundary condition bugs.

**Mutations:**
- `==` ↔ `!=`
- `>` ↔ `<`, `>` ↔ `>=`
- `<` ↔ `>`, `<` ↔ `<=`
- `>=` ↔ `<=`, `>=` ↔ `>`
- `<=` ↔ `>=`, `<=` ↔ `<`
- `===` ↔ `!==`

**Example:**
```elixir
# Original
def can_vote?(age), do: age >= 18

# Mutant 1: >= → >
def can_vote?(age), do: age > 18  # Bug: 18 can't vote

# Mutant 2: >= → <=
def can_vote?(age), do: age <= 18  # Bug: logic inverted
```

**What it catches:**
- Missing boundary condition tests (e.g., testing 19 but not 18)
- Tests that don't verify the correct comparison direction

### Boolean Mutator

Mutates boolean operators and literals to catch logic bugs.

**Mutations:**
- `and` ↔ `or`
- `&&` ↔ `||`
- `true` ↔ `false`
- `not x` → `x` (remove negation)

**Example:**
```elixir
# Original
def is_valid?(user), do: user.active and user.verified

# Mutant 1: and → or
def is_valid?(user), do: user.active or user.verified

# Mutant 2: true → false in guard
def process(x) when true, do: x
def process(x) when false, do: x  # Mutant
```

**What it catches:**
- Tests that don't verify all required conditions
- Missing tests for different boolean combinations

### Literal Mutator

Mutates literal values to catch hardcoded value dependencies.

**Mutations:**
- Numbers: increment/decrement by 1
- Strings: empty string, append character
- Lists: mutate empty list
- Atoms: change to different atom (except `:nil`, `:ok`, `:error`)

**Example:**
```elixir
# Original
def max_retries, do: 3

# Mutant 1: 3 → 4
def max_retries, do: 4

# Mutant 2: 3 → 2
def max_retries, do: 2

# Original string
def greeting, do: "Hello"

# Mutant: → empty
def greeting, do: ""
```

**What it catches:**
- Tests that don't verify specific values
- Magic number dependencies
- Missing edge case tests for special values

### FunctionCall Mutator

Mutates function calls to catch missing side-effect verification.

**Mutations:**
- Remove function call (replace with `nil`)
- Swap first two arguments

**Example:**
```elixir
# Original
def save_user(user) do
  validate_user(user)
  Repo.insert(user)
end

# Mutant 1: remove validation call
def save_user(user) do
  nil  # validation removed!
  Repo.insert(user)
end

# Original with multiple args
def send_email(to, subject, body)

# Mutant 2: swap arguments
def send_email(subject, to, body)  # to and subject swapped
```

**What it catches:**
- Tests that don't verify all necessary functions are called
- Missing argument order verification
- Side effects that aren't tested

### Conditional Mutator

Mutates conditional expressions to catch branching logic bugs.

**Mutations:**
- Invert `if` conditions: `if x` → `if not x`
- Remove branches: always take true branch or false branch
- Convert `unless` to `if`
- Remove entire `if` statement

**Example:**
```elixir
# Original
def process(user) do
  if user.admin? do
    :admin_action
  else
    :user_action
  end
end

# Mutant 1: invert condition
if not user.admin? do

# Mutant 2: always take true branch
def process(user) do
  :admin_action
end

# Mutant 3: always take false branch
def process(user) do
  :user_action
end
```

**What it catches:**
- Tests that don't verify both branches
- Missing tests for condition negation
- Tests that always pass regardless of control flow

## Intelligent File Filtering

Muex includes sophisticated file analysis to focus mutation testing on valuable code.

### Why File Filtering?

Mutation testing can be time-consuming on large codebases. Not all files benefit equally from mutation testing:

- **Framework code**: Behaviours, protocols, supervisors contain little testable logic
- **Boilerplate**: Mix tasks, reporters, configuration files
- **Low complexity**: Simple data structures, getters/setters

Muex automatically identifies and skips these files, dramatically reducing testing time.

### How It Works

Muex scores each file 0-100 based on:

**Automatic exclusions:**
- Mix tasks (CLI layer)
- Application/Supervisor modules
- Behaviour definitions
- Protocol definitions
- Reporter/Formatter modules
- Dependency code (`/deps/`)

**Complexity scoring:**
- Function count (up to 30 points)
- Conditional statements (20 points)
- Arithmetic operations (15 points)
- Comparison operations (15 points)
- Pattern matching (10 points)
- Cyclomatic complexity (up to 20 points)

Files scoring below the threshold (default: 20) are skipped.

### File Filtering Options

```bash
# Use default filtering (min score: 20)
mix muex

# More restrictive (only files with score >= 40)
mix muex --min-score 40

# More inclusive (files with score >= 10)
mix muex --min-score 10

# Disable filtering entirely
mix muex --no-filter

# See which files are included/excluded
mix muex --verbose
```

### Example Verbose Output

```bash
$ mix muex --verbose

Loading files from lib...
Found 24 file(s)
Analyzing files for mutation testing suitability...
  ✓ lib/muex/compiler.ex (score: 91)
  ✓ lib/muex/runner.ex (score: 83)
  ✓ lib/muex/mutator/arithmetic.ex (score: 67)
  ✓ lib/muex/file_analyzer.ex (score: 73)
  ✗ lib/mix/tasks/muex.ex (Mix task)
  ✗ lib/muex/application.ex (Application/Supervisor)
  ✗ lib/muex/language.ex (Behaviour definition)
  ✗ lib/muex/mutator.ex (Behaviour definition)
  - lib/muex/loader.ex (score: 15, below threshold)
  - lib/muex/reporter.ex (score: 12, below threshold)

Selected 4 file(s) for mutation testing
Skipped 20 file(s) (low complexity or framework code)
```

## Test Optimization

### Dependency-Aware Test Execution

Muex analyzes your test suite to understand dependencies between tests and source modules. This enables intelligent test execution:

**How it works:**
1. Muex scans test files for module references (imports, aliases, direct calls)
2. Builds a dependency map: module → [test_files]
3. For each mutation, runs only tests that depend on the mutated module

**Benefits:**
- **Faster execution**: Skip tests unrelated to the mutation
- **Accurate results**: Ensures relevant tests are executed
- **Better scalability**: Enables mutation testing on larger projects

**Example:**
```elixir
# lib/calculator.ex mutated
# Muex runs: test/calculator_test.exs
# Muex skips: test/user_test.exs, test/cart_test.exs
```

### Performance Characteristics

Typical mutation testing speed on modern hardware:

- **Small project** (< 1000 LOC): 30-60 seconds
- **Medium project** (1000-5000 LOC): 2-5 minutes with filtering
- **Large project** (> 5000 LOC): 5-20 minutes with filtering, 20+ without

Factors affecting speed:
- Number of mutations generated
- Test suite execution time
- Concurrency level
- File filtering effectiveness

## Output Formats

### Terminal Output (Default)

Interactive, colored output for development:

```bash
mix muex
```

**Features:**
- Green: Killed mutants (tests caught the bug)
- Red: Survived mutants (tests missed the bug)
- Yellow: Invalid mutants (compilation errors)
- Magenta: Timeouts
- Color-coded mutation score (green ≥80%, yellow ≥60%, red <60%)
- Summary statistics

**Example:**
```
Loading files from lib...
Found 24 file(s)
Analyzing files for mutation testing suitability...
Selected 8 file(s) for mutation testing
Generating mutations...
Testing 342 mutation(s)
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

Survived Mutations:
  lib/calculator.ex:15 - Arithmetic: + → - in calculate_total/2
  lib/validator.ex:42 - Comparison: >= → > in validate_age/1
  ...
```

### JSON Output

Machine-readable format for CI/CD integration:

```bash
mix muex --format json
```

Generates `muex-report.json`:

```json
{
  "summary": {
    "total": 342,
    "killed": 287,
    "survived": 55,
    "invalid": 0,
    "timeout": 0,
    "mutation_score": 83.9
  },
  "mutations": [
    {
      "file": "lib/calculator.ex",
      "line": 15,
      "mutator": "Arithmetic",
      "description": "+ → -",
      "result": "survived",
      "duration_ms": 234
    }
  ]
}
```

### HTML Output

Interactive HTML report for sharing:

```bash
mix muex --format html
```

Generates `muex-report.html` with:
- Color-coded results
- Sortable/filterable mutation list
- Per-file breakdown
- Clickable source locations
- Summary charts

## Best Practices

### 1. Start with Intelligent Filtering

When first introducing Muex to a project:

```bash
# Start with defaults
mix muex

# Review which files are tested
mix muex --verbose

# Adjust threshold if needed
mix muex --min-score 30
```

### 2. Focus on Critical Business Logic

Target mutation testing on high-value modules:

```bash
# Test core business logic
mix muex --files "lib/myapp/core"

# Test critical calculation modules
mix muex --files "lib/myapp/billing"
```

### 3. Use in Development Workflow

Integrate into your development cycle:

```bash
# After writing tests for a module
mix muex --files "lib/my_new_feature.ex"

# Check if your tests are effective
# Iterate on tests until mutation score is high
```

### 4. Set Reasonable Thresholds

For CI/CD, set achievable mutation score thresholds:

```bash
# Start conservative
mix muex --fail-at 70

# Gradually increase as test quality improves
mix muex --fail-at 80
```

Don't aim for 100% mutation score - some mutations may be:
- Equivalent mutants (semantically identical to original)
- Testing implementation details rather than behavior
- Not worth the test complexity

Target 80-90% for critical code, 70-80% for general code.

### 5. Focus on Survived Mutations

Review survived mutations to identify weak tests:

```bash
# Run with terminal output
mix muex

# Review "Survived Mutations" section
# Strengthen tests for those specific cases
```

### 6. Use Specific Mutators

For targeted test improvements:

```bash
# Testing arithmetic logic? Focus on arithmetic mutations
mix muex --files "lib/calculator.ex" --mutators arithmetic

# Testing validation logic? Focus on comparisons
mix muex --files "lib/validator.ex" --mutators comparison,boolean
```

### 7. Limit Mutations During Development

For quick feedback loops:

```bash
# Test only first 100 mutations during development
mix muex --max-mutations 100 --files "lib/my_feature.ex"

# Run full mutation testing before committing
mix muex --files "lib/my_feature.ex"
```

### 8. Document Mutation Score Goals

Add mutation score goals to your README:

```markdown
## Quality Metrics

- Code Coverage: > 90%
- Mutation Score: > 80% (core modules), > 70% (overall)
```

## Performance Tuning

### Concurrency Optimization

Find the optimal concurrency level for your system:

```bash
# Start with default (CPU schedulers)
mix muex

# Try higher concurrency
mix muex --concurrency 16

# For CPU-bound tests, use schedulers count
mix muex --concurrency $(elixir -e "IO.puts System.schedulers_online()")

# For I/O-bound tests, use higher concurrency
mix muex --concurrency 32
```

### Timeout Tuning

Adjust timeouts based on test suite speed:

```bash
# For fast test suites (< 1 second)
mix muex --timeout 2000

# For medium test suites (1-3 seconds)
mix muex --timeout 5000

# For slow test suites (> 3 seconds)
mix muex --timeout 10000
```

### Progressive Mutation Testing

For large projects, use progressive testing:

```bash
# Phase 1: Core modules only
mix muex --files "lib/myapp/core" --fail-at 80

# Phase 2: All modules with high filtering
mix muex --min-score 40 --fail-at 75

# Phase 3: All modules with default filtering
mix muex --min-score 20 --fail-at 70
```

### Caching Strategy

To speed up repeated runs:

1. Run with file filtering to reduce mutation count
2. Focus on recently changed files
3. Use `--max-mutations` to limit scope during development

## CI/CD Integration

### GitHub Actions

```yaml
name: CI

on: [push, pull_request]

jobs:
  mutation-testing:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.16'
          otp-version: '26'
      
      - name: Install dependencies
        run: mix deps.get
      
      - name: Run tests
        run: mix test
      
      - name: Run mutation testing
        run: mix muex --fail-at 80 --format json
      
      - name: Upload mutation report
        uses: actions/upload-artifact@v2
        with:
          name: mutation-report
          path: muex-report.json
```

### GitLab CI

```yaml
mutation-test:
  stage: test
  script:
    - mix deps.get
    - mix test
    - mix muex --fail-at 80 --format json
  artifacts:
    paths:
      - muex-report.json
    expire_in: 1 week
```

### CI Best Practices

1. **Set reasonable thresholds**: Start with `--fail-at 70`, increase gradually
2. **Use intelligent filtering**: Speeds up CI runs significantly
3. **Generate JSON reports**: Enable trend analysis over time
4. **Run on pull requests**: Catch test quality issues before merge
5. **Store HTML reports**: Make results accessible to team

### Incremental Mutation Testing

For faster CI feedback, test only changed files:

```bash
# Get changed files
CHANGED_FILES=$(git diff --name-only origin/main...HEAD | grep '^lib/.*\.ex$' | tr '\n' ',')

# Run mutation testing on changed files only
if [ -n "$CHANGED_FILES" ]; then
  mix muex --files "$CHANGED_FILES" --fail-at 80
fi
```

## Troubleshooting

### High Number of Survived Mutations

**Problem**: Mutation score is low (< 70%)

**Solutions**:
1. Review survived mutations list in output
2. Add assertions for specific values, not just types
3. Test boundary conditions
4. Verify both success and failure cases
5. Test all branches of conditionals

**Example improvement**:
```elixir
# Weak test
test "calculate_discount works" do
  result = calculate_discount(100, 10)
  assert is_number(result)  # Will survive arithmetic mutations
end

# Strong test
test "calculate_discount applies 10% discount" do
  result = calculate_discount(100, 10)
  assert result == 90.0  # Will kill arithmetic mutations
end
```

### Mutation Testing Takes Too Long

**Problem**: Mutation testing takes > 30 minutes

**Solutions**:
1. Enable intelligent filtering: `mix muex` (default)
2. Increase minimum score: `--min-score 40`
3. Limit mutations: `--max-mutations 500`
4. Test specific directories: `--files "lib/core"`
5. Increase concurrency: `--concurrency 16`
6. Optimize test suite performance (faster tests = faster mutation testing)

### Timeouts

**Problem**: Many mutations result in timeout

**Solutions**:
1. Increase timeout: `--timeout 10000`
2. Check for infinite loops in code
3. Optimize slow tests
4. Review mutations that timeout - may indicate code issues

### Invalid Mutations

**Problem**: High number of invalid mutations (compilation errors)

**Causes**:
- Mutations creating syntactically invalid code
- Type system constraints violated
- Usually not a problem (invalid mutations are excluded from score)

**If invalid rate is > 20%**:
- Disable specific mutators causing issues
- Report issue with code example

### False Positives

**Problem**: Mutation survived but test should have caught it

**Causes**:
- **Equivalent mutants**: Mutation is semantically identical to original
  - Example: `x + 0` → `x` (no change in behavior)
- **Implementation detail**: Test intentionally doesn't cover this behavior

**Solutions**:
- Accept some survived mutations (80-90% score is excellent)
- Add test only if behavior is important
- Document why mutation can be ignored

### Memory Issues

**Problem**: Out of memory errors

**Solutions**:
1. Reduce concurrency: `--concurrency 2`
2. Limit mutations: `--max-mutations 200`
3. Test smaller file sets: `--files "lib/specific_module.ex"`
4. Increase system swap space

## Examples

See the `examples/` directory for complete working examples:

### Calculator Example

Simple Elixir calculator demonstrating basic mutation testing:

```bash
cd examples/calculator
mix deps.get
mix muex
```

**Demonstrates**:
- Arithmetic mutation testing
- Test effectiveness evaluation
- Basic ExUnit integration

### Real-World Usage

Check Muex's own mutation testing:

```bash
# Run mutation testing on Muex itself
mix muex --files "lib/muex/compiler.ex"

# See comprehensive usage
mix muex --verbose
```

## Summary

Muex helps you build robust test suites by:

- **Validating test quality**: Ensures tests actually catch bugs
- **Providing actionable feedback**: Shows exactly which tests are weak
- **Supporting multiple languages**: Works with Elixir and Erlang
- **Optimizing performance**: Intelligent filtering and parallel execution
- **Integrating with CI/CD**: Multiple output formats and fail thresholds

Start with `mix muex` and let intelligent filtering guide you to better tests!
