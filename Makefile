.PHONY: setup up down logs restart status clean help

setup:           ## Run Elasticsearch setup (indices, pipelines, dashboards)
	./setup.sh

up:              ## Start Logstash
	docker compose up -d

down:            ## Stop Logstash
	docker compose down

logs:            ## Tail Logstash logs
	docker compose logs -f logstash

restart:         ## Restart Logstash after config changes
	docker compose restart logstash

status:          ## Show Logstash pipeline status
	docker compose exec logstash curl -s localhost:9600/_node/pipelines?pretty

clean:           ## Stop Logstash and remove volumes
	docker compose down -v

help:            ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
