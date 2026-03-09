#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------

FORCE=false
SELECTED_GROUPS=""
ALL_GROUPS="indices enrich pipelines kibana workflows agents"

usage() {
  cat <<EOF
Usage: ./setup.sh [OPTIONS]

Set up Elasticsearch indices, enrich policies, pipelines, Kibana objects,
AI agents, and workflows for the ADS-B demo.

Options:
  --only GROUP[,GROUP]  Run only the specified groups (comma-separated).
                        Available groups: ${ALL_GROUPS}
  --force               Overwrite existing resources instead of skipping them.
  --help                Show this help message.

Examples:
  ./setup.sh                         Run all groups (skip existing by default)
  ./setup.sh --only agents,workflows Re-deploy agents and workflows only
  ./setup.sh --only kibana --force   Reset dashboards to source-controlled versions
  ./setup.sh --force                 Overwrite everything
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=true; shift ;;
    --only)  SELECTED_GROUPS="$2"; shift 2 ;;
    --help)  usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

if [[ -z "$SELECTED_GROUPS" ]]; then
  SELECTED_GROUPS="$ALL_GROUPS"
else
  SELECTED_GROUPS="${SELECTED_GROUPS//,/ }"
  for g in $SELECTED_GROUPS; do
    if ! echo "$ALL_GROUPS" | grep -qw "$g"; then
      echo "ERROR: Unknown group '$g'. Available: $ALL_GROUPS" >&2
      exit 1
    fi
  done
fi

group_enabled() { echo "$SELECTED_GROUPS" | grep -qw "$1"; }

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

if [[ -f .env ]]; then
  set -a; source .env; set +a
else
  echo "ERROR: .env file not found in $SCRIPT_DIR" >&2
  echo "Copy .env.example to .env and fill in your credentials first." >&2
  exit 1
fi

for var in ES_ENDPOINT ES_API_KEY_ENCODED KB_ENDPOINT; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set. Check your .env file." >&2
    exit 1
  fi
done

BASE="${ES_ENDPOINT%/}"
KB_BASE="${KB_ENDPOINT%/}"

# ---------------------------------------------------------------------------
# Step counting
# ---------------------------------------------------------------------------

declare -A GROUP_STEPS=(
  [indices]=6
  [enrich]=4
  [pipelines]=2
  [kibana]=1
  [agents]=2
  [workflows]=5
)

TOTAL=0
for g in $SELECTED_GROUPS; do
  TOTAL=$((TOTAL + GROUP_STEPS[$g]))
done

STEP=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

step_label() {
  STEP=$((STEP + 1))
  echo "[$STEP/$TOTAL] $1 ..."
}

curl_es() {
  curl -s -w '\n%{http_code}' \
    -H "Authorization: ApiKey $ES_API_KEY_ENCODED" "$@"
}

curl_kb() {
  curl -s -w '\n%{http_code}' \
    -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
    -H "kbn-xsrf: true" "$@"
}

curl_kb_wf() {
  curl -s -w '\n%{http_code}' \
    -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
    -H "kbn-xsrf: true" \
    -H "x-elastic-internal-origin: kibana" "$@"
}

parse_response() {
  local body http_code
  body=$(sed '$d' <<< "$1")
  http_code=$(tail -1 <<< "$1")
  echo "$body"
  return 0
}

http_code_of() {
  tail -1 <<< "$1"
}

run_curl() {
  local label="$1"; shift
  step_label "$label"

  local tmpfile
  tmpfile=$(mktemp)
  local http_code
  http_code=$(curl -s -w '%{http_code}' -o "$tmpfile" \
    -H "Authorization: ApiKey $ES_API_KEY_ENCODED" "$@")

  if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
    echo "  FAILED (HTTP $http_code):" >&2
    cat "$tmpfile" >&2
    rm -f "$tmpfile"
    exit 1
  fi

  echo "  OK (HTTP $http_code)"
  rm -f "$tmpfile"
}

ndjson_doc_count() {
  local lines
  lines=$(wc -l < "$1" | tr -d ' ')
  echo $((lines / 2))
}

index_doc_count() {
  local resp
  resp=$(curl_es -X GET "$BASE/$1/_count" 2>/dev/null || echo '{"count":-1}')
  local body
  body=$(parse_response "$resp")
  python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('count',-1))" "$body" 2>/dev/null || echo "-1"
}

# ---------------------------------------------------------------------------
# Group: indices
# ---------------------------------------------------------------------------

