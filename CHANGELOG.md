# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **`--output <file>`**: Writes the `json` or `html` report to the given file and prints a one-line summary in place of the report. Requires `--format json` or `--format html`. The path is checked before any mutant runs. Without it, `json` still prints to stdout and `html` still writes `muex-report.html`.
- **Test Files**: Each result records the test files `mix test` was given for the mutant (`test_files` in the JSON report, "Test files" in the HTML report and under each survivor in the terminal). For a survivor these are the tests that ran and still passed.

### Fixed
- **`--since` in a Subdirectory**: For a project that is not at the top of its git repository, such as an umbrella inside a monorepo, `--since` matched no files and generated no mutations. The diff now names files from the project root, and relative and absolute `--files` paths both match.
- **Unknown Format**: `--format` is validated with the other options, so an unknown format is refused before the run instead of after it.
- **HTML Write Errors**: A failed write of `muex-report.html` is reported as an error instead of being logged as generated.
- **Docs**: README and USAGE said `--format json` writes `muex-report.json`; it prints to stdout. The CI examples now pass `--output muex-report.json`, so the artifact they upload exists.
- **Tests That Never Ran**: When every test chosen for a mutant was excluded, skipped or invalid, `mix test` exited 0 with `Result: 0 tests` (or `N tests, 0 failures, N excluded` before Elixir 1.20) and the mutant was scored survived. It is now `:no_coverage`, with the summary in its `error`, and the terminal says the chosen tests ran none. The umbrella baseline refuses the run when its tests ran none, instead of reporting green.
- **Failures Missed in the Summary**: Before Elixir 1.20 only the first `N tests, M failures` line was read, so in an umbrella a failure in any app after the first was scored survived. A `setup_all` crash, which counts its tests as invalid rather than failed and exits non-zero, was also scored survived. Failures are now summed over every summary, a non-zero exit with no failure counted is a kill, and ANSI colours are removed before the summary is read.
- **Uncompiled Mutants Scored Killed**: Mix treats a file as unchanged when its size and its mtime (whole seconds) match the last compile, so a mutant the same size as the one before it, written within the same second, was never compiled. Its module was missing, every test failed, and the mutant was scored killed without being tested. Each mutant is now padded with trailing newlines to a size no compile has seen; no code or line number changes.
- **Worker Crashes**: An exception or exit inside muex while running a mutant was recorded as `:timeout`, which the high bound of the score counts as killed. It is now `:invalid`, with the error in the report.
- **Equivalent Mutants**: Mutants `Muex.Equivalence` judges equivalent were dropped before the run and appeared in no report, although the README says they are reported. They are now results with status `:equivalent`, shown in every report and still left out of the score. The JSON summary now counts `equivalent` and `no_coverage`, and its `total` now includes equivalent mutants. The HTML report has cards and filters for both. A run that has only equivalent mutants left reports them and exits as a run with no mutants did before.
- **Broken Runs Scored as Invalid Mutants**: `mix test` compiles the whole project, so a mutant was scored `:invalid` for a compile error in any file, including one it never touched: a dependency edited during the run, a sibling app, a test file. Every later mutant then came back invalid too, and the score, which leaves invalid mutants out, looked healthy. When a mutant's run does not compile or stops before ExUnit reports, the chosen tests are run again with no mutation applied: with every test excluded when the compile failed, which compiles and loads everything and runs nothing, and with the tests otherwise. Which file the error names does not decide it, because a mutant can break a file that depends on it (a caller of a macro it changed) and a change elsewhere can break the mutated file. If the unmutated run fails the same way, the run stops with the files the error names and nothing scored, as the umbrella baseline does. If it passes, the mutant is still `:invalid`. Each invalid mutant costs this one extra run.

## [0.10.0] - 2026-09-12

