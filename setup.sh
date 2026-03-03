#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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

TOTAL=14
STEP=0
BASE="${ES_ENDPOINT%/}"
KB_BASE="${KB_ENDPOINT%/}"

run_curl() {
  local label="$1"; shift
  STEP=$((STEP + 1))
  echo "[$STEP/$TOTAL] $label ..."

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

run_curl "Creating geo shapes source index" \
  -X PUT "$BASE/geo.shapes-world.countries-50m" \
  -H "Content-Type: application/json" \
  -d @elasticsearch/geo-shapes-world-countries-50m-mapping.json

run_curl "Bulk-loading geo shapes data" \
  -X POST "$BASE/geo.shapes-world.countries-50m/_bulk" \
  -H "Content-Type: application/x-ndjson" \
  --data-binary @elasticsearch/geo-shapes-world-countries-50m-data.json

run_curl "Refreshing geo shapes index" \
  -X POST "$BASE/geo.shapes-world.countries-50m/_refresh"

run_curl "Creating enrich policy" \
  -X PUT "$BASE/_enrich/policy/opensky-geo-enrich-50m" \
  -H "Content-Type: application/json" \
  -d @elasticsearch/enrich-policy.json

run_curl "Executing enrich policy" \
  -X POST "$BASE/_enrich/policy/opensky-geo-enrich-50m/_execute"

run_curl "Creating airports source index" \
  -X PUT "$BASE/adsb-airports-geo" \
  -H "Content-Type: application/json" \
  -d @elasticsearch/adsb-airports-geo-mapping.json

run_curl "Bulk-loading airports data" \
  -X POST "$BASE/adsb-airports-geo/_bulk" \
  -H "Content-Type: application/x-ndjson" \
  --data-binary @elasticsearch/adsb-airports-geo-data.ndjson

run_curl "Refreshing airports index" \
  -X POST "$BASE/adsb-airports-geo/_refresh"

run_curl "Creating airport proximity enrich policy" \
  -X PUT "$BASE/_enrich/policy/adsb-airport-proximity" \
  -H "Content-Type: application/json" \
  -d @elasticsearch/adsb-airport-enrich-policy.json

run_curl "Executing airport proximity enrich policy" \
  -X POST "$BASE/_enrich/policy/adsb-airport-proximity/_execute"

run_curl "Creating ingest pipeline" \
  -X PUT "$BASE/_ingest/pipeline/demo-aircraft-adsb.opensky" \
  -H "Content-Type: application/json" \
  -d @elasticsearch/ingest-pipeline.json

run_curl "Creating index template" \
  -X PUT "$BASE/_index_template/demos-aircraft-adsb" \
  -H "Content-Type: application/json" \
  -d @elasticsearch/index-template.json

STEP=$((STEP + 1))
echo "[$STEP/$TOTAL] Importing Kibana saved objects (dashboards, data views) ..."

import_tmp=$(mktemp)
import_http=$(curl -s -w '%{http_code}' -o "$import_tmp" \
  -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
  -X POST "$KB_BASE/api/saved_objects/_import?overwrite=true" \
  -H "kbn-xsrf: true" \
  -F "file=@elasticsearch/adsb-saved-objects.ndjson")

if [[ "$import_http" -lt 200 || "$import_http" -ge 300 ]]; then
  echo "  FAILED (HTTP $import_http):" >&2
  cat "$import_tmp" >&2
  rm -f "$import_tmp"
  exit 1
fi

import_success=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('success',True))" < "$import_tmp" || echo "True")
if [[ "$import_success" == "False" ]]; then
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
fi

echo "  OK (HTTP $import_http) — $(python3 -c "import json,sys; print(json.load(sys.stdin).get('successCount','?'))" < "$import_tmp" || echo "?") objects imported"
rm -f "$import_tmp"

STEP=$((STEP + 1))
echo "[$STEP/$TOTAL] Deploying ADS-B tracking agent ..."

agent_tmp=$(mktemp)
agent_http=$(curl -s -w '%{http_code}' -o "$agent_tmp" \
  -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
  -X PUT "$KB_BASE/api/agent_builder/agents/adsb_agent" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d @elasticsearch/adsb-agent.json)

if [[ "$agent_http" == "404" ]]; then
  agent_http=$(curl -s -w '%{http_code}' -o "$agent_tmp" \
    -H "Authorization: ApiKey $ES_API_KEY_ENCODED" \
    -X POST "$KB_BASE/api/agent_builder/agents" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "import json,sys; d=json.load(open('elasticsearch/adsb-agent.json')); d['id']='adsb_agent'; json.dump(d,sys.stdout)")")
fi

if [[ "$agent_http" -lt 200 || "$agent_http" -ge 300 ]]; then
  echo "  FAILED (HTTP $agent_http):" >&2
  cat "$agent_tmp" >&2
  rm -f "$agent_tmp"
  exit 1
fi

echo "  OK (HTTP $agent_http)"
rm -f "$agent_tmp"

echo ""
echo "Elasticsearch setup complete."
