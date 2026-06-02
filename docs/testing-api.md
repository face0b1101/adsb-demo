# Testing via API

After editing workflows (`elasticsearch/workflows/`), agents (`elasticsearch/agents/`),
or aggregation queries, validate changes via the Elasticsearch and Kibana REST APIs.
All commands require `required_permissions: ["all"]` in sandboxed environments.

## Prerequisites

```sh
source .env   # provides ES_ENDPOINT, KB_ENDPOINT, ES_API_KEY_ENCODED

# Space-aware Kibana base URL (all Kibana API calls must use KB_BASE)
KB_BASE="${KB_ENDPOINT%/}"
[[ -n "${KB_SPACE:-}" ]] && KB_BASE="${KB_BASE}/s/${KB_SPACE}"
```

## Redeploy changed resources

```sh
./setup.sh --only agents,workflows --force
```

## Test an Elasticsearch query

Run the query body directly against ES to validate aggregations, painless scripts, and
mappings before deploying a workflow.

```sh
curl -s "${ES_ENDPOINT}/demos-aircraft-adsb/_search" \
  -H "Authorization: ApiKey ${ES_API_KEY_ENCODED}" \
  -H "Content-Type: application/json" \
  -d '{"size":0,"query":{...},"aggs":{...}}' | jq '.aggregations'
```

## Test a workflow

The Kibana Workflows API (Technical Preview) requires the extra header
`x-elastic-internal-origin: kibana` on every request.

```sh
# 1. Find workflow ID by name (list endpoint unchanged)
WF_ID=$(curl -s "${KB_BASE}/api/workflows" \
  -H "Authorization: ApiKey ${ES_API_KEY_ENCODED}" \
  -H "kbn-xsrf: true" \
  -H "x-elastic-internal-origin: kibana" \
  | jq -r '.results[] | select(.name=="My Workflow Name") | .id')

# 2. Run — NOTE: path changed in 9.4.x, now requires "workflow/" segment
EXEC_ID=$(curl -s -X POST "${KB_BASE}/api/workflows/workflow/${WF_ID}/run" \
  -H "Authorization: ApiKey ${ES_API_KEY_ENCODED}" \
  -H "kbn-xsrf: true" \
  -H "x-elastic-internal-origin: kibana" \
  -H "Content-Type: application/json" \
  -d '{"inputs":{}}' | jq -r '.workflowExecutionId')

# 3. Poll until status is "completed" or "failed"
curl -s "${KB_BASE}/api/workflows/executions/${EXEC_ID}" \
  -H "Authorization: ApiKey ${ES_API_KEY_ENCODED}" \
  -H "kbn-xsrf: true" \
  -H "x-elastic-internal-origin: kibana" \
  | jq '{status, duration, steps: [.stepExecutions[]? | {type: .stepType, status: .status}]}'

# 4. Inspect individual step output
STEP_ID=$(curl -s "${KB_BASE}/api/workflows/executions/${EXEC_ID}" \
  -H "Authorization: ApiKey ${ES_API_KEY_ENCODED}" \
  -H "kbn-xsrf: true" \
  -H "x-elastic-internal-origin: kibana" \
  | jq -r '.stepExecutions[0].id')

curl -s "${KB_BASE}/api/workflows/executions/${EXEC_ID}/step/${STEP_ID}" \
  -H "Authorization: ApiKey ${ES_API_KEY_ENCODED}" \
  -H "kbn-xsrf: true" \
  -H "x-elastic-internal-origin: kibana" | jq '.output'
```

For workflows with inputs, pass them in the run body:
`-d '{"inputs":{"icao24":"a1b2c3","callsign":"DAL123"}}'`

## Test an agent

Use the Agent Builder converse API to send a message and inspect the response.

```sh
curl -s -X POST "${KB_BASE}/api/agent_builder/converse" \
  -H "Authorization: ApiKey ${ES_API_KEY_ENCODED}" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{"agent_id":"${AGENT_ID}","input":"Your test prompt here"}' \
  | jq '{status, model: .model_usage.model, response: .response.message}'
```

## Side-effect awareness

Some workflows trigger real external actions when run:

| Workflow                           | Side effects                                  |
| ---------------------------------- | --------------------------------------------- |
| `adsb-aggregate-stats`             | None (read-only ES query)                     |
| `daily-flight-briefing`            | Sends Slack message, invokes AI agent         |
| `squawk-7500-enrich`               | External HTTP calls (adsbdb, adsb.lol, GNews) |
| `squawk-7500-hijack-investigation` | Creates Kibana case, may send Slack           |
| `squawk-7500-create-case`          | Creates or updates a Kibana case              |

Agent converse calls may invoke workflow tools and incur LLM costs.
