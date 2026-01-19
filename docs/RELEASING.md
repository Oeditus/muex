# Release Process

This guide covers how to create a new release of Muex.

## Overview

The release process is automated via GitHub Actions when a new tag is pushed. The workflow:

1. Builds both escript and hex archive artifacts
2. Generates SHA256 checksums
3. Creates a GitHub Release with downloadable artifacts
4. Publishes to Hex.pm (for stable releases only)

## Prerequisites

### One-Time Setup

1. **Hex API Key** (for Hex.pm publishing)
   - Generate at https://hex.pm/settings (under "API keys")
   - Add to GitHub repository secrets as `HEX_API_KEY`
   - Go to: Repository Settings → Secrets and variables → Actions → New repository secret

2. **Repository Permissions**
   - Ensure GitHub Actions has write permissions for releases
   - Go to: Repository Settings → Actions → General → Workflow permissions
   - Select "Read and write permissions"

## Release Types

### Stable Release (e.g., v0.2.0)

Publishes to both GitHub and Hex.pm:

```bash
git tag v0.2.0
git push origin v0.2.0
```

### Pre-release (e.g., v0.3.0-beta.1)

Publishes to GitHub only (skips Hex.pm):

```bash
git tag v0.3.0-beta.1
git push origin v0.3.0-beta.1
```

Pre-release tags containing `alpha`, `beta`, or `rc` are marked as pre-releases on GitHub.

## Step-by-Step Release Process

### 1. Prepare the Release

Update version and changelog:

```bash
# Edit version in mix.exs
vim mix.exs  # Update @version

# Update CHANGELOG.md
vim CHANGELOG.md

# Commit changes
git add mix.exs CHANGELOG.md
git commit -m "Bump version to 0.3.0"
git push origin main
```

### 2. Create and Push Tag

```bash
# Create annotated tag
git tag -a v0.3.0 -m "Release v0.3.0"

# Push tag to trigger release workflow
git push origin v0.3.0
```

### 3. Monitor Release Workflow

Watch the GitHub Actions workflow:

```bash
# View in browser
open https://github.com/Oeditus/muex/actions

# Or use GitHub CLI
gh run list --workflow=release.yml
gh run watch
```

The workflow will:
- Build escript and archive (takes ~2-3 minutes)
- Create GitHub Release with artifacts
- Publish to Hex.pm (if stable release)

### 4. Verify Release

Check that all artifacts are present:

```bash
# View release
gh release view v0.3.0

# Or in browser
open https://github.com/Oeditus/muex/releases/tag/v0.3.0
```

Expected artifacts:
- `muex` (escript binary)
- `muex-0.3.0.ez` (hex archive)
- `muex.sha256` (escript checksum)
- `muex-archive.sha256` (archive checksum)

### 5. Test Installation

Test both installation methods:

```bash
# Test escript
wget https://github.com/Oeditus/muex/releases/download/v0.3.0/muex
chmod +x muex
./muex --version

# Test hex archive
mix archive.install hex muex
mix muex --version
```

### 6. Announce Release

- Update README.md badges if needed
- Post announcement on Elixir Forum
- Tweet or share on social media

## Troubleshooting

### Build Fails

**Check build logs:**
```bash
gh run view --log
```

**Common issues:**
- Compilation errors: Fix code and re-tag
- Missing dependencies: Update mix.exs
- Test failures: Fix tests first

**To re-release:**
```bash
# Delete bad tag
git tag -d v0.3.0
git push origin :refs/tags/v0.3.0

# Fix issues, commit, and re-tag
git tag -a v0.3.0 -m "Release v0.3.0"
git push origin v0.3.0
```

### Hex Publishing Fails

**Check if HEX_API_KEY is set:**
```bash
# Via GitHub UI
# Repository Settings → Secrets and variables → Actions

# Via GitHub CLI
gh secret list
```

**Generate new key if needed:**
1. Visit https://hex.pm/settings
2. Create new API key with publish permissions
3. Update GitHub secret: `gh secret set HEX_API_KEY`

