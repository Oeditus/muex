# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