setup_index() {
  local index_name="$1" mapping_file="$2" data_file="$3" label="$4"

  step_label "Creating $label index"

  local head_code
  head_code=$(curl -s -o /dev/null -w '%{http_code}' \
    -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
    -I "$BASE/$index_name")

  if [[ "$head_code" == "200" ]]; then
    if [[ "$FORCE" == "true" ]]; then
      echo "  Index exists — deleting (--force)"
      curl_es -X DELETE "$BASE/$index_name" > /dev/null 2>&1
      local tmpfile
      tmpfile=$(mktemp)
      local create_code
      create_code=$(curl -s -w '%{http_code}' -o "$tmpfile" \
        -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
        -X PUT "$BASE/$index_name" \
        -H "Content-Type: application/json" \
        -d "@$mapping_file")
      if [[ "$create_code" -lt 200 || "$create_code" -ge 300 ]]; then
        echo "  FAILED (HTTP $create_code):" >&2
        cat "$tmpfile" >&2
        rm -f "$tmpfile"
        exit 1
      fi
      echo "  Recreated (HTTP $create_code)"
      rm -f "$tmpfile"
    else
      echo "  Already exists — skipping creation"
    fi
  else
    local tmpfile
    tmpfile=$(mktemp)
    local create_code
    create_code=$(curl -s -w '%{http_code}' -o "$tmpfile" \
      -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
      -X PUT "$BASE/$index_name" \
      -H "Content-Type: application/json" \
      -d "@$mapping_file")
    if [[ "$create_code" -lt 200 || "$create_code" -ge 300 ]]; then
      echo "  FAILED (HTTP $create_code):" >&2
      cat "$tmpfile" >&2
      rm -f "$tmpfile"
      exit 1
    fi
    echo "  Created (HTTP $create_code)"
    rm -f "$tmpfile"
  fi

  step_label "Loading $label reference data"

  if [[ "$FORCE" == "true" ]]; then
    echo "  Loading unconditionally (--force)"
  else
    local expected actual
    expected=$(ndjson_doc_count "$data_file")
    actual=$(index_doc_count "$index_name")
    if [[ "$actual" == "$expected" ]]; then
      echo "  Reference data already loaded ($actual documents) — skipping"
      step_label "Refreshing $label index"
      echo "  Skipped (data unchanged)"
      return 0
    fi
    echo "  Document count differs (index: $actual, file: $expected) — reloading"
  fi

  local bulk_tmp bulk_code
  bulk_tmp=$(mktemp)
  bulk_code=$(curl -s -w '%{http_code}' -o "$bulk_tmp" \
    -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
    -X POST "$BASE/$index_name/_bulk" \
    -H "Content-Type: application/x-ndjson" \
    --data-binary "@$data_file")

  if [[ "$bulk_code" -lt 200 || "$bulk_code" -ge 300 ]]; then
    echo "  FAILED (HTTP $bulk_code):" >&2
    cat "$bulk_tmp" >&2
    rm -f "$bulk_tmp"
    exit 1
  fi
  echo "  OK (HTTP $bulk_code)"
  rm -f "$bulk_tmp"

  step_label "Refreshing $label index"
  local ref_tmp ref_code
  ref_tmp=$(mktemp)
  ref_code=$(curl -s -w '%{http_code}' -o "$ref_tmp" \
    -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
    -X POST "$BASE/$index_name/_refresh")
  if [[ "$ref_code" -lt 200 || "$ref_code" -ge 300 ]]; then
    echo "  FAILED (HTTP $ref_code):" >&2
    cat "$ref_tmp" >&2
    rm -f "$ref_tmp"
    exit 1
  fi
  echo "  OK (HTTP $ref_code)"
  rm -f "$ref_tmp"
}

setup_indices() {
  setup_index \
    "geo.shapes-world.countries-50m" \
    "elasticsearch/indices/geo-shapes-world-countries-50m-mapping.json" \
    "data/geo-shapes-world-countries-50m-data.json" \
    "geo shapes"

  setup_index \
    "adsb-airports-geo" \
    "elasticsearch/indices/adsb-airports-geo-mapping.json" \
    "data/adsb-airports-geo-data.ndjson" \
    "airports"
}

# ---------------------------------------------------------------------------
# Group: enrich
# ---------------------------------------------------------------------------

