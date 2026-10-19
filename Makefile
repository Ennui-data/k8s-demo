# Используем python3.11, если он есть (в Astra Linux системный python3 — 3.7, он слишком старый).
PY    ?= $(shell command -v python3.11 >/dev/null 2>&1 && echo python3.11 || echo python3)
VENV  ?= .venv
IMAGE ?= ghcr.io/owner/k8s-demo
TAG   ?= dev

.PHONY: help venv install lint fmt test test-docker build run deploy status

help:
	@echo "make venv        - создать виртуальное окружение ($(PY))"
	@echo "make install     - установить зависимости (включая dev)"
	@echo "make lint        - ruff check"
	@echo "make fmt         - ruff format (исправить форматирование)"
	@echo "make test        - ruff + pytest локально"
	@echo "make test-docker - то же самое, но в контейнере (не нужен локальный Python)"
	@echo "make build       - собрать образ $(IMAGE):$(TAG)"
	@echo "make run         - запустить локально на :18080 (нужен build)"
	@echo "make deploy      - kubectl apply -k deploy/"
	@echo "make status      - состояние деплоя в кластере"

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

deploy:
	kubectl apply -k deploy/

status:
	kubectl get deploy,pods,svc -l app=k8s-demo -o wide
