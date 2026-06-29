# Dashboard management

How Kibana dashboards are stored, exported, versioned, and redeployed in this project.
See [`DEVELOPMENT.md`](DEVELOPMENT.md) for Make targets and [`known-quirks.md`](known-quirks.md) for
platform gotchas that affect workflows and alerting.

______________________________________________________________________

## Model

Dashboards are **saved objects in source control**, not edited only in Kibana.

| Layer | Location | Role |
| ----- | -------- | ---- |
| Source of truth | [`elasticsearch/kibana/adsb-saved-objects.ndjson`](../elasticsearch/kibana/adsb-saved-objects.ndjson) | Bundled ndjson export committed to git |
| Deploy | `make deploy-kibana` → `setup.sh --only kibana` | Bulk import via Saved Objects API |
| Runtime | Kibana space (`KB_SPACE`, default `adsb`) | Live dashboards users open in the UI |

The ndjson file is a **single bundle** of related objects, not dashboards alone:

| Type | Count (approx.) | Examples |
| ---- | --------------- | -------- |
| `dashboard` | 2 | Aircraft Detail, Aircraft World Overview |
| `map` | 2 | Aircraft Demo, Aircraft World Overview |
| `index-pattern` | 3 | `demos-aircraft-adsb`, geo shapes, countries |
| `search` | 1 | Legacy saved searches still referenced by panels |
| `tag` | 1 | _Demo_ tag |