setup_enrich_policy() {
  local policy_name="$1" policy_file="$2" label="$3"

  step_label "Creating $label enrich policy"

  local check_resp check_code
  check_resp=$(curl_es -X GET "$BASE/_enrich/policy/$policy_name" 2>/dev/null)
  check_code=$(http_code_of "$check_resp")

  if [[ "$check_code" == "200" ]]; then
    if [[ "$FORCE" == "true" ]]; then
      echo "  Policy exists — deleting (--force)"
      curl_es -X DELETE "$BASE/_enrich/policy/$policy_name" > /dev/null 2>&1
    else
      echo "  Already exists — skipping"
      step_label "Executing $label enrich policy"
      echo "  Skipped (policy unchanged)"
      return 0
    fi
  fi

  local tmp_file create_code
  tmp_file=$(mktemp)
  create_code=$(curl -s -w '%{http_code}' -o "$tmp_file" \
    -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
    -X PUT "$BASE/_enrich/policy/$policy_name" \
    -H "Content-Type: application/json" \
    -d "@$policy_file")

  if [[ "$create_code" -lt 200 || "$create_code" -ge 300 ]]; then
    echo "  FAILED (HTTP $create_code):" >&2
    cat "$tmp_file" >&2
    rm -f "$tmp_file"
    exit 1
  fi
  echo "  OK (HTTP $create_code)"
  rm -f "$tmp_file"

  step_label "Executing $label enrich policy"
  local exec_tmp exec_code
  exec_tmp=$(mktemp)
  exec_code=$(curl -s -w '%{http_code}' -o "$exec_tmp" \
    -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
    -X POST "$BASE/_enrich/policy/$policy_name/_execute")

  if [[ "$exec_code" -lt 200 || "$exec_code" -ge 300 ]]; then
    echo "  FAILED (HTTP $exec_code):" >&2
    cat "$exec_tmp" >&2
    rm -f "$exec_tmp"
    exit 1
  fi
  echo "  OK (HTTP $exec_code)"
  rm -f "$exec_tmp"
}

setup_enrich() {
  setup_enrich_policy \
    "opensky-geo-enrich-50m" \
    "elasticsearch/enrich/adsb-geo-enrich-policy.json" \
    "geo-shape"

  setup_enrich_policy \
    "adsb-airport-proximity" \
    "elasticsearch/enrich/adsb-airport-enrich-policy.json" \
    "airport proximity"
}

# ---------------------------------------------------------------------------
# Group: pipelines
# ---------------------------------------------------------------------------

setup_pipelines() {
  run_curl "Creating ingest pipeline" \
    -X PUT "$BASE/_ingest/pipeline/demo-aircraft-adsb.opensky" \
    -H "Content-Type: application/json" \
    -d @elasticsearch/pipelines/adsb-ingest-pipeline.json

  run_curl "Creating index template" \
    -X PUT "$BASE/_index_template/demos-aircraft-adsb" \
    -H "Content-Type: application/json" \
    -d @elasticsearch/indices/adsb-index-template.json
}

# ---------------------------------------------------------------------------
# Group: kibana
# ---------------------------------------------------------------------------

setup_kibana() {
  STEP=$((STEP + 1))

  local overwrite_param=""
  if [[ "$FORCE" == "true" ]]; then
    overwrite_param="?overwrite=true"
    echo "[$STEP/$TOTAL] Importing Kibana saved objects (--force: overwriting existing) ..."
  else
    echo "[$STEP/$TOTAL] Importing Kibana saved objects ..."
  fi

  local import_tmp import_http
  import_tmp=$(mktemp)
  import_http=$(curl -s -w '%{http_code}' -o "$import_tmp" \
    -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
    -X POST "$KB_BASE/api/saved_objects/_import${overwrite_param}" \
    -H "kbn-xsrf: true" \
    -F "file=@elasticsearch/kibana/adsb-saved-objects.ndjson")

  if [[ "$import_http" -lt 200 || "$import_http" -ge 300 ]]; then
    echo "  FAILED (HTTP $import_http):" >&2
    cat "$import_tmp" >&2
    rm -f "$import_tmp"
    exit 1
  fi

  local import_success
  import_success=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('success',True))" < "$import_tmp" || echo "True")

  if [[ "$import_success" == "False" ]]; then
    if [[ "$FORCE" == "true" ]]; then
      echo "  PARTIAL FAILURE (HTTP $import_http):" >&2
      python3 -c "
