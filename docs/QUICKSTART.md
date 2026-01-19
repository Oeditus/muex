# Quick Start Guide

Get started with Muex mutation testing in 60 seconds.

## Choose Your Installation Method

### Fast Start: Hex Archive (Recommended)

Install globally in one command:

```bash
mix archive.install hex muex
```

Use in any project:

```bash
cd your_project
mix muex
```

### Alternative: Escript

Download or build the standalone binary:

```bash
# From muex repository
git clone https://github.com/Oeditus/muex
cd muex
mix deps.get
mix escript.build
sudo cp muex /usr/local/bin/
```

Use in any project:

```bash
cd your_project
muex
```

### Per-Project: Mix Dependency

Add to your project's `mix.exs`:

```elixir
def deps do
  [
    {:muex, "~> 0.2.0", only: [:dev, :test], runtime: false}
  ]
end
```

Then:

```bash
mix deps.get
mix muex
```

## First Run

Run mutation testing on your project:

```bash
# Using hex archive or mix dependency
mix muex

# Using escript
muex
```

## Common Usage Patterns

### Quick Check (Development)

Fast feedback with optimization:

```bash
mix muex --optimize --max-mutations 50
```

### CI/CD Pipeline

Comprehensive testing with quality gate:

```bash
mix muex --fail-at 80 --format json
```

### Specific Files

Test only changed files:

```bash
mix muex --files "lib/my_module.ex"
```

### Detailed Report

Generate HTML report with full analysis:

```bash
mix muex --format html --verbose
```

## Interpreting Results

### Mutation Score

- **90-100%**: Excellent test coverage
- **80-90%**: Good test coverage
- **70-80%**: Adequate but could improve
- **<70%**: Weak test coverage

### Survived Mutations

Review mutations that weren't caught by tests:

```
SURVIVED: lib/calculator.ex:10
  Original: a + b
  Mutated:  a - b
  Description: Changed + to -
```

This indicates your tests don't verify the addition operation correctly.

## Next Steps

- Read the [Installation Guide](docs/INSTALLATION.md) for detailed setup
- Check [USAGE.md](USAGE.md) for all options
- Learn about [Mutation Optimization](docs/MUTATION_OPTIMIZATION.md)
- Run `mix muex --help` (or `muex --help`) for full options

## Getting Help

- **Bug reports**: https://github.com/Oeditus/muex/issues
- **Documentation**: https://hexdocs.pm/muex
- **Examples**: See `examples/` directory in the repository
