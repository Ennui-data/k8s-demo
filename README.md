# k8s-demo — пример CI/CD в GitHub Actions с деплоем в kind

Маленькое Go-приложение (stdlib only) + пайплайн: **тесты → сборка образа → push в GHCR → деплой в кластер kind**.

```
push в main ──► [test] ──► [build] ──► [deploy]
                 │          │            │
             gofmt/vet/   docker push  self-hosted runner:
             go test      в ghcr.io    kubectl apply -k + rollout
                          + smoke-тест
```

## Структура

```
main.go                     HTTP-сервис: /, /healthz, /readyz
main_test.go                юнит-тесты (httptest)
Dockerfile                  multi-stage: golang:1.27-alpine → alpine:3.24, non-root
Makefile                    локальные команды
deploy/kustomization.yaml   подстановка образа (CI переписывает newName/newTag)
deploy/deployment.yaml      2 реплики, пробы, лимиты, non-root, readonly rootfs
deploy/service.yaml         NodePort 30080 (проброшен на localhost:8080)
.github/workflows/ci-cd.yml пайплайн
```

## Эндпоинты

| Путь | Назначение |
|---|---|
| `/` | JSON: service, version (тег сборки), hostname, go_version |
| `/healthz` | liveness-проба, `ok` |
| `/readyz` | readiness-проба, `ok` |

## Локальная разработка

```bash
make test              # gofmt-проверка делается в CI
make build TAG=local   # docker build
make run               # запуск на http://localhost:18080
```

## Требования для деплоя

1. Кластер kind с нодой, у которой NodePort **30080** проброшен на **8080** хоста:

   ```yaml
   # kind-config.yaml
   nodes:
     - role: control-plane
       extraPortMappings:
         - containerPort: 30080
           hostPort: 8080
   ```

2. Self-hosted runner с метками `self-hosted, linux, x64, kind` на той же машине,
   где есть `kubectl` (`~/.kube/config`) и запущенный кластер.

### Установка runner (без root)

```bash
OWNER_REPO=ВАШ_ЛОГИН/k8s-demo
TOKEN=$(curl -fsS -X POST -H "Authorization: Bearer $GH_TOKEN" \
  https://api.github.com/repos/$OWNER_REPO/actions/runners/registration-token | jq -r .token)

mkdir -p ~/actions-runner && cd ~/actions-runner
curl -fsSLO https://github.com/actions/runner/releases/download/v2.338.0/actions-runner-linux-x64-2.338.0.tar.gz
tar xzf actions-runner-linux-x64-2.338.0.tar.gz
./config.sh --unattended --replace --name "$(hostname)-kind" --labels kind \
  --url "https://github.com/$OWNER_REPO" --token "$TOKEN"
./run.sh          # проверить вручную, затем оформить как сервис (см. ниже)
```

Сервис через user-systemd (папка `~/.config/systemd/user/github-runner.service`):

```ini
[Unit]
Description=GitHub Actions runner (kind)
After=network-online.target

[Service]
ExecStart=%h/actions-runner/run.sh
WorkingDirectory=%h/actions-runner
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now github-runner
sudo loginctl enable-linger "$USER"   # чтобы работал после логаута
```

## Секреты

Отдельные секреты **не нужны**: для push в GHCR используется встроенный `GITHUB_TOKEN`
(права `packages: write` выдаются в job `build`).

## Важно про приватность образа

Образ попадает в GHCR. Если пакет приватный, нода kind не сможет его скачать и поды
застрянут в `ImagePullBackOff`. Варианты:

- сделать пакет публичным (Settings пакета → Change visibility → Public) — проще всего;
- либо завести `imagePullSecret` и добавить его в `deployment.yaml`.

## Ручной прогон и откат

```bash
# ручной запуск пайплайна
gh workflow run ci-cd.yml

# откат на предыдущую ревизию
kubectl rollout undo deployment/k8s-demo
kubectl rollout history deployment/k8s-demo

# принудительный деплой конкретного тега
kubectl set image deployment/k8s-demo app=ghcr.io/OWNER/k8s-demo:sha-abc1234
```
