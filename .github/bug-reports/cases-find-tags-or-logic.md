# [Cases] `_find` API `tags` parameter uses OR logic with no AND option

## Describe the bug

When passing multiple `tags` values to `GET /api/cases/_find`, the API returns cases matching **any** of the specified tags (OR logic) rather than cases matching **all** of them (AND logic). The [API documentation](https://www.elastic.co/docs/api/doc/kibana/operation/operation-findcasesdefaultspace) does not specify which behaviour applies — it simply says "Filters the returned cases by tags."

This makes it impossible to filter cases that have a specific combination of tags, which is a common requirement for programmatic deduplication.

## To reproduce

1. Create two cases with different tags:

```sh
# Case A: tags ["squawk-7500", "icao24:abc123"]
# Case B: tags ["squawk-7500", "icao24:def456"]
```

2. Query for cases matching both `squawk-7500` AND `icao24:abc123`:

```sh
curl -s "$KB_BASE/api/cases/_find?tags=squawk-7500&tags=icao24:abc123&perPage=10" \
  -H "Authorization: ApiKey $API_KEY" \
  -H "kbn-xsrf: true"
```

3. Both Case A and Case B are returned (OR logic), even though only Case A has both tags.

## Expected behaviour

Either:
- Multiple `tags` values should use AND logic by default (matching cases that have **all** specified tags), or
- A `tagsOperator` parameter should be available to choose between `AND` and `OR` (similar to how Elasticsearch query operators work), or
- The OR behaviour should be explicitly documented

## Actual behaviour

Multiple `tags` values use OR logic — any case matching at least one of the specified tags is returned. This is not documented.

## Impact

This breaks deduplication workflows that rely on tag combinations to identify unique cases. For example, a workflow that creates one case per aircraft (tagged `icao24:<hex>`) for a specific alert type (tagged `squawk-7500`) cannot use `_find` with both tags to check for an existing case — it incorrectly matches unrelated cases that share the `squawk-7500` tag.

## Workaround

Use a single composite tag that encodes the uniqueness constraint (e.g. `icao24:abc123` alone) instead of relying on multiple tag filters.

## Environment

- **Kibana version**: 9.3.1
- **Deployment type**: Elastic Cloud Hosted (Azure UK South)
- **Cases owner**: `observability`