import json,sys
d=json.load(sys.stdin)
ok=d.get('successCount',0)
errs=d.get('errors',[])
print(f'  {ok} objects imported, {len(errs)} failed:')
for e in errs:
    title=e.get('meta',{}).get('title','?')
    etype=e.get('error',{}).get('type','?')
    refs=e.get('error',{}).get('references',[])
    ref_ids=', '.join(r.get('id','?') for r in refs)
    print(f'    - {e[\"type\"]} \"{title}\": {etype} (refs: {ref_ids})')
" < "$import_tmp" >&2
      rm -f "$import_tmp"
      exit 1
    else
      local ok_count skipped_count
      ok_count=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('successCount',0))" < "$import_tmp" 2>/dev/null || echo "0")
      skipped_count=$(python3 -c "import json,sys; print(len(json.load(sys.stdin).get('errors',[])))" < "$import_tmp" 2>/dev/null || echo "0")
      echo "  OK (HTTP $import_http) — $ok_count imported, $skipped_count skipped (already exist)"
      rm -f "$import_tmp"
      return 0
    fi
  fi

  echo "  OK (HTTP $import_http) — $(python3 -c "import json,sys; print(json.load(sys.stdin).get('successCount','?'))" < "$import_tmp" || echo "?") objects imported"
  rm -f "$import_tmp"
}

# ---------------------------------------------------------------------------
# Group: agents
# ---------------------------------------------------------------------------

deploy_agent() {
  local agent_id="$1" agent_file="$2" label="$3"

  step_label "Deploying $label"

  if [[ "$FORCE" == "true" ]]; then
    local agent_tmp agent_http
    agent_tmp=$(mktemp)
    agent_http=$(curl -s -w '%{http_code}' -o "$agent_tmp" \
      -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
      -X PUT "$KB_BASE/api/agent_builder/agents/$agent_id" \
      -H "kbn-xsrf: true" \
      -H "Content-Type: application/json" \
      -d "@$agent_file")

    if [[ "$agent_http" == "404" ]]; then
      agent_http=$(curl -s -w '%{http_code}' -o "$agent_tmp" \
        -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
        -X POST "$KB_BASE/api/agent_builder/agents" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -d "$(python3 -c "import json,sys; d=json.load(open('$agent_file')); d['id']='$agent_id'; json.dump(d,sys.stdout)")")
    fi

    if [[ "$agent_http" -lt 200 || "$agent_http" -ge 300 ]]; then
      echo "  FAILED (HTTP $agent_http):" >&2
      cat "$agent_tmp" >&2
      rm -f "$agent_tmp"
      exit 1
    fi
    echo "  OK (HTTP $agent_http)"
    rm -f "$agent_tmp"
  else
    local agent_tmp agent_http
    agent_tmp=$(mktemp)
    agent_http=$(curl -s -w '%{http_code}' -o "$agent_tmp" \
      -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
      -X POST "$KB_BASE/api/agent_builder/agents" \
      -H "kbn-xsrf: true" \
      -H "Content-Type: application/json" \
      -d "$(python3 -c "import json,sys; d=json.load(open('$agent_file')); d['id']='$agent_id'; json.dump(d,sys.stdout)")")

    if [[ "$agent_http" -ge 200 && "$agent_http" -lt 300 ]]; then
      echo "  Created (HTTP $agent_http)"
    elif [[ "$agent_http" == "409" ]] || { [[ "$agent_http" == "400" ]] && grep -q "already exists" "$agent_tmp"; }; then
      echo "  Already exists — skipping"
    else
      echo "  FAILED (HTTP $agent_http):" >&2
      cat "$agent_tmp" >&2
      rm -f "$agent_tmp"
      exit 1
    fi
    rm -f "$agent_tmp"
  fi
}

setup_agents() {
  deploy_agent \
    "adsb_agent" \
    "elasticsearch/agents/adsb-agent.json" \
    "ADS-B tracking agent"

  deploy_agent \
    "adsb_daily_briefing_agent" \
    "elasticsearch/agents/adsb-daily-briefing-agent.json" \
    "daily briefing agent"
}

# ---------------------------------------------------------------------------
# Group: workflows
# ---------------------------------------------------------------------------

