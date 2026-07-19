# infra-utm-redteam-lab
# One-command, hands-off red team lab on UTM (Apple Silicon).

SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help preflight up provision configure status ssh down destroy lint test

# Allow `make ssh attacker` (bare VM name) alongside `make ssh VM=attacker`.
# When ssh is the goal, the remaining goals are the VM name: capture them and
# stub each out as a no-op target so make does not fail with "no rule to make
# target". Guarded on ssh being the first goal so typos on other targets still
# error normally. (A VM must therefore not share a name with a make target.)
ifeq ($(firstword $(MAKECMDGOALS)),ssh)
SSH_ARGS := $(filter-out ssh,$(MAKECMDGOALS))
ifneq ($(SSH_ARGS),)
.PHONY: $(SSH_ARGS)
$(eval $(SSH_ARGS):;@:)
endif
endif

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

up: ## Full hands-off deploy: preflight, create VMs, configure with Ansible
	@scripts/up.sh

preflight: ## Check macOS, UTM, and required tools; generate SSH key
	@scripts/preflight.sh

provision: ## Create and boot the VMs only (no Ansible)
	@scripts/up.sh --provision-only

configure: ## Run Ansible against already-running VMs
	@scripts/up.sh --configure-only

status: ## Show status of all lab VMs
	@scripts/status.sh

ssh: ## SSH into a VM: make ssh attacker
	@scripts/ssh.sh $(or $(VM),$(SSH_ARGS))

down: ## Stop all lab VMs (keeps them for later)
	@scripts/down.sh

destroy: ## Stop and delete all lab VMs and generated artifacts
	@scripts/destroy.sh

test: ## Run the shell unit tests
	@tests/parse-vm-entry.sh

lint: ## Syntax-check scripts and Ansible
	@bash -n scripts/*.sh tests/*.sh && echo "shell OK"
	@command -v ansible-lint >/dev/null && ansible-lint ansible/ || echo "ansible-lint not installed, skipping"
