# Используем python3.11, если он есть (в Astra Linux системный python3 — 3.7, он слишком старый).
PY    ?= $(shell command -v python3.11 >/dev/null 2>&1 && echo python3.11 || echo python3)
VENV  ?= .venv
IMAGE ?= ghcr.io/owner/k8s-demo
TAG   ?= dev
ENV   ?= dev
YAML  ?= /tmp/$(ENV).yaml

CLUSTER ?= k8s-demo
TOFU  ?= $(HOME)/.local/bin/tofu
TF_STATE ?= $(HOME)/.local/share/tofu/k8s-demo.tfstate
export TF_CLI_CONFIG_FILE = $(CURDIR)/infra/tofurc

.PHONY: help venv install lint fmt test test-docker build run \
        render lint-manifests iac-init iac-plan iac-apply iac-fmt iac-output \
        argocd-password apps secrets-edit docker-check cluster-stop cluster-start

help:
	@echo "Разработка:"
	@echo "  make venv install   - окружение и зависимости (python3.11)"
	@echo "  make test           - ruff + pytest локально"
	@echo "  make test-docker    - то же в контейнере"
	@echo "  make build TAG=x    - собрать образ"
	@echo "  make run            - запустить локально на :18080"
	@echo
	@echo "Манифесты (ENV=dev|prod):"
	@echo "  make render         - kustomize build overlays/\$$ENV"
	@echo "  make lint-manifests - render + kubeconform + kube-linter"
	@echo
	@echo "Инфраструктура (OpenTofu):"
	@echo "  make iac-init       - tofu init (state в $(TF_STATE))"
	@echo "  make iac-plan       - tofu plan"
	@echo "  make iac-apply      - tofu apply (кластер + addons)"
	@echo "  make iac-output     - tofu output"
	@echo
	@echo "GitOps/секреты:"
	@echo "  make apps           - Applications в Argo CD"
	@echo "  make argocd-password- пароль admin в UI Argo CD"
	@echo "  make secrets-edit   - правка секрета (ENV=dev|prod) через sops"
	@echo
	@echo "Стенд:"
	@echo "  make cluster-stop   - выключить кластер (состояние сохраняется)"
	@echo "  make cluster-start  - включить кластер и дождаться ноды"

venv:
	$(PY) -m venv $(VENV)
	$(VENV)/bin/pip install --upgrade pip

install: venv
	$(VENV)/bin/pip install -r requirements-dev.txt

lint:
	$(VENV)/bin/ruff check .
	$(VENV)/bin/ruff format --check .

fmt:
	$(VENV)/bin/ruff check --fix .
	$(VENV)/bin/ruff format .

test:
	$(VENV)/bin/ruff check .
	$(VENV)/bin/ruff format --check .
	$(VENV)/bin/pytest -q

test-docker:
	docker run --rm -v "$$PWD":/app -w /app python:3.11-slim \
		sh -c "pip install -q -r requirements-dev.txt && ruff check . && ruff format --check . && pytest -q"

build:
	docker build --build-arg VERSION=$(TAG) -t $(IMAGE):$(TAG) .

run:
	docker run --rm -p 18080:8080 $(IMAGE):$(TAG)

render:
	kustomize build deploy/overlays/$(ENV) > $(YAML)
	@echo "готово: $(YAML)"

lint-manifests: render
	kubeconform -strict -ignore-missing-schemas -summary $(YAML)
	kube-linter lint $(YAML)

iac-init:
	mkdir -p "$$(dirname $(TF_STATE))"
	cd infra && $(TOFU) init -backend-config=path=$(TF_STATE)

iac-plan: iac-init
	cd infra && $(TOFU) plan

iac-apply: iac-init
	cd infra && $(TOFU) apply

iac-fmt:
	cd infra && $(TOFU) fmt -recursive

iac-output:
	cd infra && $(TOFU) output

apps:
	kubectl -n argocd get applications

argocd-password:
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

secrets-edit:
	sops deploy/overlays/$(ENV)/sops-secret.enc.yaml

docker-check:
	@sg docker -c 'docker info >/dev/null && echo "docker доступен"'

# Стенд целиком — это один контейнер kind. Остановка сохраняет состояние на диске
# и освобождает память; запуск возвращает кластер, дальше Argo CD догоняет git сам.
# Важно: пока кластер остановлен, tofu plan/apply падают (провайдер не может
# прочитать kubeconfig из остановленного контейнера) — IaC работает на живом кластере.
cluster-stop:
	sg docker -c 'docker stop --time 60 $(CLUSTER)'

cluster-start:
	sg docker -c 'docker start $(CLUSTER)'
	@echo "ждём ноду..."
	@kubectl wait --for=condition=Ready node/$(CLUSTER)-control-plane --timeout=180s
