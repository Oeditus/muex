# Release Automation

This document explains the automated release workflow for Muex.

## Overview

Muex uses GitHub Actions to automate the complete release process. When you push a version tag, the workflow automatically:

1. Builds production-ready escript and hex archive
2. Generates SHA256 checksums for security verification
3. Creates a GitHub Release with downloadable artifacts
4. Publishes the package to Hex.pm (stable releases only)
5. Generates comprehensive release notes

## Workflow Architecture

### Workflow File

`.github/workflows/release.yml`

### Jobs

1. **build** - Builds and publishes artifacts
   - Compiles with `MIX_ENV=prod`
   - Builds escript (`muex`)
   - Builds hex archive (`muex-X.Y.Z.ez`)
   - Generates checksums
   - Creates GitHub Release
   
2. **publish-hex** - Publishes to Hex.pm
   - Only runs for stable releases (not alpha/beta/rc)
   - Requires `HEX_API_KEY` secret
   - Depends on successful build job
   
3. **notify** - Final status check
   - Reports success/failure
   - Provides release URL

### Triggers

The workflow triggers on:
- Push of tags matching `v*` pattern
- Examples: `v0.2.0`, `v1.0.0-beta.1`, `v2.0.0-rc.1`

### Artifacts Generated

For each release, the workflow creates:

| Artifact | Description | Size |
|----------|-------------|------|
| `muex` | Standalone escript binary | ~3.3 MB |
| `muex-X.Y.Z.ez` | Hex archive | ~174 KB |
| `muex.sha256` | Escript checksum | ~100 bytes |
| `muex-archive.sha256` | Archive checksum | ~100 bytes |

## Release Types

### Stable Release

**Tag format**: `v0.2.0`, `v1.0.0`

**Behavior**:
- Creates GitHub Release (not marked as pre-release)
- Publishes to Hex.pm
- Available via `mix archive.install hex muex`

**Command**:
```bash
git tag -a v0.2.0 -m "Release v0.2.0"
git push origin v0.2.0
```

### Pre-Release

**Tag formats**: `v0.3.0-alpha.1`, `v0.3.0-beta.1`, `v0.3.0-rc.1`

**Behavior**:
- Creates GitHub Release (marked as pre-release)
- Does NOT publish to Hex.pm
- Available only via GitHub download or local archive install

**Command**:
```bash
git tag -a v0.3.0-beta.1 -m "Beta release"
git push origin v0.3.0-beta.1
```

## Setup Requirements

### First-Time Configuration

#### 1. Hex API Key

Generate and add your Hex.pm API key:

```bash
# Visit https://hex.pm/settings
# Generate new API key with "Publish packages" permission
# Copy the key

# Add to GitHub repository secrets
gh secret set HEX_API_KEY
# Paste the key when prompted
```

Or via GitHub UI:
1. Go to repository Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `HEX_API_KEY`
4. Value: Your Hex API key
5. Click "Add secret"

#### 2. GitHub Actions Permissions

Enable write permissions for releases:

1. Go to repository Settings → Actions → General
2. Scroll to "Workflow permissions"
3. Select "Read and write permissions"
4. Check "Allow GitHub Actions to create and approve pull requests"
5. Click "Save"

### Verification

Check that everything is configured:

```bash
# Check secrets
gh secret list

# Check if HEX_API_KEY exists
gh secret list | grep HEX_API_KEY
```

## Using the Workflow

### Standard Release Process

```bash
# 1. Update version and changelog
vim mix.exs  # Update @version
vim CHANGELOG.md

# 2. Commit changes
git add mix.exs CHANGELOG.md
git commit -m "Bump version to 0.3.0"
git push origin main

# 3. Create and push tag
git tag -a v0.3.0 -m "Release v0.3.0"
git push origin v0.3.0

# 4. Monitor workflow
gh run watch

# 5. Verify release
gh release view v0.3.0
```

### Quick Release (One-Liner)

```bash
# Ensure version is updated in mix.exs first
git tag -a v0.3.0 -m "Release v0.3.0" && git push origin v0.3.0 && gh run watch
```

## Release Notes

The workflow automatically generates release notes that include:

- Installation instructions for all three methods (escript, archive, dependency)
- Usage examples
- Checksum verification instructions
- Links to documentation
- Auto-generated changelog from commits

Users see comprehensive instructions when downloading from GitHub Releases.

## Monitoring

### View Workflow Status

```bash
# List recent runs
gh run list --workflow=release.yml

# Watch current run
gh run watch

# View specific run
gh run view RUN_ID

# View logs
gh run view --log
```

### GitHub UI

Visit: https://github.com/Oeditus/muex/actions

Filter by "Release" workflow to see all release builds.

## Troubleshooting

### Build Failures

**Symptom**: Workflow fails during build step

**Common causes**:
- Compilation errors
- Test failures
- Missing dependencies

**Resolution**:
```bash
# Check logs
gh run view --log

# Fix issues locally
mix test
mix quality

# Delete bad tag
git tag -d v0.3.0
git push origin :refs/tags/v0.3.0

# Re-tag after fix
git tag -a v0.3.0 -m "Release v0.3.0"
git push origin v0.3.0
```

### Hex Publishing Failures

**Symptom**: Build succeeds but Hex.pm publish fails

**Common causes**:
- Missing or invalid `HEX_API_KEY`
- Package validation errors
- Version already published

**Resolution**:
```bash
# Check if secret exists
gh secret list | grep HEX_API_KEY

# Regenerate key if needed
# Visit https://hex.pm/settings
gh secret set HEX_API_KEY

# Manual publish (if workflow fails)
git checkout v0.3.0
export HEX_API_KEY="your-key"
mix hex.publish --yes
```

### Release Not Created

**Symptom**: Workflow succeeds but no GitHub Release appears

**Common causes**:
- Insufficient permissions
- GITHUB_TOKEN issue

**Resolution**:
```bash
# Check Actions permissions (GitHub UI)
# Settings → Actions → General → Workflow permissions

# Manual release creation
make build  # Build artifacts locally
gh release create v0.3.0 muex muex-0.3.0.ez \
  --title "v0.3.0" \
  --notes "See CHANGELOG.md"
```

## Security

### Checksum Verification

Users can verify downloaded artifacts:

```bash
# Download escript and checksum
wget https://github.com/Oeditus/muex/releases/download/v0.3.0/muex
wget https://github.com/Oeditus/muex/releases/download/v0.3.0/muex.sha256

# Verify
sha256sum -c muex.sha256
```

### Secrets Management

- `HEX_API_KEY` is stored encrypted in GitHub Secrets
- Never committed to repository
- Only accessible during workflow execution
- Can be rotated anytime without code changes

## Workflow Customization

To modify the workflow:

1. Edit `.github/workflows/release.yml`
2. Test changes on a feature branch with a test tag
3. Once verified, merge to main

Common customizations:
- Change Elixir/OTP versions
- Add additional build steps
- Modify release note template
- Add Slack/Discord notifications

## Further Reading

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Hex.pm Publishing Guide](https://hex.pm/docs/publish)
- [Complete Release Guide](../docs/RELEASING.md)
- [Build & Distribution Guide](../docs/BUILD_AND_DISTRIBUTE.md)
