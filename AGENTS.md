# Project Rules

> **Single Source of Truth** for AI coding assistants (Claude Code, Cursor, etc.)

______________________________________________________________________

## Project Scope

Live aircraft position tracking on the Elastic Stack. Logstash pipelines poll the
[OpenSky Network](https://opensky-network.org) REST API for real-time ADS-B transponder
data across four global quadrants, enrich each position with country/region geo-shapes and
nearest-airport proximity, and index everything into an Elasticsearch data stream for
visualisation in Kibana. An Agent Builder + Workflows layer adds AI agents, daily
briefings, and automated hijack (squawk 7500) investigation. See the
[README](README.md) for architecture and setup detail.

______________________________________________________________________

## At Startup

This repository uses **beads (bd)** for issue tracking (`.beads/` is present). Before
starting work, see [Issue Tracking](#beads-issue-tracker) at the foot of this file and run
`bd prime` for the full workflow context.

______________________________________________________________________

## Behavioural Guidelines

Guidelines to reduce common LLM coding mistakes. These bias toward caution over speed;
for trivial tasks, use judgement.

### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them; don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it; don't delete it.

When your changes create orphans:

- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:

- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:

```text
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work")
require constant clarification.

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites
due to overcomplication, and clarifying questions come before implementation rather than
after mistakes.

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

### 5. Environment

- **Docker commands require elevated permissions.** Every `docker` / `docker compose`
  command (including read-only ones like `docker ps`) must use
  `required_permissions: ["all"]`, or it silently fails under the sandbox. Full rationale
  and examples: [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md#docker-access).

### 6. Pre-flight Checklist

1. Read the task, confirm assumptions, and outline the approach.
2. Inspect the relevant files (include imports/configs for context).
3. After changes, run the [post-change checklist](docs/DEVELOPMENT.md#post-change-checklist).
4. Summarise edits, mention tests, and flag follow-up work in the final response.

______________________________________________________________________

## Reference

- **Development** (tech stack, Make targets, Docker access, conventions): [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)
- **Releasing** (version, tag, publish workflow): [`docs/RELEASING.md`](docs/RELEASING.md)
- **Elastic Skills & MCP Servers** (skill categories, MCP usage, precedence): [`docs/elastic-skills-mcp.md`](docs/elastic-skills-mcp.md)
- **Testing via API** (curl patterns for ES, workflows, agents): [`docs/testing-api.md`](docs/testing-api.md)
- **Known Quirks** (read before touching workflows, cases, ILM, alert rules): [`docs/known-quirks.md`](docs/known-quirks.md)

______________________________________________________________________

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

5. ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```

6. **Clean up** - Clear stashes, prune remote branches

7. **Verify** - All changes committed AND pushed

8. **Hand off** - Provide context for next session

**CRITICAL RULES:**

- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

<!-- END BEADS INTEGRATION -->
