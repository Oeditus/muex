# Elixir Mutation Testing Libraries: Muex vs Darwin vs Exavier

A comprehensive comparison of the three Elixir mutation testing libraries.

## Executive Summary

Muex, Darwin, and Exavier are all mutation testing tools for the BEAM ecosystem. They share the same core idea -- introduce deliberate bugs into code and verify that tests catch them -- but differ significantly in architecture, maturity, feature breadth, and maintenance status. Darwin and Exavier were both created in 2019 and have been unmaintained since late 2020. Muex is actively developed (2026) and represents a generational leap in features and design.

## Project Vitals

### Muex
- **Version**: 0.5.0 (March 2026, 8 published releases)
- **Elixir requirement**: ~> 1.14
- **License**: MIT
- **Hex downloads**: 304 all-time
- **GitHub stars**: New project
- **Maintainer**: Aleksei Matiushkin (mudasobwa)
- **Last activity**: March 2026 (actively maintained)
- **Dependencies**: jason ~> 1.4 (runtime), plus dev/test tooling (credo, dialyxir, excoveralls, ex_doc)
- **LOC (lib)**: ~3,900
- **LOC (tests)**: ~2,300 (204 passing tests)
- **CI**: GitHub Actions with matrix (Elixir 1.14-1.16, OTP 25-26)

### Darwin
- **Version**: 0.1.0 (only version ever published)
- **Elixir requirement**: ~> 1.7
- **License**: Not specified
- **Hex downloads**: Listed on Hex but minimal
- **GitHub stars**: 12
- **Maintainer**: tmbb (sole contributor)
- **Last activity**: December 2020 (abandoned)
- **Dependencies**: parse_trans ~> 3.3, makeup_elixir ~> 0.14, plus benchee, stream_data, ex_doc (dev)
- **LOC (lib)**: ~15,000+ (estimated from file count and sizes)
- **CI**: None

### Exavier
- **Version**: 0.3.0 (November 2020, 8 releases)
- **Elixir requirement**: ~> 1.7
- **License**: MIT
- **Hex downloads**: 2,243 all-time (most popular of the three)
- **GitHub stars**: 101
- **Maintainers**: 4 contributors (dnlserrano, Cantido, KingOfRostov, tank-bohr)
- **Last activity**: November 2020 (abandoned)
- **Dependencies**: None (runtime), ex_doc ~> 0.23 (dev only)
- **LOC (lib)**: ~1,500 (estimated)
- **CI**: Travis CI

## Architecture

### Muex: Plugin-Based, Language-Agnostic
Muex uses a behaviour-based plugin architecture with clear separation:

1. **`Muex.Language` behaviour** -- Defines interface for language adapters (`parse/1`, `unparse/1`, `compile/2`, `file_extensions/0`, `test_file_pattern/0`)
2. **`Muex.Mutator` behaviour** -- Defines interface for mutation strategies (`mutate/2`, `name/0`, `description/0`)
3. **`Muex.Loader`** -- File discovery with glob patterns
4. **`Muex.Compiler`** -- AST mutation application and hot-swapping
5. **`Muex.Runner`** -- Test execution via port-based isolation
6. **`Muex.WorkerPool`** -- GenServer-based parallel execution
7. **`Muex.FileAnalyzer`** -- Intelligent file filtering via code analysis
8. **`Muex.MutantOptimizer`** -- 7-strategy mutation reduction heuristics
9. **`Muex.DependencyAnalyzer`** -- Test dependency graph for targeted execution
10. **`Muex.Reporter`** / **`Muex.Reporter.Html`** / **`Muex.Reporter.Json`** -- Multi-format reporting
11. **`Muex.Config`** -- Centralized configuration with CLI parsing
12. **`Muex.CLI`** -- Escript entry point

Key design: mutations happen at the Elixir AST level, language adapters provide parse/unparse/compile, and test execution runs in isolated port processes (separate BEAM VM per mutation).

### Darwin: Erlang Abstract Code Approach
Darwin takes a fundamentally different approach -- it works at the Erlang abstract code level:

1. Converts Elixir source to Erlang abstract forms via Elixir-to-Erlang transpilation
2. Applies mutations at the Erlang abstract code level
3. Uses a "codon" model inspired by genetics -- mutation points are named codons
4. Uses process dictionary for thread-local mutation activation (`Darwin.ActiveMutation`)
5. Injects runtime dispatch: mutated code contains `darwin_was_here/N` calls that branch on the active mutation at runtime
6. Re-runs ExUnit for each mutation using `Darwin.TestCase` to short-circuit after first failure