Import uses `POST /api/saved_objects/_import` against the space-aware `KB_BASE` URL
(see [`testing-api.md`](testing-api.md#prerequisites)).

______________________________________________________________________

## Stable IDs matter

Dashboard UUIDs in the ndjson are **intentionally stable** across deployments. Other
resources resolve them at deploy time:

- **Workflows** — `__DASHBOARD_AIRCRAFT_DETAIL_ID__` and `__DASHBOARD_WORLD_OVERVIEW_ID__`
  placeholders in YAML under `elasticsearch/workflows/`
- **Agents** — `__DASHBOARD_AIRCRAFT_DETAIL_ID__` in `elasticsearch/agents/adsb-agent.json`
- **Alert rules** — squawk 7500 rule links to Aircraft Detail

`setup.sh` extracts IDs from the ndjson by dashboard title:

```bash
jq -r 'select(.type == "dashboard" and .attributes.title == "Aircraft Detail") | .id' \
  elasticsearch/kibana/adsb-saved-objects.ndjson
```

Current IDs (do not change without updating dependents):

| Dashboard | ID |
| --------- | -- |
| Aircraft Detail | `ce6e34c0-ae6d-11ec-9a01-6da5271d9a1d` |
| Aircraft World Overview | `611bbe7b-d277-4684-9974-63cdd2b33d08` |

After changing dashboard IDs in the ndjson, redeploy workflows and agents too:

```bash
make deploy-workflows FORCE=1
make deploy-agents FORCE=1
```

______________________________________________________________________

## Downloading (export from Kibana)

When you edit dashboards in the UI, pull changes back into the repo export.

### Option A — Stack Management export (recommended for full bundle)

1. Open Kibana in the correct space (`/s/adsb/` if `KB_SPACE=adsb`).
2. **Stack Management → Saved Objects**.
3. Filter by the _Demo_ tag (or select the dashboards, maps, data views, and searches they depend on).
4. **Export** → include related objects.
5. Save the file and replace `elasticsearch/kibana/adsb-saved-objects.ndjson`.

The export must remain **one JSON object per line** (ndjson). Kibana's default export format matches this.

### Option B — Saved Objects API

```bash
source .env
KB_BASE="${KB_ENDPOINT%/}"
[[ -n "${KB_SPACE:-}" ]] && KB_BASE="${KB_BASE}/s/${KB_SPACE}"

curl -s "${KB_BASE}/api/saved_objects/_export" \
  -H "Authorization: ApiKey ${ES_API_KEY_ENCODED}" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{"type":["dashboard","map","index-pattern","search","tag"],"includeReferencesDeep":true}' \
  -o elasticsearch/kibana/adsb-saved-objects.ndjson
```

Trim the export to demo objects only if the API returns more than this project needs.

### After export

1. Validate JSON: every line must parse (`python3 -c "import json,sys; [json.loads(l) for l in open('...')]"`).
2. Confirm dashboard IDs unchanged (or redeploy workflows/agents if you changed them).
3. Commit the ndjson with a CHANGELOG entry under `[Unreleased]`.
4. Do **not** commit absolute Kibana host URLs in panel links; use relative paths
   (`/app/dashboards#/view/<id>` or `/s/<space>/app/dashboards#/view/<id>`).

______________________________________________________________________

## Version tracking

| Mechanism | What it tracks |
| --------- | -------------- |
| **Git** | Every change to `adsb-saved-objects.ndjson` is diffable in PRs |
| **CHANGELOG.md** | Human-readable summary per release (`[Unreleased]` → versioned section) |
| **Git tags** | Release snapshots (`v1.11.1`, etc.); see [`RELEASING.md`](RELEASING.md) |

There is no separate dashboard version field inside Kibana. The git commit (and release tag)
is the version record.

Ndjson diffs are often large and opaque (`panelsJSON` is minified). Prefer descriptive
CHANGELOG bullets over relying on the raw diff for review.

______________________________________________________________________

## Reapplying (deploy to Kibana)

```bash
make deploy-kibana          # import; skip objects that already exist
make deploy-kibana FORCE=1  # overwrite existing objects
```

Equivalent: `./setup.sh --only kibana` or `./setup.sh --only kibana --force`.

### When to use `FORCE=1`

| Scenario | FORCE? |
| -------- | ------ |
| First setup on a new deployment | No (or full `make setup`) |
| Pull ndjson changes from git and apply to an existing deployment | **Yes** |
| UI edits you want to discard in favour of source | **Yes** |
| Accidental live corruption (e.g. wiped dashboard) | **Yes** |

Without `FORCE=1`, import succeeds but **skips** objects that already exist; live
dashboards keep UI edits and do not pick up ndjson changes.

### Protected fields

Some metadata is **not** overwritten on import even with `FORCE=1`:

- `accessControl` (e.g. `write_restricted`) set on a live object may persist until the
  owner clears it or the object is deleted and re-imported.

If redeploy does not clear access restrictions, delete the dashboard in Kibana (as owner),
then `make deploy-kibana FORCE=1`.

### Verify after deploy

```bash
source .env
KB_BASE="${KB_ENDPOINT%/}/s/${KB_SPACE}"

# Saved Objects API — object exists
curl -s "${KB_BASE}/api/saved_objects/dashboard/ce6e34c0-ae6d-11ec-9a01-6da5271d9a1d" \
  -H "Authorization: ApiKey ${ES_API_KEY_ENCODED}" -H "kbn-xsrf: true" \
  | jq '{title: .attributes.title, panels: (.attributes.panelsJSON | fromjson | length)}'

# Dashboards API (Kibana 9.4+) — transform validation passes (HTTP 200)
curl -s -o /dev/null -w '%{http_code}\n' \
  "${KB_BASE}/api/dashboards/ce6e34c0-ae6d-11ec-9a01-6da5271d9a1d" \
  -H "Authorization: ApiKey ${ES_API_KEY_ENCODED}" \
  -H "kbn-xsrf: true" \
  -H "x-elastic-internal-origin: kibana"
```

Expect `200` from both. A `400` from `/api/dashboards` with an `Invalid response` message
means the ndjson contains config the 9.4 transforms layer cannot round-trip (see below).

______________________________________________________________________

## Kibana 9.4 UI saves

From Kibana 9.4, dashboard **Save** in the UI routes through the [Dashboards API transforms layer](https://www.elastic.co/search-labs/blog/kibana-dashboards-as-code-terraform-api).
Config that fails validation produces a blank toast (`Dashboard '...' was not saved. Error:`)
with no detail; check **DevTools → Network** for the real `400` body, or run the
`/api/dashboards/{id}` check above.

Known constraints for this project's dashboards (fixed in v1.11.1 unless noted):

| Issue | Mitigation |
| ----- | ---------- |
| Legacy `embeddableConfig.drilldowns` arrays with orphaned `dashboardRefName` | Use `enhancements.dynamicActions` with explicit `config.dashboardId` and matching `references` entry |
| Dashboard drilldown on **saved-search** panels | Not representable in 9.4 schema; use Lens/ES\|QL table or URL drilldown instead ([#17](https://github.com/face0b1101/adsb-demo/issues/17)) |
| Self-referencing drilldowns (Detail → Detail) | Remove; no useful navigation |
| `write_restricted` access control | Removed from source; clear on live deployments manually if import does not drop it |

**Do not** switch deploy to the new `POST /api/dashboards` API or Terraform provider yet:
the tech-preview API strips unsupported panel types (Maps, Links) from this project's dashboards.
Keep the ndjson + Saved Objects import pipeline.

______________________________________________________________________

## Typical workflow

```text
1. Edit dashboard in Kibana UI (space: adsb)
2. Save — confirm no error toast; if save fails, fix config or export before redeploy overwrites
3. Export saved objects → replace adsb-saved-objects.ndjson
4. Validate JSON + dashboard IDs
5. Commit ndjson + CHANGELOG [Unreleased]
6. make deploy-kibana FORCE=1   (other environments / teammates)
7. Release when ready           (see RELEASING.md)
```

For map-only or panel tweaks another author already made in git, skip steps 1–3 and pull
then `make deploy-kibana FORCE=1`.

______________________________________________________________________

## Related

- [`DEVELOPMENT.md`](DEVELOPMENT.md) — Make targets, Docker, post-change checklist
- [`testing-api.md`](testing-api.md) — `KB_BASE`, API headers, curl patterns
- [`RELEASING.md`](RELEASING.md) — version bumps and GitHub releases
- [`known-quirks.md`](known-quirks.md) — workflows, cases, ILM (not dashboard-specific)
