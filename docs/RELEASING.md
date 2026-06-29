# Releasing

Automated release procedure for the ADS-B demo.
See [`../AGENTS.md`](../AGENTS.md) for agent behaviour and [`DEVELOPMENT.md`](DEVELOPMENT.md) for the dev workflow.

______________________________________________________________________

**Trigger:** When the user says **"release-ready"**, execute the full release procedure below without further prompting. Do not stop between steps or ask for confirmation unless a step fails.

**Prerequisites (validate before starting):**

- `[Unreleased]` section in `CHANGELOG.md` is non-empty
- Working tree is clean (`git status` shows no uncommitted changes apart from CHANGELOG/AGENTS.md)
- Current branch is `main`

**Procedure:**

1. **Determine version** - read `CHANGELOG.md` `[Unreleased]` entries and the latest tag (`git tag --sort=-v:refname | head -1`). Infer the bump type from the changes:

   - `### Added` sections or new features = minor bump
   - `### Fixed` / `### Changed` only = patch bump
   - Breaking changes or user-specified = major bump
   - If ambiguous, ask the user once: "minor or patch?"

2. **Update CHANGELOG** - rename `## [Unreleased]` content into `## [X.Y.Z] - YYYY-MM-DD` (today's date). Leave an empty `## [Unreleased]` section above it.

3. **Update CHANGELOG footer links** - add the new version's compare link and update `[unreleased]` to point from the new tag to HEAD:

   ```txt
   [X.Y.Z]: https://github.com/face0b1101/adsb-demo/compare/vPREV...vX.Y.Z
   [unreleased]: https://github.com/face0b1101/adsb-demo/compare/vX.Y.Z...HEAD
   ```

4. **Commit** - stage and commit:

   ```bash
   git add CHANGELOG.md
   git commit -m "chore: release vX.Y.Z"
   ```

   Include any other files modified as part of the release (e.g. AGENTS.md), but do not stage unrelated work.

5. **Tag** - create a signed annotated tag:

   ```bash
   SSH_AUTH_SOCK="$HOME/.bitwarden-ssh-agent.sock" \
     git tag -s -a vX.Y.Z -m "<one-line summary from CHANGELOG>"
   ```

6. **Push** - push commit and tag:

   ```bash
   git push && git push origin vX.Y.Z
   ```

7. **GitHub Release** - create the release from the CHANGELOG notes:

   ```bash
   gh release create vX.Y.Z --title "vX.Y.Z - <title>" \
     --notes "<notes from CHANGELOG>" --latest
   ```

8. **Verify** - run `git status` and confirm it shows "up to date with origin". Run `gh release view vX.Y.Z` to confirm the release exists.

**Rules:**

- Never leave a CHANGELOG version without a matching git tag and GitHub Release.
- If any step fails, stop, report the error, and attempt to fix it before continuing.