This approach means Darwin does not re-compile per mutation -- it compiles once with all mutation points embedded, then activates them one at a time via the process dictionary. This is architecturally clever but comes with its own trade-offs (code bloat from injected dispatchers, mandatory test modification).

### Exavier: Direct AST Rewriting
Exavier uses the simplest approach:

1. Runs code coverage analysis to determine which lines to mutate
2. For each module (in parallel), for each mutator (sequentially):
   - Rewrites the quoted AST using `Code.compile_quoted/2`
   - Re-requires the test file
   - Runs ExUnit
3. Uses `Code.compile_quoted/2` with `ignore_module_conflict: true` for hot-swap
4. GenServer-based reporter tracks results

The architecture is straightforward but tightly coupled to ExUnit internals and lacks isolation between mutations.

## Language Support

### Muex
- **Elixir**: Full support via `Muex.Language.Elixir` adapter
- **Erlang**: Full support via `Muex.Language.Erlang` adapter (uses `:erl_scan`, `:erl_parse`, `:erl_prettypr`, `:compile`)
- **Extensible**: Any BEAM language can be supported by implementing the `Muex.Language` behaviour (5 callbacks)
- **Custom adapters**: Registerable via `config :muex, languages: %{"lua" => MyApp.Language.Lua}` at compile time

### Darwin
- **Elixir only** (despite working through Erlang abstract code internally)
- No formal language adapter system
- Erlang abstract code is an internal implementation detail, not an extensibility point

### Exavier
- **Elixir only**
- No language adapter system
- Tightly coupled to Elixir AST and ExUnit

## Mutation Strategies

### Muex (6 strategies, 30+ individual mutations)

| Mutator | Mutations |
|---------|-----------|
| **Arithmetic** | `+` <-> `-`, `*` <-> `/`, `+` -> `0`, `-` -> `0`, `*` -> `1`, `/` -> `1` |
| **Comparison** | `==` <-> `!=`, `>` <-> `<`, `>` <-> `>=`, `<` <-> `<=`, `>=` <-> `<=`, `===` <-> `!==` |
| **Boolean** | `and` <-> `or`, `&&` <-> `\|\|`, `true` <-> `false`, `not x` -> `x` |
| **Literal** | numbers +/-1, strings empty/append, empty list -> `[:mutated]`, atoms -> `:mutated_atom` |
| **FunctionCall** | Remove calls (replace with `nil`), swap first two arguments |
| **Conditional** | Invert `if` condition, always-true/always-false branches, `unless` -> `if`, remove `if` |

All mutators are selectable via CLI (`--mutators arithmetic,comparison`). Custom mutators registerable via compile-time config.

### Darwin (AOR/ROR + operator mutations)
Darwin uses pitest-inspired naming (AOR = Arithmetic Operator Replacement, ROR = Relational Operator Replacement) and implements mutations via Erlang abstract code transformations. The mutation approach embeds all possible mutations into the code at compile time and selects them at runtime. Specific mutators include:

- Arithmetic operator replacement (+, -, *, /)
- Relational operator replacement (==, /=, <, >, >=, =<)
- Guard rewriting for mutated guards

Darwin's mutator system is based on a `@callback mutate/2` that transforms Erlang abstract code forms. Mutators are registered in a default list. The codon-based system means each mutation point gets a unique index.

### Exavier (13 mutators)

| Mutator | Based On |
|---------|----------|
| **AOR1-AOR4** | Arithmetic operator replacement (pitest-style) |
| **ROR1-ROR5** | Relational operator replacement (pitest-style) |
| **IfTrue** | Replace `if` condition with `true` |
| **NegateConditionals** | Negate conditional operators |
| **ConditionalsBoundary** | Change boundary conditions (> to >=, etc.) |
| **InvertNegatives** | Remove unary minus |

Custom mutators supported via `.exavier.exs` config file. No boolean mutators, no literal mutators, no function call mutators.

### Summary

- **Muex**: Broadest mutation coverage. Unique strategies: literal mutation, function call removal/arg swapping, conditional branch removal. Named descriptively (not pitest codes).
- **Darwin**: Erlang-level mutations with codon-indexed dispatch. Architecturally novel but harder to reason about.
- **Exavier**: pitest-faithful naming, decent arithmetic/relational coverage, but missing boolean, literal, function call, and advanced conditional mutations.

## Test Execution Model

