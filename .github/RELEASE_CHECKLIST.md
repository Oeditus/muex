# Release Checklist

Quick reference for creating a new Muex release.

## Pre-Release

- [ ] All tests passing: `mix test`
- [ ] Quality checks pass: `mix quality`
- [ ] Update version in `mix.exs`: `@version "X.Y.Z"`
- [ ] Update `CHANGELOG.md` with changes
- [ ] Commit version bump: `git commit -am "Bump version to X.Y.Z"`
- [ ] Push to main: `git push origin main`

## Release

- [ ] Create tag: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`
- [ ] Push tag: `git push origin vX.Y.Z`
- [ ] Monitor workflow: https://github.com/Oeditus/muex/actions
- [ ] Wait for workflow completion (~3-5 minutes)

## Post-Release

- [ ] Verify GitHub Release created
- [ ] Check artifacts present:
  - [ ] `muex` (escript)
  - [ ] `muex-X.Y.Z.ez` (archive)
  - [ ] `muex.sha256` (checksum)
  - [ ] `muex-archive.sha256` (checksum)
- [ ] Verify Hex.pm publish (stable releases)
- [ ] Test escript installation:
  ```bash
  wget https://github.com/Oeditus/muex/releases/download/vX.Y.Z/muex
  chmod +x muex
  ./muex --version
  ```
- [ ] Test hex archive installation:
  ```bash
  mix archive.install hex muex
  mix muex --version
  ```

## Announce

- [ ] Post on Elixir Forum
- [ ] Tweet/share on social media
- [ ] Update project README if needed

## Troubleshooting

**Build fails?**
```bash
gh run view --log  # Check logs
git tag -d vX.Y.Z  # Delete local tag
git push origin :refs/tags/vX.Y.Z  # Delete remote tag
# Fix issue, then re-tag
```

**Need to rollback?**
```bash
gh release delete vX.Y.Z --yes
git tag -d vX.Y.Z
git push origin :refs/tags/vX.Y.Z
```

## Version Types

- **Stable**: `v0.2.0` → Publishes to GitHub + Hex.pm
- **Pre-release**: `v0.3.0-beta.1` → GitHub only (no Hex.pm)

## Quick Commands

```bash
# Create stable release
git tag -a v0.3.0 -m "Release v0.3.0" && git push origin v0.3.0

# Create pre-release
git tag -a v0.3.0-beta.1 -m "Beta release" && git push origin v0.3.0-beta.1

# View release
gh release view vX.Y.Z

# List workflows
gh run list --workflow=release.yml

# Watch workflow
gh run watch
```

## First-Time Setup

1. Generate Hex API key: https://hex.pm/settings
2. Add to GitHub secrets as `HEX_API_KEY`
3. Enable Actions write permissions in repo settings

For detailed instructions, see [docs/RELEASING.md](../docs/RELEASING.md)