### Fixed
- **Umbrella Project Root**: `--app <app>` now resolves the umbrella root as the project root instead of `apps/<app>`, whose `config_path: "../../config/config.exs"` pointed outside the sandbox.
- **Umbrella Sandboxes**: Umbrella sandboxes now clone `apps/` and `_build/<env>` (copy-on-write where supported) instead of linking each app, so `in_umbrella` dependencies resolve inside the sandbox and no recompile writes into the real build. Every mutant used to come back `:invalid`. Each sandbox is compiled once before the first mutant, outside the per-mutant timeout. The sandbox's parent mirrors the project's parent, so tests that read files beside the project still find them.
- **Test Selection**: `Muex.DependencyAnalyzer` joined module name parts without a separator (`:ElixirMyAppFoo`), so no test file was ever selected and every mutant ran the whole test directory.
- **Baseline Check**: In umbrellas, the selected tests are run once with no mutation applied, and the run stops if any fail, instead of reporting every mutant they judge as killed.
- **Empty Test Selection**: A mutant with no selected test file stops the run. `mix test` given no files runs every test.
- **Writes Through Links**: Files outside `apps/<app>/` are refused in umbrellas, and a mutant is never written or restored through a symlink into the real project.
- **Sandbox Cleanup**: Sandboxes are removed when setup, warm-up or the baseline fails.
- **Worker Pool Crash**: The pool no longer crashes on the `{:EXIT, port, :normal}` messages that `System.cmd` sends during sandbox setup.

### Changed
- **Kill Evidence**: A killed mutant's `error` field now holds the first ExUnit failure block (test name, file:line, assertion), shown in JSON and HTML reports.
- **Pool Size**: No more sandboxes are created than there are distinct mutated files.
- **Progress Output**: Warm-up and baseline progress lines go to stderr, so `--format json` output stays parseable.

## [0.9.0] - 2026-08-26

Special thanks to [@e-fu](https://github.com/e-fu) for extensive bug reports, detailed reproductions, and code contributions!

### Fixed
- **Behavior Definition vs Implementation Filtering**: `Muex.FileAnalyzer` no longer skips modules that implement a behavior (`@behaviour SomeBehaviour`). Only modules defining multiple `@callback` annotations are skipped as behavior definitions ([#22](https://github.com/Oeditus/muex/issues/22)). (Credit: [@e-fu](https://github.com/e-fu))
- **Threshold Enforcement on Empty Runs**: `mix muex` now enforces the `--fail-at` threshold when zero mutations are tested rather than silently passing ([#22](https://github.com/Oeditus/muex/issues/22)). (Credit: [@e-fu](https://github.com/e-fu))
- **Sandbox File Linking**: Symlinked all files and subdirectories in the test root (`test/`) into worker sandboxes when narrowing `--test-paths`, ensuring test modules can access compile-time and runtime fixtures, golden files, and schemas ([#25](https://github.com/Oeditus/muex/issues/25)). (Credit: [@e-fu](https://github.com/e-fu))
- **Invalid Verdict Error Details**: Preserved error details in `classify_test_result` when test runs yield `:invalid` verdicts, preventing `error: null` in output reports ([#25](https://github.com/Oeditus/muex/issues/25)). (Credit: [@e-fu](https://github.com/e-fu))
- **Dotted Exception Name Matching**: Updated `compile_error?` regex pattern to support namespaced Elixir exceptions such as `File.Error` and `Jason.DecodeError` ([#25](https://github.com/Oeditus/muex/issues/25)). (Credit: [@e-fu](https://github.com/e-fu))
- **Accurate Node Replacement Matching**: Matched mutations by their original node AST line (`:original_line`) rather than reported display line ([#27](https://github.com/Oeditus/muex/pull/27)). (Credit: [@e-fu](https://github.com/e-fu))
- **App Detection in Sandbox**: Improved OTP application name detection from project definitions rather than guessing from `_build` markers ([#26](https://github.com/Oeditus/muex/pull/26)). (Credit: [@e-fu](https://github.com/e-fu))
- **Unmeasured Runs Verdict Handling**: Fixed unmeasured test runs from being incorrectly counted as killed mutants ([#20](https://github.com/Oeditus/muex/issues/20) / [#21](https://github.com/Oeditus/muex/pull/21)). (Credit: [@e-fu](https://github.com/e-fu))

### Changed
- **Mutator Type Spec**: Made `:original_ast`, `:original_line`, and `:equivalent` optional keys in `@type Muex.Mutator.mutation()` map spec to prevent type friction for external mutators.
