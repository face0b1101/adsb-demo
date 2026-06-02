# Elastic Skills & MCP Servers

This project relies heavily on Elasticsearch, Kibana, and Elastic Cloud APIs.
Before starting any Elastic-related task, check for available agent skills
and MCP servers — they contain up-to-date API patterns, best practices, and
tooling that will improve the quality of your output.

## Skills

Look for installed Elastic skills covering Elasticsearch, Kibana, Cloud,
Observability, and Security. Skills are self-describing — read their
`SKILL.md` to understand scope and activation triggers. Relevant skill
categories for this project include:

- **Elasticsearch** — REST API patterns, Query DSL, ES|QL, index management,
  ingest pipelines, auth, RBAC, troubleshooting
- **Kibana** — dashboards, alerting rules, connectors, Agent Builder, Workflows,
  Streams, Vega visualisations
- **Cloud** — project provisioning, API keys, network security
- **Observability** — SLOs, logs, EDOT instrumentation
- **Security** — detection rules, alert triage, case management

If a skill exists for the task at hand, read and follow it before falling back
to general knowledge.

## MCP Servers

An **Elastic Docs** MCP server may be available (via IDE marketplace plugin or
user configuration). It provides tools to search and retrieve Elastic product
documentation published at elastic.co/docs. Prefer its `search_docs` tool over
a general web search for any Elastic-specific query.

## Precedence

When sources overlap, prefer **project-specific conventions** in `AGENTS.md`
(e.g. `ES_API_KEY_ENCODED`, `KB_BASE`, workflow YAML patterns), then
**skills** for canonical API reference and best practices, then the **MCP docs
server** for latest documentation lookups.