### Muex: Port-Based Isolation
- Each mutation is tested in a **separate BEAM VM** spawned via Erlang ports
- The worker pool writes the mutated source to the original file, deletes the `.beam` cache, runs `mix test` in a subprocess, then restores the original
- Complete process isolation prevents any mutation side-effects from leaking
- Supports incremental compilation (only the mutated module is recompiled)
- Configurable concurrency via `--concurrency` flag and `Muex.WorkerPool` GenServer
- Configurable timeout per mutation (`--timeout`)
- Test dependency analysis selects only relevant test files per mutation

### Darwin: In-Process Runtime Dispatch
- Code is compiled once with all mutations embedded as runtime branches
- Active mutation is selected via process dictionary (`Darwin.ActiveMutation`)
- ExUnit runs within the same BEAM VM
- `Darwin.TestCase` overrides `test/2` and `test/3` macros to short-circuit after first failure
- Pro: No re-compilation overhead per mutation (fastest possible switching)
- Con: Requires modifying test files (`use Darwin.TestCase`), modifying `test_helper.exs`, and listing modules in `mix.exs`

### Exavier: In-Process Hot-Swap
- Uses `Code.compile_quoted/2` with `ignore_module_conflict: true`
- Re-requires test files and calls `ExUnit.run()` per mutation
- Parallel per module via `Task.async_stream`
- Sequential per mutator within each module
- No process isolation -- mutations share the same VM
- Coverage analysis as a pre-processing step to identify lines to mutate

## Configuration and CLI

### Muex
Muex offers the richest CLI and configuration:

- **Entry points**: `mix muex` (Mix task), `muex` (escript binary), `mix archive.install hex muex` (global archive)
- **File selection**: `--files` with directory, file, or glob patterns (`**/*.ex`, `{a,b}/**/*.ex`)
- **Umbrella support**: `--app my_app` automatically sets `--files` and `--test-paths`
- **Test paths**: `--test-paths "test/unit,test/integration"` with glob expansion
- **Output formats**: `--format terminal|json|html`
- **Score threshold**: `--fail-at 80` (CI/CD integration)
- **Filtering**: `--no-filter`, `--min-score`, `--max-mutations`
- **Optimization**: `--optimize`, `--optimize-level conservative|balanced|aggressive`, `--min-complexity`, `--max-per-function`
- **Compile-time config**: Register custom language adapters and mutators in `config/config.exs`
- **Centralized config struct**: `%Muex.Config{}` with typed fields and validation

### Darwin
- Modules to mutate listed in `mix.exs` under the `:darwin` key
- No CLI flags documented
- Requires modifying `test_helper.exs` and all test modules
- No filtering, no optimization, no output format selection
- HTML reporter outputs to `darwin/reports/html/`

### Exavier
- Run via `mix exavier.test`
- Configuration via `.exavier.exs` dotfile:
  - `:threshold` -- mutation coverage threshold (default: 67%)
  - `:test_files_to_modules` -- custom test-to-module mapping
  - `:custom_mutators` -- additional mutator modules
- No CLI flags for file selection, mutator selection, or concurrency

## Intelligent Features

### Muex (Unique)

**File Analyzer** (`Muex.FileAnalyzer`):
- Scores files 0-100 based on code characteristics
- Automatically excludes: Mix tasks, supervisors, application modules, behaviour definitions, protocols, reporters, dependency code
- Scores based on: function count, conditionals, arithmetic, comparisons, pattern matching, cyclomatic complexity
- Configurable minimum score threshold (`--min-score`)

**Mutation Optimizer** (`Muex.MutantOptimizer`):
- 7 optimization strategies: equivalent mutant detection, impact scoring, complexity filtering, mutation clustering, per-function limits, boundary prioritization, pattern-based filtering
- 3 presets: conservative (50-65% reduction, <1% score impact), balanced (70-85% reduction), aggressive (85-95% reduction)
- Benchmark on Calculator project (76 LOC, 20 tests): 85 mutations reduced to 31 (63.5% reduction), score preserved at 100%

**Test Dependency Analysis** (`Muex.DependencyAnalyzer`):
- Parses test files to extract module references (aliases, imports, function calls, describe/test strings)
- Runs only tests that depend on the mutated module
- Falls back to full test suite when no dependencies found

### Darwin
- Fast-fail: stops test suite after first failure per mutation (via `Darwin.TestCase`)
- Debug output: writes mutated Erlang and Elixir source to `_darwin_debug/`

### Exavier
- Code coverage pre-processing: only mutates lines that are covered by tests
- Threshold-based pass/fail (default 67%)