**Manual publish (if workflow fails):**
```bash
git checkout v0.3.0
mix deps.get
export HEX_API_KEY="your-key-here"
mix hex.publish --yes
```

### Release Not Created

**Check permissions:**
- Ensure Actions has write permissions (see Prerequisites)
- Verify GITHUB_TOKEN is available (automatic)

**Manual release creation:**
```bash
# Build artifacts locally
make build

# Create release with GitHub CLI
gh release create v0.3.0 \
  muex muex-0.3.0.ez \
  --title "v0.3.0" \
  --notes "See CHANGELOG.md for details"
```

## Release Checklist

Before pushing a tag:

- [ ] Version updated in `mix.exs`
- [ ] `CHANGELOG.md` updated with changes
- [ ] All tests passing locally (`mix test`)
- [ ] Code quality checks pass (`mix quality`)
- [ ] Documentation updated if needed
- [ ] Committed and pushed to main branch

After pushing tag:

- [ ] GitHub Actions workflow completed successfully
- [ ] GitHub Release created with all artifacts
- [ ] Hex.pm package published (stable releases)
- [ ] Checksums verified
- [ ] Installation tested from artifacts
- [ ] Release announced

## Version Numbering

Follow Semantic Versioning (SemVer):

- **MAJOR** (v1.0.0): Breaking changes
- **MINOR** (v0.2.0): New features, backward compatible
- **PATCH** (v0.2.1): Bug fixes, backward compatible

Pre-release suffixes:
- `alpha`: Early development (v0.3.0-alpha.1)
- `beta`: Feature complete, testing (v0.3.0-beta.1)
- `rc`: Release candidate (v0.3.0-rc.1)

## Rollback

If a release has critical issues:

### 1. Unpublish from Hex (if published)

```bash
mix hex.package unpublish muex 0.3.0 --revert
```

Note: Hex allows unpublishing within 24 hours.

### 2. Delete GitHub Release

```bash
# Via GitHub CLI
gh release delete v0.3.0 --yes

# Delete tag
git tag -d v0.3.0
git push origin :refs/tags/v0.3.0
```

### 3. Release Fix

```bash
# Fix issues and release patch version
git tag -a v0.3.1 -m "Release v0.3.1 - fixes critical issues"
git push origin v0.3.1
```

## Emergency Hotfix Process

For critical production issues:

```bash
# Create hotfix branch from tag
git checkout -b hotfix/v0.2.1 v0.2.0

# Fix the issue
# ... make changes ...
git commit -am "Fix critical issue"

# Update version to patch
vim mix.exs  # Change to 0.2.1

# Merge to main
git checkout main
git merge --no-ff hotfix/v0.2.1
git push origin main

# Tag and release
git tag -a v0.2.1 -m "Hotfix: critical bug"
git push origin v0.2.1

# Clean up
git branch -d hotfix/v0.2.1
```

## Automation Scripts

### Quick Release Script

Create `scripts/release.sh`:

```bash
#!/bin/bash
set -e

VERSION=$1
if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 0.3.0"
  exit 1
fi

# Update version in mix.exs
sed -i "s/@version \".*\"/@version \"$VERSION\"/" mix.exs

# Prompt for changelog
echo "Update CHANGELOG.md, then press Enter to continue..."
read

# Commit and tag
git add mix.exs CHANGELOG.md
git commit -m "Bump version to $VERSION"
git tag -a "v$VERSION" -m "Release v$VERSION"

# Push
echo "Ready to push. Continue? (y/n)"
read -r response
if [ "$response" = "y" ]; then
  git push origin main
  git push origin "v$VERSION"
  echo "Release v$VERSION triggered!"
else
  echo "Aborted. To clean up:"
  echo "  git reset --hard HEAD~1"
  echo "  git tag -d v$VERSION"
fi
```

Usage:
```bash
chmod +x scripts/release.sh
./scripts/release.sh 0.3.0
```

## Further Reading

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Hex.pm Publishing Guide](https://hex.pm/docs/publish)
- [Semantic Versioning](https://semver.org/)
