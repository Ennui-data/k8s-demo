IMAGE ?= ghcr.io/owner/k8s-demo
TAG   ?= dev

.PHONY: help test fmt build run deploy status

help:
	@echo "make test    - go test -race"
	@echo "make fmt     - gofmt -w"
	@echo "make build   - собрать образ ($(IMAGE):$(TAG))"
	@echo "make run     - запустить локально на :18080"
	@echo "make deploy  - kubectl apply -k deploy/"
	@echo "make status  - состояние деплоя в кластере"

test:
	go test -race ./...

fmt:
	gofmt -w .

build:
	docker build --build-arg VERSION=$(TAG) -t $(IMAGE):$(TAG) .

run: build
	docker run --rm -p 18080:8080 $(IMAGE):$(TAG)

deploy:
	kubectl apply -k deploy/

status:
	kubectl get deploy,pods,svc -l app=k8s-demo -o wide
