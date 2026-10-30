SHELL := /bin/bash
TF    ?= terraform
TF_DIR := terraform
AN_DIR := ansible

# Pass extra flags to ansible-playbook, e.g. make deploy ANSIBLE_ARGS="--tags kibana"
ANSIBLE_ARGS ?=
VAULT_ARGS   ?= --ask-vault-pass

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

# --- Setup ---------------------------------------------------------------------

.PHONY: deps
deps: ## Install Ansible collections
	cd $(AN_DIR) && ansible-galaxy collection install -r requirements.yml

.PHONY: vault
vault: ## Generate an encrypted vault.yml with random secrets
	scripts/generate-vault.sh

# --- Infrastructure -------------------------------------------------------------

.PHONY: init
init: ## terraform init
	$(TF) -chdir=$(TF_DIR) init

.PHONY: plan
plan: ## terraform plan
	$(TF) -chdir=$(TF_DIR) plan -out=tfplan

.PHONY: apply
apply: ## terraform apply (the saved plan)
	$(TF) -chdir=$(TF_DIR) apply tfplan

.PHONY: destroy
destroy: ## Tear everything down
	$(TF) -chdir=$(TF_DIR) destroy

# --- Configuration --------------------------------------------------------------

.PHONY: inventory
inventory: ## Show the hosts Ansible discovered
	cd $(AN_DIR) && ansible-inventory --graph

.PHONY: deploy
deploy: ## Configure the Elastic Stack
	cd $(AN_DIR) && ansible-playbook site.yml $(VAULT_ARGS) $(ANSIBLE_ARGS)

.PHONY: verify
verify: ## Smoke-test the running stack
	cd $(AN_DIR) && ansible-playbook verify.yml $(VAULT_ARGS) $(ANSIBLE_ARGS)

.PHONY: kibana
kibana: ## Open a tunnel to Kibana at https://localhost:5601
	@eval "$$($(TF) -chdir=$(TF_DIR) output -raw kibana_port_forward_command)"

# --- Quality --------------------------------------------------------------------

.PHONY: lint
lint: ## yamllint, ansible-lint, terraform fmt/validate, tflint
	yamllint .
	cd $(AN_DIR) && ansible-lint
	$(TF) -chdir=$(TF_DIR) fmt -check -recursive
	$(TF) -chdir=$(TF_DIR) init -backend=false -input=false >/dev/null
	$(TF) -chdir=$(TF_DIR) validate
	cd $(TF_DIR) && tflint --init && tflint

.PHONY: test
test: ## Offline tests: Terraform plan assertions + Ansible render/cert tests
	$(TF) -chdir=$(TF_DIR) init -backend=false -input=false >/dev/null
	$(TF) -chdir=$(TF_DIR) test
	cd tests/ansible && ANSIBLE_ROLES_PATH=../../$(AN_DIR)/roles ansible-playbook -i inventory/three-node.yml render_test.yml
	cd tests/ansible && ANSIBLE_ROLES_PATH=../../$(AN_DIR)/roles ansible-playbook -i inventory/single-node.yml render_test.yml

.PHONY: scan
scan: ## Secret scan (gitleaks) and IaC security scan (checkov)
	gitleaks detect --source . --redact --verbose
	checkov --directory $(TF_DIR) --quiet --compact
