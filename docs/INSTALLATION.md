# Installation Guide

Muex can be used in three ways: as a Mix dependency, as an escript, or as a hex archive.

## Option 1: Mix Dependency (Recommended for Project-Specific Use)

Add `muex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:muex, "~> 0.2.0", only: [:dev, :test], runtime: false}
  ]
end
```

Then run:

```bash
mix deps.get
mix muex
```

## Option 2: Escript (Standalone Binary)

Build and install the escript to run muex as a standalone command-line tool:

### Build the escript

From the muex repository:

```bash
mix escript.build
```

This creates a standalone executable `muex` in the current directory.

### Install system-wide

Copy the executable to a directory in your PATH:

```bash
# Linux/macOS
sudo cp muex /usr/local/bin/muex
sudo chmod +x /usr/local/bin/muex

# Or to user bin (add to PATH if needed)
cp muex ~/.local/bin/muex
chmod +x ~/.local/bin/muex
```

### Usage

Navigate to any Elixir project and run:

```bash
muex
muex --files "lib/my_module.ex"
muex --optimize --fail-at 80
```

### Advantages

- Single binary, easy to distribute
- No need to add muex as a dependency
- Works in any Elixir project
- Fast startup

### Limitations

- Requires the target project to have Mix and dependencies compiled
- Must be rebuilt to update to newer versions

## Option 3: Hex Archive (Recommended for Global Installation)

Install muex as a hex archive to make it available globally via `mix muex`:

### Install from Hex

```bash
mix archive.install hex muex
```

### Install from local build

From the muex repository:

```bash
# Build the archive
mix archive.build

# Install it
mix archive.install muex-0.2.0.ez
```

### Install from GitHub

```bash
mix archive.install github Oeditus/muex
```

### Usage

Navigate to any Elixir project and run:

```bash
mix muex
mix muex --files "lib/**/*.ex" --optimize
```

The command will be available globally in all your Elixir projects.

### Update

To update to a newer version:

```bash
# Uninstall old version
mix archive.uninstall muex

# Install new version
mix archive.install hex muex
```

### List installed archives

```bash
mix archive
```

### Advantages

- Available globally via `mix muex`
- Integrated with Mix tooling
- Easy to update via hex
- Automatic version management

### Limitations

- Still requires Mix environment in target project
- Slightly slower startup than escript

## Comparison

| Feature | Mix Dependency | Escript | Hex Archive |
|---------|---------------|---------|-------------|
| Installation | Project-specific | Manual copy | One-time global |
| Updates | `mix deps.update` | Rebuild manually | `mix archive.install` |
| Availability | Per-project | System-wide | System-wide |
| Command | `mix muex` | `muex` | `mix muex` |
| Startup time | Fast | Fastest | Fast |
| Disk usage | Per-project | Single binary | Shared archive |

## Recommended Approach

- **For CI/CD pipelines**: Use as a Mix dependency for reproducible builds
- **For local development across multiple projects**: Use hex archive for convenience
- **For distribution to teams**: Use escript for simplicity and portability

## Verification

After installation, verify it works:

```bash
# For mix dependency or hex archive
mix muex --version

# For escript
muex --version
```

## Troubleshooting

### Escript: "No mix.exs found"

The escript must be run from the root of an Elixir project. Navigate to your project directory:

```bash
cd /path/to/your/elixir/project
muex
```

### Hex archive: "The task muex could not be found"

Ensure the archive is installed:

```bash
mix archive
```

If not listed, reinstall:

```bash
mix archive.install hex muex
```

### Permission denied (escript)

Make the escript executable:

```bash
chmod +x muex
```

### Outdated version

For hex archive:

```bash
mix archive.uninstall muex
mix archive.install hex muex
```

For escript, rebuild from the latest source:

```bash
git pull
mix deps.get
mix escript.build
```
