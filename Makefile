SHELL        := /bin/bash
CLUSTER_NAME ?= hcl-dx
CONFIG_FILE  := .k3d-config.env

.DEFAULT_GOAL := menu

-include $(CONFIG_FILE)

.PHONY: menu check-prereqs analyze-resources start stop \
        install-k3d configure-k3d uninstall-k3d clean-k3d \
        install-kubectl configure-kubectl uninstall-kubectl clean-kubectl \
        install-helm configure-helm uninstall-helm clean-helm \
        install-k9s configure-k9s uninstall-k9s clean-k9s \
        install-all uninstall-all

# ── Menu ───────────────────────────────────────────────────────────────────────

menu: ## Show interactive target menu (default)
	@bash scripts/menu.sh

# ── Prerequisites ─────────────────────────────────────────────────────────────

check-prereqs: ## Check for Docker, curl, make; offer to install missing tools
	@bash scripts/check-prereqs.sh

# ── Resource Analysis ──────────────────────────────────────────────────────────

analyze-resources: ## Detect system resources; recommend and save k3d settings
	@bash scripts/analyze-resources.sh

# ── Cluster Lifecycle ──────────────────────────────────────────────────────────

start: ## Start the k3d cluster
	k3d cluster start $(CLUSTER_NAME)

stop: ## Stop the k3d cluster and free CPU/RAM
	k3d cluster stop $(CLUSTER_NAME)

# ── k3d ───────────────────────────────────────────────────────────────────────

install-k3d: ## Download and install the k3d binary
	@bash scripts/install-k3d.sh

configure-k3d: $(CONFIG_FILE) ## Create the k3d cluster from .k3d-config.env settings
	@CLUSTER_NAME=$(CLUSTER_NAME) bash scripts/configure-k3d.sh

uninstall-k3d: ## Delete the k3d cluster and remove the k3d binary
	@k3d cluster delete $(CLUSTER_NAME) 2>/dev/null || true
	@sudo rm -f /usr/local/bin/k3d
	@echo "k3d cluster deleted and binary removed."

clean-k3d: ## Remove k3d configuration and generated cluster files
	@rm -f $(CONFIG_FILE) config/k3d-cluster.yaml
	@echo "Removed k3d configuration files."

# ── kubectl ───────────────────────────────────────────────────────────────────

install-kubectl: ## Download and install kubectl
	@bash scripts/install-kubectl.sh

configure-kubectl: ## Set kubectl context and install shell completions
	@CLUSTER_NAME=$(CLUSTER_NAME) bash scripts/configure-kubectl.sh

uninstall-kubectl: ## Remove the kubectl binary
	@sudo rm -f /usr/local/bin/kubectl
	@echo "kubectl removed."

clean-kubectl: ## Remove kubectl shell completions
	@sudo rm -f /etc/bash_completion.d/kubectl
	@rm -f $(HOME)/.config/fish/completions/kubectl.fish
	@echo "kubectl completions removed."

# ── Helm ──────────────────────────────────────────────────────────────────────

install-helm: ## Download and install Helm
	@bash scripts/install-helm.sh

configure-helm: ## Add Helm repositories and install shell completions
	@bash scripts/configure-helm.sh

uninstall-helm: ## Remove the Helm binary
	@sudo rm -f /usr/local/bin/helm
	@echo "Helm removed."

clean-helm: ## Remove Helm repositories and shell completions
	@helm repo remove bitnami 2>/dev/null || true
	@sudo rm -f /etc/bash_completion.d/helm
	@rm -f $(HOME)/.config/fish/completions/helm.fish
	@echo "Helm repositories and completions removed."

# ── k9s ───────────────────────────────────────────────────────────────────────

install-k9s: ## Download and install k9s
	@bash scripts/install-k9s.sh

configure-k9s: ## Write k9s default config and install shell completions
	@bash scripts/configure-k9s.sh

uninstall-k9s: ## Remove the k9s binary
	@sudo rm -f /usr/local/bin/k9s
	@echo "k9s removed."

clean-k9s: ## Remove k9s configuration directory and shell completions
	@rm -rf $(HOME)/.config/k9s
	@sudo rm -f /etc/bash_completion.d/k9s
	@rm -f $(HOME)/.config/fish/completions/k9s.fish
	@echo "k9s configuration removed."

# ── Pipelines ─────────────────────────────────────────────────────────────────

_INSTALL_DEPS   := check-prereqs \
                   install-k3d configure-k3d \
                   install-kubectl configure-kubectl \
                   install-helm configure-helm \
                   install-k9s configure-k9s

_UNINSTALL_DEPS := clean-k9s uninstall-k9s \
                   clean-helm uninstall-helm \
                   clean-kubectl uninstall-kubectl \
                   clean-k3d uninstall-k3d

install-all: $(_INSTALL_DEPS) ## Full install pipeline in dependency order

uninstall-all: $(_UNINSTALL_DEPS) ## Full uninstall pipeline in reverse order

# ── Guards ────────────────────────────────────────────────────────────────────

$(CONFIG_FILE):
	@echo "Error: $(CONFIG_FILE) not found. Run 'make analyze-resources' first." >&2
	@exit 1
