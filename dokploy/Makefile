VARIANT ?= full
STORAGE ?= local
OUTPUT ?= dokploy/template.json

.PHONY: render render-all render-template validate

render:
	../scripts/render-dokploy.sh --variant $(VARIANT) --storage $(STORAGE) --output $(OUTPUT)

render-template:
	../scripts/render-dokploy.sh --variant $(VARIANT) --storage $(STORAGE) --output dokploy/template.json

render-all:
	../scripts/render-dokploy.sh --all

validate:
	../scripts/validate.sh
