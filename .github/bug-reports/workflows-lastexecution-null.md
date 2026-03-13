# [Workflows] `lastExecution` on GET /api/workflows/{id} always returns `null`

## Describe the bug

After an alert-triggered workflow executes successfully, querying `GET /api/workflows/{id}` always returns `lastExecution: null`. This makes it impossible to determine when a workflow last ran without querying the execution history endpoint separately.

The workflow does execute — confirmed via `GET /api/workflowExecutions?workflowId={id}` which shows `status: "completed"` with correct timestamps.

## To reproduce

1. Deploy a workflow with an alert trigger
2. Create an alert rule with a `.workflows` system connector action targeting the workflow
3. Trigger the alert so the workflow executes
4. Confirm execution:

```sh
curl -s "$KB_BASE/api/workflowExecutions?workflowId=workflow-example-id&size=1" \
  -H "Authorization: ApiKey $API_KEY" \
  -H "kbn-xsrf: true" \
  -H "x-elastic-internal-origin: kibana"
```

Response shows the execution completed:

```json
{
  "results": [
    {
      "id": "c12fe9e3-401f-4d52-badf-9b91bf813c24",
      "status": "completed",
      "startedAt": "2026-03-13T16:11:56.806Z",
      "finishedAt": "2026-03-13T16:12:25.322Z",
      "duration": 28516,
      "triggeredBy": "alert"
    }
  ],
  "total": 62
}
```

5. Query the workflow definition:

```sh
curl -s "$KB_BASE/api/workflows/workflow-example-id" \
  -H "Authorization: ApiKey $API_KEY" \
  -H "kbn-xsrf: true" \
  -H "x-elastic-internal-origin: kibana" | jq '.lastExecution'
```

Returns `null`.

## Expected behaviour

`lastExecution` should reflect the most recent execution — at minimum the timestamp, status, and execution ID.

## Actual behaviour

`lastExecution` is always `null` regardless of how many times the workflow has executed.

## Environment

- **Kibana version**: 9.3.1
- **Deployment type**: Elastic Cloud Hosted (Azure UK South)
- **Workflow trigger type**: alert (via `.workflows` system connector)
- **Total executions observed**: 62 (all returning `null` for `lastExecution`)