## Reporting

### Muex
- **Terminal**: Color-coded output (ANSI), progress dots, categorized summary (killed/survived/invalid/timeout), survived mutation details with file:line
- **JSON**: Structured JSON with full mutation details, CI/CD friendly (stdout, or a file with `--output`)
- **HTML**: Interactive report with filter buttons, summary cards, color-coded mutations, responsive design (`muex-report.html`)

### Darwin
- Console logging: green (killed), red (survived)
- HTML reporter: outputs to `darwin/reports/html/` (described as "under heavy development")

### Exavier
- Console only: dots for progress (green = killed, red = survived)
- Diff-style output showing original vs. mutated code for survived mutations
- Summary line with percentages

## Benchmark: Calculator Project

Test subject: `Calculator` module (76 LOC, 4 functions: add, subtract, multiply, divide with guards and error handling). 20 ExUnit tests.

### Muex Results

**Without optimization** (`--no-optimize --no-filter`):
- Mutations generated: 85
- Killed: 85 (100%)
- Survived: 0
- Invalid: 0
- Wall time: ~10.8s

**With conservative optimization** (`--optimize --optimize-level conservative`):
- Mutations generated: 85 -> 31 after optimization (63.5% reduction)
- Killed: 31 (100%)
- Survived: 0
- Wall time: ~4.2s (61% faster)

### Darwin / Exavier
Both Darwin and Exavier have been abandoned since 2020 and require Elixir ~> 1.7. They cannot be installed in a modern Elixir 1.17+ project without dependency conflicts. Darwin's `parse_trans` dependency and Exavier's compilation model are incompatible with current Elixir/OTP releases. Therefore, direct benchmark comparison on the same codebase is not feasible.

Historical context: Exavier's README shows an example of 22 tests producing 27.27% mutation coverage on a simple hello-world module, with no timing data provided. Darwin provides no benchmark data.

## Code Quality and Testing

### Muex
- 204 passing tests covering all major components
- Test coverage for: Config, DependencyAnalyzer, Loader, all 6 mutators, Reporter, JSON Reporter, TestRunner.Port, WorkerPool, Language.Elixir, integration tests
- Quality pipeline: `mix quality` runs formatter + credo --strict + dialyzer
- CI matrix: Elixir 1.14-1.16, OTP 25-26
- Typespecs on all public functions
- `@moduledoc` and `@doc` on all modules and public functions
- Documentation published on HexDocs with guides (Installation, Usage, Mutation Optimization)

### Darwin
- Tests present but minimal (uses `stream_data` for property-based testing of mutators)
- No CI pipeline
- No typespecs visible in main modules
- Documentation incomplete (many `TODO: document this` comments)

### Exavier
- Self-described as "proof-of-concept" with a lengthy "To be done" list
- Has tests but author admits they need "way more tests (OMG the irony)"
- Travis CI (now defunct service)
- Minimal typespecs
- Published on HexDocs

## Extensibility

### Muex
- **Language adapters**: Implement `Muex.Language` behaviour (5 callbacks), register via config
- **Mutators**: Implement `Muex.Mutator` behaviour (3 callbacks), register via config
- **Compile-time registration**: `config :muex, languages: %{...}, mutators: %{...}`
- **Programmatic API**: `Muex.run(%Muex.Config{})` returns `{:ok, %{results: [...], score: float}}`
- **Three installation modes**: Mix dependency, hex archive (global), escript binary
- **Umbrella support**: `--app` flag for targeting specific apps

### Darwin
- Mutators implement `Darwin.Mutator` callback, registered in default list
- No compile-time or runtime registration mechanism for end users
- No programmatic API
- Mix dependency only

### Exavier
- Custom mutators via `Exavier.Mutators.Mutator` behaviour (2 callbacks)
- Registration via `.exavier.exs` config file
- No programmatic API
- Mix dependency only

## Integration and Deployment

### Muex
- CI/CD: JSON output format for machine consumption, `--fail-at` for threshold gates
- Three distribution modes: dependency, archive, escript
- Umbrella-aware with `--app` flag
- Custom test path selection for monorepo/polyrepo setups

### Darwin
- Requires invasive changes to project (modify `mix.exs`, `test_helper.exs`, all test files)
- HTML report generation
- No CI/CD integration features

### Exavier
- Threshold-based exit code (pass/fail)
- No JSON/HTML output
- No CI/CD-specific features

## Known Limitations

