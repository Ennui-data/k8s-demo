# --- Стадия сборки ---
FROM golang:1.27-alpine AS build

WORKDIR /src

# Сначала только манифесты — слой с зависимостями кэшируется.
COPY go.mod ./

COPY main.go main_test.go ./

ARG VERSION=dev
RUN CGO_ENABLED=0 go build \
        -trimpath \
        -ldflags "-s -w -X main.version=${VERSION}" \
        -o /out/k8s-demo .

# --- Стадия рантайма ---
FROM alpine:3.24

RUN adduser -D -u 10001 app

COPY --from=build /out/k8s-demo /k8s-demo

USER 10001
EXPOSE 8080

# Пробы настраиваются в Kubernetes (deploy/deployment.yaml), HEALTHCHECK не нужен.
ENTRYPOINT ["/k8s-demo"]
