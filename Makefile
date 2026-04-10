# Makefile for deploying the Flux Operator

# Prerequisites:
# - Kubectl
# - Helm
# - Flux CLI

SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

REPOSITORY ?= https://github.com/controlplaneio-fluxcd/d2-fleet
REGISTRY ?= ghcr.io/controlplaneio-fluxcd/d2-fleet

.PHONY: all
all: push bootstrap-staging

##@ General

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Artifacts

push: ## Push the Kubernetes manifests to Github Container Registry.
	flux push artifact oci://$(REGISTRY):latest \
	  --path=./ \
	  --source=$(REPOSITORY) \
	  --revision="$$(git branch --show-current)@sha1:$$(git rev-parse HEAD)"

##@ Flux

bootstrap-staging: ## Deploy Flux Operator on the staging Kubernetes cluster.
	@test $${GITHUB_TOKEN?Environment variable not set}

	helm install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
	  --namespace flux-system \
	  --create-namespace \
	  -f clusters/staging/flux-system/flux-operator-values.yaml \
	  --wait

	kubectl -n flux-system create secret docker-registry ghcr-auth \
	  --docker-server=ghcr.io \
	  --docker-username=flux \
	  --docker-password=$$GITHUB_TOKEN

	kubectl apply -f clusters/staging/flux-system/flux-instance.yaml

	kubectl -n flux-system wait fluxinstance/flux --for=condition=Ready --timeout=5m

bootstrap-production: ## Deploy Flux Operator on the production Kubernetes cluster.
	@test $${GITHUB_TOKEN?Environment variable not set}

	helm install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
	  --namespace flux-system \
	  --create-namespace \
	  -f clusters/prod-eu/flux-system/flux-operator-values.yaml \
	  --wait

	kubectl -n flux-system create secret docker-registry ghcr-auth \
	  --docker-server=ghcr.io \
	  --docker-username=flux \
	  --docker-password=$$GITHUB_TOKEN

	kubectl apply -f clusters/prod-eu/flux-system/flux-instance.yaml

	kubectl -n flux-system wait fluxinstance/flux --for=condition=Ready --timeout=5m

bootstrap-update: ## Deploy Flux Operator on the image update automation Kubernetes cluster.
	@test $${GITHUB_TOKEN?Environment variable not set for GHCR}
	@test $${GH_UPDATE_TOKEN?Environment variable not set for GitHub repos}

	helm install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
	  --namespace flux-system \
	  --create-namespace \
	  --set multitenancy.enabled=true \
	  --wait

	kubectl -n flux-system create secret docker-registry ghcr-auth \
	  --docker-server=ghcr.io \
	  --docker-username=flux \
	  --docker-password=$$GITHUB_TOKEN

	kubectl -n flux-system create secret generic github-auth \
	  --from-literal=username=flux \
	  --from-literal=password=$$GH_UPDATE_TOKEN

	kubectl apply -f clusters/update/flux-system/flux-instance.yaml

	kubectl -n flux-system wait fluxinstance/flux --for=condition=Ready --timeout=5m