setup_workflows() {
  # --- Enable Workflows feature flag ---
  step_label "Enabling Workflows feature flag"

  local wf_flag_tmp wf_flag_http
  wf_flag_tmp=$(mktemp)
  wf_flag_http=$(curl -s -w '%{http_code}' -o "$wf_flag_tmp" \
    -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
    -X POST "$KB_BASE/api/kibana/settings/workflows:ui:enabled" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{"value": true}')

  if [[ "$wf_flag_http" -lt 200 || "$wf_flag_http" -ge 300 ]]; then
    echo "  WARNING (HTTP $wf_flag_http): Could not enable workflows feature flag." >&2
    echo "  Enable it manually: Kibana > Stack Management > Advanced Settings > workflows:ui:enabled" >&2
    cat "$wf_flag_tmp" >&2
  else
    echo "  OK (HTTP $wf_flag_http)"
  fi
  rm -f "$wf_flag_tmp"

  # --- Create Slack connector (conditional) ---
  step_label "Configuring Slack connector"

  if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
    local slack_check slack_check_code
    local slack_connector_id="d85ca362-fb82-56f6-867c-4ef2c356d912"
    slack_check=$(curl_kb -X GET "$KB_BASE/api/actions/connector/$slack_connector_id" 2>/dev/null)
    slack_check_code=$(http_code_of "$slack_check")

    if [[ "$slack_check_code" == "200" ]]; then
      if [[ "$FORCE" == "true" ]]; then
        echo "  Connector exists — updating (--force)"
        local slack_tmp slack_http
        slack_tmp=$(mktemp)
        slack_http=$(curl -s -w '%{http_code}' -o "$slack_tmp" \
          -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
          -X PUT "$KB_BASE/api/actions/connector/$slack_connector_id" \
          -H "kbn-xsrf: true" \
          -H "Content-Type: application/json" \
          -d "$(python3 -c "
import json, os
print(json.dumps({
    'name': 'ADS-B Daily Briefing',
    'secrets': {'webhookUrl': os.environ['SLACK_WEBHOOK_URL']}
}))
")")
        if [[ "$slack_http" -lt 200 || "$slack_http" -ge 300 ]]; then
          echo "  WARNING (HTTP $slack_http): Could not update Slack connector." >&2
          cat "$slack_tmp" >&2
        else
          echo "  Updated (HTTP $slack_http)"
        fi
        rm -f "$slack_tmp"
      else
        echo "  Already exists — skipping"
      fi
    else
      echo "  Creating Slack connector ..."
      local slack_tmp slack_http
      slack_tmp=$(mktemp)
      slack_http=$(curl -s -w '%{http_code}' -o "$slack_tmp" \
        -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
        -X POST "$KB_BASE/api/actions/connector/$slack_connector_id" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -d "$(python3 -c "
import json, os
print(json.dumps({
    'connector_type_id': '.slack',
    'name': 'ADS-B Daily Briefing',
    'secrets': {'webhookUrl': os.environ['SLACK_WEBHOOK_URL']}
}))
")")
      if [[ "$slack_http" -lt 200 || "$slack_http" -ge 300 ]]; then
        echo "  WARNING (HTTP $slack_http): Could not create Slack connector." >&2
        echo "  Configure it manually in Kibana > Stack Management > Connectors." >&2
        cat "$slack_tmp" >&2
      else
        echo "  Created (HTTP $slack_http)"
      fi
      rm -f "$slack_tmp"
    fi
  else
    echo "  Skipped (SLACK_WEBHOOK_URL not set)"
    echo "  To enable Slack notifications, add SLACK_WEBHOOK_URL to .env"
    echo "  or create the connector manually in Kibana > Stack Management > Connectors."
  fi

  # --- Deploy daily flight briefing workflow ---
  step_label "Deploying daily flight briefing workflow"

  local workflow_yaml
  workflow_yaml=$(python3 -c "
import json, re, os
with open('elasticsearch/workflows/daily-flight-briefing.yaml') as f:
    yaml_content = f.read()
yaml_content = yaml_content.replace('__KB_ENDPOINT__', os.environ.get('KB_ENDPOINT', '').rstrip('/'))
payload = {'yaml': yaml_content}
m = re.search(r'^name:\s*(.+)', yaml_content, re.MULTILINE)
if m:
    payload['name'] = m.group(1).strip()
print(json.dumps(payload))
")

  local wf_tmp
  wf_tmp=$(mktemp)

  local wf_search_http existing_wf_id=""
  wf_search_http=$(curl -s -w '%{http_code}' -o "$wf_tmp" \
    -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
    -X POST "$KB_BASE/api/workflows/search" \
    -H "kbn-xsrf: true" \
    -H "x-elastic-internal-origin: kibana" \
    -H "Content-Type: application/json" \
    -d '{"query": "Daily Flight Briefing", "limit": 1}')

  if [[ "$wf_search_http" -ge 200 && "$wf_search_http" -lt 300 ]]; then
    existing_wf_id=$(python3 -c "
import json, sys
data = json.load(sys.stdin)
workflows = data.get('workflows', data.get('results', []))
for w in workflows:
    if w.get('name') == 'Daily Flight Briefing':
        print(w['id'])
        break
" < "$wf_tmp" 2>/dev/null || true)
  fi

  local wf_http
  if [[ -n "$existing_wf_id" ]]; then
    if [[ "$FORCE" == "true" ]]; then
      echo "  Workflow exists — updating (--force)"
      wf_http=$(curl -s -w '%{http_code}' -o "$wf_tmp" \
        -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
        -X PUT "$KB_BASE/api/workflows/$existing_wf_id" \
        -H "kbn-xsrf: true" \
        -H "x-elastic-internal-origin: kibana" \
        -H "Content-Type: application/json" \
        -d "$workflow_yaml")
    else
      echo "  Already exists — skipping"
      rm -f "$wf_tmp"
    fi
  else
    wf_http=$(curl -s -w '%{http_code}' -o "$wf_tmp" \
      -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
      -X POST "$KB_BASE/api/workflows" \
      -H "kbn-xsrf: true" \
      -H "x-elastic-internal-origin: kibana" \
      -H "Content-Type: application/json" \
      -d "$workflow_yaml")
  fi

  if [[ "$wf_http" -lt 200 || "$wf_http" -ge 300 ]]; then
    echo "  FAILED (HTTP $wf_http):" >&2
    cat "$wf_tmp" >&2
    rm -f "$wf_tmp"
    exit 1
  fi

  local wf_id
  wf_id=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" < "$wf_tmp" 2>/dev/null || true)
  echo "  OK (HTTP $wf_http) — workflow ID: ${wf_id:-unknown}"
  rm -f "$wf_tmp"

  # --- Deploy ADS-B aggregate stats workflow ---
  step_label "Deploying ADS-B aggregate stats workflow"

  local agg_yaml
  agg_yaml=$(python3 -c "
import json, re
with open('elasticsearch/workflows/adsb-aggregate-stats.yaml') as f:
    yaml_content = f.read()
payload = {'yaml': yaml_content}
m = re.search(r'^name:\s*(.+)', yaml_content, re.MULTILINE)
if m:
    payload['name'] = m.group(1).strip()
print(json.dumps(payload))
")

  local agg_tmp
  agg_tmp=$(mktemp)

  local agg_search_http existing_agg_id=""
  agg_search_http=$(curl -s -w '%{http_code}' -o "$agg_tmp" \
    -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
    -X POST "$KB_BASE/api/workflows/search" \
    -H "kbn-xsrf: true" \
    -H "x-elastic-internal-origin: kibana" \
    -H "Content-Type: application/json" \
    -d '{"query": "ADS-B Aggregate Stats", "limit": 1}')

  if [[ "$agg_search_http" -ge 200 && "$agg_search_http" -lt 300 ]]; then
    existing_agg_id=$(python3 -c "
import json, sys
data = json.load(sys.stdin)
workflows = data.get('workflows', data.get('results', []))
for w in workflows:
    if w.get('name') == 'ADS-B Aggregate Stats':
        print(w['id'])
        break
" < "$agg_tmp" 2>/dev/null || true)
  fi

  local agg_http
  if [[ -n "$existing_agg_id" ]]; then
    if [[ "$FORCE" == "true" ]]; then
      echo "  Workflow exists — updating (--force)"
      agg_http=$(curl -s -w '%{http_code}' -o "$agg_tmp" \
        -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
        -X PUT "$KB_BASE/api/workflows/$existing_agg_id" \
        -H "kbn-xsrf: true" \
        -H "x-elastic-internal-origin: kibana" \
        -H "Content-Type: application/json" \
        -d "$agg_yaml")
    else
      echo "  Already exists — skipping"
      local agg_wf_id="$existing_agg_id"
      register_workflow_tool "$agg_wf_id"
      rm -f "$agg_tmp"
      return 0
    fi
  else
    agg_http=$(curl -s -w '%{http_code}' -o "$agg_tmp" \
      -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
      -X POST "$KB_BASE/api/workflows" \
      -H "kbn-xsrf: true" \
      -H "x-elastic-internal-origin: kibana" \
      -H "Content-Type: application/json" \
      -d "$agg_yaml")
  fi

  if [[ "$agg_http" -lt 200 || "$agg_http" -ge 300 ]]; then
    echo "  FAILED (HTTP $agg_http):" >&2
    cat "$agg_tmp" >&2
    rm -f "$agg_tmp"
    exit 1
  fi

  local agg_wf_id
  agg_wf_id=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" < "$agg_tmp" 2>/dev/null || true)
  echo "  OK (HTTP $agg_http) — workflow ID: ${agg_wf_id:-unknown}"

  register_workflow_tool "$agg_wf_id"
  rm -f "$agg_tmp"
}

register_workflow_tool() {
  local wf_id="$1"
  [[ -z "$wf_id" ]] && return 0

  step_label "Registering adsb-aggregate-stats workflow tool"

  local tool_payload
  tool_payload=$(python3 -c "
import json
print(json.dumps({
    'id': 'adsb-aggregate-stats',
    'description': 'Aggregates the last 24 hours of ADS-B data from demos-aircraft-adsb. Takes no parameters (fixed now-24h window).\n\nReturned aggregation keys:\n- unique_aircraft: cardinality of icao24\n- busiest_airports: top 10 by airport.iata_code\n- origin_countries: top 10 by origin_country\n- activity_breakdown: terms on airport.activity (arriving, departing, taxiing, overflight, at_airport — airport airspace zone only)\n- traffic_by_subregion: top 15 by geo.SUBREGION\n- traffic_by_continent: top 7 by geo.CONTINENT\n- ground_vs_airborne: terms on on_ground\n- emergency_squawks: named filters for 7500 (hijack), 7600 (radio failure), 7700 (general emergency)\n\nResults are at output.aggregations. Total document count is at hits.total.value. This is an async workflow — poll with platform.core.get_workflow_execution_status until complete.',
    'type': 'workflow',
    'tags': ['adsb', 'aggregation'],
    'configuration': {'workflow_id': '$wf_id'}
}))
")

  local tool_tmp tool_http
  tool_tmp=$(mktemp)
  tool_http=$(curl -s -w '%{http_code}' -o "$tool_tmp" \
    -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
    -X POST "$KB_BASE/api/agent_builder/tools" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d "$tool_payload")

  if [[ "$tool_http" -ge 200 && "$tool_http" -lt 300 ]]; then
    echo "  Workflow tool registered (HTTP $tool_http)"
  elif [[ "$tool_http" == "409" ]] || { [[ "$tool_http" == "400" ]] && grep -q "already exists" "$tool_tmp"; }; then
    if [[ "$FORCE" == "true" ]]; then
      local tool_update_payload
      tool_update_payload=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); [d.pop(k,None) for k in ('id','type')]; print(json.dumps(d))" "$tool_payload")
      tool_http=$(curl -s -w '%{http_code}' -o "$tool_tmp" \
        -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
        -X PUT "$KB_BASE/api/agent_builder/tools/adsb-aggregate-stats" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -d "$tool_update_payload")
      if [[ "$tool_http" -ge 200 && "$tool_http" -lt 300 ]]; then
        echo "  Workflow tool updated (HTTP $tool_http)"
      else
        echo "  WARNING: Could not update workflow tool (HTTP $tool_http)" >&2
        cat "$tool_tmp" >&2
      fi
    else
      echo "  Workflow tool already registered — skipping"
    fi
  else
    echo "  WARNING: Could not register workflow tool (HTTP $tool_http)" >&2
    cat "$tool_tmp" >&2
  fi
  rm -f "$tool_tmp"
}

# ---------------------------------------------------------------------------
# Run selected groups
# ---------------------------------------------------------------------------

echo "ADS-B Demo Setup"
echo "Groups: $SELECTED_GROUPS"
[[ "$FORCE" == "true" ]] && echo "Mode: --force (overwriting existing resources)"
echo ""

group_enabled "indices"   && setup_indices
group_enabled "enrich"    && setup_enrich
group_enabled "pipelines" && setup_pipelines
group_enabled "kibana"    && setup_kibana
group_enabled "workflows" && setup_workflows
group_enabled "agents"    && setup_agents

echo ""
echo "Setup complete."
