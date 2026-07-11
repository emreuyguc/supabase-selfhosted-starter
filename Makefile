.PHONY: validate render-readme render-dokploy generate-env backup-postgres backup-minio test-runtime typecheck-runtime test-smoke

validate:
	./scripts/validate.sh

render-readme:
	./scripts/render-readme.sh

render-dokploy:
	./scripts/render-dokploy.sh

generate-env:
	./scripts/generate-env.sh

backup-postgres:
	./scripts/backup-postgres.sh

backup-minio:
	./scripts/backup-minio.sh

test-runtime:
	npm --prefix tests/runtime test

typecheck-runtime:
	npm --prefix tests/runtime run typecheck

test-smoke:
	npm --prefix tests/runtime test