### Muex
- Port-based execution adds overhead per mutation (~100-200ms per test run vs in-process)
- File-system based mutation (writes to source files temporarily, though with backup/restore)
- Young project with growing download base

### Darwin
- Requires modifying all test files with `use Darwin.TestCase`
- Requires modifying `test_helper.exs`
- Requires listing all modules to mutate in `mix.exs`
- Single contributor, abandoned since December 2020
- Erlang abstract code approach means mutations may not perfectly map to Elixir source
- No license specified

### Exavier
- Self-described proof-of-concept
- Cannot tune which mutators are used (planned but unimplemented)
- No parallel mutation within a module
- Relies on `ignore_module_conflict: true` with no isolation
- Hardcoded test file discovery (`test/**/*_test.exs`)
- Abandoned since November 2020
- No fast-fail mechanism (planned but unimplemented)

## Feature Matrix

| Feature | Muex | Darwin | Exavier |
|---------|------|--------|---------|
| **Status** | Active (2026) | Abandoned (2020) | Abandoned (2020) |
| **Elixir support** | Yes | Yes | Yes |
| **Erlang support** | Yes | No | No |
| **Custom language adapters** | Yes (behaviour) | No | No |
| **Arithmetic mutations** | Yes (6) | Yes | Yes (AOR1-4) |
| **Comparison mutations** | Yes (12) | Yes | Yes (ROR1-5) |
| **Boolean mutations** | Yes (7) | No | No |
| **Literal mutations** | Yes (8) | No | No |
| **Function call mutations** | Yes (2) | No | No |
| **Conditional mutations** | Yes (8) | No | Yes (3) |
| **Custom mutators** | Yes (compile-time config) | Yes (code-level) | Yes (.exavier.exs) |
| **Mutator selection** | CLI flag | No | No (planned) |
| **Process isolation** | Port (separate VM) | In-process (pdict) | In-process (hot-swap) |
| **Parallel execution** | GenServer worker pool | No | Per-module |
| **Configurable concurrency** | Yes (--concurrency) | No | No |
| **Intelligent file filtering** | Yes (FileAnalyzer) | No | No |
| **Mutation optimization** | Yes (7 strategies, 3 presets) | No | No |
| **Test dependency analysis** | Yes | No | No |
| **Coverage-based filtering** | Via FileAnalyzer | No | Yes (pre-processing) |
| **Umbrella support** | Yes (--app flag) | No | No |
| **Custom test paths** | Yes (--test-paths) | No | No |
| **Terminal output** | Color-coded, progress dots | Color-coded | Color-coded, diffs |
| **JSON output** | Yes | No | No |
| **HTML output** | Yes (interactive) | Yes (basic) | No |
| **Score threshold** | Yes (--fail-at) | No | Yes (threshold in config) |
| **Mix task** | Yes (mix muex) | No (programmatic) | Yes (mix exavier.test) |
| **Escript** | Yes | No | No |
| **Hex archive install** | Yes | No | No |
| **Programmatic API** | Yes (Muex.run/1) | Yes (Mutator.mutate_compile_and_load_module/1) | No |
| **Documentation** | HexDocs + guides | HexDocs (incomplete) | HexDocs |
| **Typespecs** | Comprehensive | Partial | Minimal |
| **Test suite** | 204 tests | Minimal | Minimal |
| **CI/CD** | GitHub Actions matrix | None | Travis CI (defunct) |

## Verdict

**Muex** is the only actively maintained option and offers by far the most complete feature set. Its language-agnostic architecture, intelligent file filtering, mutation optimization, test dependency analysis, multiple output formats, and umbrella support make it suitable for production CI/CD pipelines. The trade-off is port-based execution overhead, which the optimizer mitigates effectively (63.5% mutation reduction with no score impact on the calculator benchmark).

**Darwin** introduced an innovative compile-once-dispatch-at-runtime approach that eliminates per-mutation compilation overhead. This is architecturally interesting but comes at the cost of invasive project modifications and an Erlang-abstract-code complexity that makes the codebase harder to extend. It has been abandoned for over 5 years.

**Exavier** is the most well-known of the three (101 stars, 2,243 downloads) and pioneered Elixir mutation testing with a clean, simple design. However, the author explicitly described it as a proof-of-concept, and several planned features were never implemented. It has been abandoned for over 5 years.

For any new project considering mutation testing in 2026, **Muex is the clear choice** -- it is the only option that works with modern Elixir/OTP, is actively maintained, and provides the tooling depth needed for real-world adoption.
