# Build and Distribution Guide

This guide covers building and distributing Muex as an escript and hex archive.

## Overview

Muex can be packaged in three ways:

1. **Mix dependency** - Traditional Hex package (for per-project use)
2. **Hex archive** - Global Mix task available system-wide
3. **Escript** - Standalone executable binary

## Building

### Quick Build

Use the Makefile for convenience:

```bash
# Build both escript and archive
make build

# Build only escript
make escript

# Build only archive
make archive

# See all available commands
make help
```

### Manual Build

#### Escript

```bash
mix deps.get
mix compile
mix escript.build
```

This creates a standalone executable `muex` (approximately 3.3 MB).

#### Hex Archive

```bash
mix deps.get
mix compile
mix archive.build
```

This creates `muex-X.Y.Z.ez` archive (approximately 174 KB).

### Build Configuration

The build is configured in `mix.exs`:

```elixir
def escript do
  [
    main_module: Muex.CLI,
    name: "muex",
    embed_elixir: true,
    app: nil
  ]
end
```

Key settings:
- `main_module: Muex.CLI` - Entry point for the escript
- `embed_elixir: true` - Include Elixir runtime (larger but portable)
- `app: nil` - Don't start the application automatically

## Installation

### Escript Installation

#### System-wide (Linux/macOS)

```bash
# Install to /usr/local/bin
sudo cp muex /usr/local/bin/muex
sudo chmod +x /usr/local/bin/muex

# Verify
muex --version
```

#### User-local

```bash
# Install to ~/.local/bin (ensure it's in PATH)
mkdir -p ~/.local/bin
cp muex ~/.local/bin/
chmod +x ~/.local/bin/muex

# Add to PATH if needed
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc  # or ~/.zshrc
source ~/.bashrc
```

#### Windows

Copy `muex` to a directory in your PATH, or:

```powershell
# PowerShell
Copy-Item muex C:\Windows\System32\muex.exe
```

### Hex Archive Installation

#### From Local Build

```bash
mix archive.install muex-0.2.0.ez
```

#### From Hex.pm (after publishing)

```bash
mix archive.install hex muex
```

#### From GitHub

```bash
mix archive.install github Oeditus/muex
```

### Verification

```bash
# Escript
muex --version
muex --help

# Hex archive
mix muex --version
mix archive | grep muex
```

## Distribution

### Escript Distribution

The escript is a single, standalone executable that can be distributed via:

1. **GitHub Releases**
   - Upload as a release asset
   - Users download and install manually
   ```bash
   wget https://github.com/Oeditus/muex/releases/download/v0.2.0/muex
   chmod +x muex
   sudo mv muex /usr/local/bin/
   ```

2. **Direct Download**
   - Host on a web server
   - Provide curl/wget install script

3. **Package Managers**
   - Create packages for apt, brew, etc.
   - Example homebrew formula:
   ```ruby
   class Muex < Formula
     desc "Mutation testing for Elixir and Erlang"
     homepage "https://github.com/Oeditus/muex"
     url "https://github.com/Oeditus/muex/releases/download/v0.2.0/muex"
     sha256 "..."
     
     def install
       bin.install "muex"
     end
   end
   ```

### Hex Archive Distribution

The hex archive is distributed through Hex.pm:

1. **Publish to Hex**
   ```bash
   # First time
   mix hex.user register
   
   # Publish
   mix hex.publish
   ```

2. **Users Install From Hex**
   ```bash
   mix archive.install hex muex
   ```

3. **Update Process**
   ```bash
   mix archive.uninstall muex
   mix archive.install hex muex
   ```

## Version Management

When releasing a new version:

1. Update version in `mix.exs`:
   ```elixir
   @version "0.3.0"
   ```

2. Update CHANGELOG.md

3. Rebuild artifacts:
   ```bash
   make clean
   make build
   ```

4. Tag release:
   ```bash
   git tag -a v0.3.0 -m "Release v0.3.0"
   git push origin v0.3.0
   ```

5. Publish to Hex:
   ```bash
   mix hex.publish
   ```

6. Create GitHub Release with escript attachment

## Testing

Test both installation methods:

```bash
# Automated test
make test-install

# Or manual test
./scripts/test_installations.sh
```

The test script:
- Creates a temporary test project
- Tests escript functionality
- Tests hex archive functionality (if installed)
- Verifies mutation testing runs correctly

## CI/CD Integration

Muex includes a complete GitHub Actions workflow for automated releases.

### GitHub Actions Workflow

The release workflow is located at `.github/workflows/release.yml` and automatically:

1. Builds escript and hex archive with production settings
2. Generates SHA256 checksums for verification
3. Creates GitHub Release with all artifacts
4. Publishes to Hex.pm (stable releases only)
5. Marks pre-releases (alpha, beta, rc) appropriately

**Trigger a release:**

```bash
git tag -a v0.3.0 -m "Release v0.3.0"
git push origin v0.3.0
```

**Setup requirements:**

1. Add `HEX_API_KEY` to repository secrets (for Hex.pm publishing)
2. Enable write permissions for GitHub Actions

For detailed release instructions, see [RELEASING.md](RELEASING.md).

## Troubleshooting

### Escript Issues

**Problem**: "No mix.exs found"
- **Solution**: The escript must be run from a project directory containing mix.exs

**Problem**: "Permission denied"
- **Solution**: Make the file executable: `chmod +x muex`

**Problem**: Large file size
- **Reason**: Includes embedded Elixir runtime
- **Solution**: This is normal; enables portability

### Hex Archive Issues

**Problem**: "The task muex could not be found"
- **Solution**: Ensure archive is installed: `mix archive | grep muex`

**Problem**: Version conflicts
- **Solution**: Uninstall and reinstall:
  ```bash
  mix archive.uninstall muex
  mix archive.install hex muex
  ```

### Build Issues

**Problem**: Compilation errors
- **Solution**: Clean and rebuild:
  ```bash
  make clean
  mix deps.clean --all
  mix deps.get
  make build
  ```

## Best Practices

1. **Version Consistency**: Keep escript and archive versions synchronized
2. **Testing**: Always test both artifacts before release
3. **Documentation**: Update installation docs when changing build process
4. **Size Optimization**: Consider compression for escript distribution
5. **Checksums**: Provide SHA256 checksums for escript downloads

## File Sizes

Typical sizes (as of v0.2.0):

- **Escript**: ~3.3 MB (includes Elixir runtime)
- **Hex Archive**: ~174 KB (relies on system Elixir)
- **Hex Package**: ~50 KB (source only)

The escript is larger because it includes the Elixir runtime, making it fully standalone.

## Further Reading

- [Mix.Tasks.Escript.Build](https://hexdocs.pm/mix/Mix.Tasks.Escript.Build.html)
- [Mix.Tasks.Archive.Build](https://hexdocs.pm/mix/Mix.Tasks.Archive.Build.html)
- [Hex.pm Publishing](https://hex.pm/docs/publish)
- [Installation Guide](INSTALLATION.md)
