VARIANT ?= internal-db
STORAGE ?= minio
OUTPUT ?=

.PHONY: render render-all render-template validate

render:
	../scripts/render-dokploy.sh --variant "$(VARIANT)" --storage "$(STORAGE)" $(if $(OUTPUT),--output "$(OUTPUT)")

render-template:
	../scripts/render-dokploy.sh --variant "$(VARIANT)" --storage "$(STORAGE)"

render-all:
	../scripts/render-dokploy.sh --all

validate:
	../scripts/validate.sh
