# Project Rules

> **Single Source of Truth** for AI coding assistants (Claude Code, Cursor, etc.)

______________________________________________________________________

## Tech Stack & Commands

- **Runtime**: Docker & Docker Compose
- **Data pipeline**: Logstash 9.x (four quadrant pipelines polling the OpenSky Network API)
- **Search & storage**: Elasticsearch (time-series data stream with geo-shape enrichment)
- **Visualisation**: Kibana (dashboards, data views)
- **Setup automation**: Bash (`setup.sh`)

| Command                | Purpose                                                                  |
| ---------------------- | ------------------------------------------------------------------------ |
| `cp .env.example .env` | Create local environment config                                          |
| `make setup`           | Create ES indices, enrich policy, ingest pipeline, import Kibana objects |
| `make up`              | Start Logstash (all 4 pipelines)                                         |
| `make down`            | Stop Logstash                                                            |
| `make logs`            | Tail Logstash logs                                                       |
| `make restart`         | Restart Logstash after config changes                                    |
| `make status`          | Show Logstash pipeline status                                            |
| `make clean`           | Stop Logstash and remove volumes                                         |
| `make help`            | List all available targets                                               |

**Key conventions**:

- Never edit `.env` directly in commits; only reference `.env.example`.
- Logstash pipeline configs live in `logstash/pipeline/`; Elasticsearch resources in `elasticsearch/`.
- The four pipelines (`adsb_q1`–`adsb_q4`) are intentionally separate to spread load across quadrants.

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

### 5. Pre-flight Checklist

1. Read the task, confirm assumptions, and outline the approach.
2. Inspect the relevant files (include imports/configs for context).
3. After changes, verify Docker Compose config parses: `docker compose config --quiet`.
4. Summarise edits, mention tests, and flag follow-up work in the final response.
