# Project Rules

> **Single Source of Truth** for AI coding assistants (Claude Code, Cursor, etc.)

______________________________________________________________________

## Tech Stack & Commands

- **Runtime**: Docker & Docker Compose
- **Data pipeline**: Logstash 9.x (four quadrant pipelines polling the OpenSky Network API)
- **Search & storage**: Elasticsearch (time-series data stream with geo-shape enrichment)
- **Visualisation**: Kibana (dashboards, data views)
- **Setup automation**: Bash (`setup.sh`)

| Command                      | Purpose                                                                  |
| ---------------------------- | ------------------------------------------------------------------------ |
| `cp .env.example .env`       | Create local environment config                                          |
| `make setup`                 | Create ES indices, enrich policy, ingest pipeline, import Kibana objects |
| `make setup-no-service-user` | Run full setup without service user (actions attributed to .env API key) |
| `make deploy-ilm`            | Deploy ES ILM policy only (skipped on Serverless)                        |
| `make deploy-indices`        | Deploy ES index templates and data streams only                          |
| `make deploy-enrich`         | Deploy ES enrich policies only                                           |
| `make deploy-pipelines`      | Deploy ES ingest pipelines only                                          |
| `make deploy-kibana`         | Deploy Kibana saved objects (dashboards, data views) only                |
| `make deploy-cases`          | Deploy case configuration (custom fields, templates)                     |
| `make deploy-workflows`      | Deploy Kibana workflows only                                             |
| `make deploy-agents`         | Deploy Kibana AI agents only                                             |
| `make deploy-demouser`       | Deploy demo user roles and users only                                    |
| `make deploy-es`             | Deploy all ES resources (ilm + indices + enrich + pipelines)             |
| `make deploy-ai`             | Deploy AI layer (workflows + agents)                                     |
| `make redeploy`              | Re-deploy all resources (force overwrite)                                |
| `make up`                    | Start Logstash (all 4 pipelines)                                         |
| `make down`                  | Stop Logstash                                                            |
| `make logs`                  | Tail Logstash logs                                                       |
| `make restart`               | Restart Logstash after config changes                                    |
| `make status`                | Show Logstash pipeline status                                            |
| `make clean`                 | Stop Logstash and remove volumes                                         |
| `make validate`              | Validate Docker Compose config                                           |
| `make health`                | Check Elasticsearch cluster health                                       |
| `make ps`                    | Show running containers                                                  |
| `make shell`                 | Open a shell inside the Logstash container                               |
| `make help`                  | List all available targets (grouped)                                     |

Any deploy target accepts `FORCE=1` to overwrite existing resources, e.g. `make deploy-agents FORCE=1`.

**Key conventions**:

- Never edit `.env` directly in commits; only reference `.env.example`.
- Logstash pipeline configs live in `logstash/pipeline/`; Elasticsearch resources in `elasticsearch/`.
- The four pipelines (`adsb_q1`–`adsb_q4`) are intentionally separate to spread load across quadrants.

______________________________________________________________________

## Elastic Skills & MCP Servers

See [docs/elastic-skills-mcp.md](docs/elastic-skills-mcp.md) — skill categories, MCP server usage, and precedence rules.

______________________________________________________________________

## Docker Access

This project relies on Docker for its Logstash service. AI assistants
running in sandboxed environments (e.g. Cursor) often cannot reach the Docker
daemon under default sandbox restrictions.

**Always request elevated permissions for Docker commands.** Use
`required_permissions: ["all"]` for any `docker` or `docker compose` command
(including `docker ps`, `docker logs`, `docker stats`, `docker volume`,
`docker inspect`, etc.). Read-only Docker queries still require the Docker
socket, which the sandbox blocks.

```sh
# Correct — works reliably
Shell(command="docker ps", required_permissions=["all"])

# Wrong — will silently fail with empty output or exit code 1
Shell(command="docker ps")
Shell(command="docker ps", required_permissions=["full_network"])
```

______________________________________________________________________

## Testing via API

See [docs/testing-api.md](docs/testing-api.md) — curl patterns for ES queries, workflows, agents, and side-effect awareness.

______________________________________________________________________

## Known Quirks

See [docs/known-quirks.md](docs/known-quirks.md) — read before touching workflows, cases, ILM, or alert rules.

______________________________________________________________________

## AI Assistant Operating Rules

Concise policy reference for all coding agents touching this repository. Keep responses factual and avoid speculative language.

### 1. Communication & Planning

- Always mention assumptions; ask the user to confirm anything ambiguous before editing.
- Follow the required plan/approval workflow when prompted and wait for explicit approval to execute.
- Use UK-English spelling in comments, documentation, and commit messages.

### 2. File Safety

- Do **not** edit `.env` or other environment files; only reference `.env.example`.
- Delete files only when you created them or the user explicitly instructs you to remove older assets.
- Never run destructive git commands (`git reset --hard`, `git checkout --`, `git restore`, `rm -rf .git`) unless the user provides written approval in this thread.

### 3. Collaboration Etiquette

- If another agent has edited a file, read their changes and build on them — do not revert or overwrite.
- Coordinate before touching large refactors that might conflict with ongoing work.
- Keep diffs minimal and reviewable; use targeted edits rather than rewriting whole files.

### 4. Git & Commits

- Check `git status` before staging and before committing.
- Keep commits atomic and list paths explicitly, e.g. `git commit -m "feat: add CI" -- path/to/file`.
- For new files: `git restore --staged :/ && git add <paths> && git commit -m "<msg>" -- <paths>`.
- Quote any paths containing brackets/parentheses when staging to avoid globbing.
- Never amend existing commits unless the user instructs you to.
- Don't plaster all commits and git issues with "Made with Cursor", "Cursor helped me with this", "AI did everything" or anything similar.

#### Releases

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

   ```
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

### 5. Pre-flight Checklist

1. Read the task, confirm assumptions, and outline the approach.
2. Inspect the relevant files (include imports/configs for context).
3. After changes, verify Docker Compose config parses: `docker compose config --quiet`.
4. Summarise edits, mention tests, and flag follow-up work in the final response.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->

## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**

- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

<!-- END BEADS INTEGRATION -->
