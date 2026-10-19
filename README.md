# k8s-demo — пример CI/CD в GitHub Actions с деплоем в kind

Маленькое приложение на **Python (Flask + gunicorn)** + пайплайн:
**тесты → сборка образа → push в GHCR → деплой в кластер kind**.

```
push в main ──► [test] ──► [build] ──► [deploy]
                 │          │            │
            ruff + pytest  docker push  self-hosted runner:
                           в ghcr.io    kubectl apply -k + rollout
                           + smoke-тест
```

## Структура

```
app.py                      Flask-приложение: /, /healthz, /readyz
test_app.py                 тесты (pytest, Flask test client)
requirements.txt            flask, gunicorn (рантайм)
requirements-dev.txt        + pytest, ruff (для тестов и линтера)
pyproject.toml              настройки ruff и pytest
.python-version             3.11 (используется в CI)
Dockerfile                  python:3.11-slim, non-root uid 10001, gunicorn
Makefile                    локальные команды
deploy/kustomization.yaml   подстановка образа (CI переписывает newName/newTag)
deploy/deployment.yaml      2 реплики, пробы, лимиты, non-root, read-only rootfs
deploy/service.yaml         NodePort 30080 (проброшен на localhost:8080)
.github/workflows/ci-cd.yml пайплайн
```

## Эндпоинты

| Путь | Назначение |
|---|---|
| `/` | JSON: service, version (тег сборки), hostname, python_version |
| `/healthz` | liveness-проба, `ok` |
| `/readyz` | readiness-проба, `ok` |

Версия попадает в образ на этапе сборки: `docker build --build-arg VERSION=<тег>` →
`ENV APP_VERSION` → `GET /` показывает, какая сборка реально запущена.

## Локальная разработка

Системный Python в Astra Linux — 3.7, он не подойдёт. Один раз ставим 3.11:

```bash
sudo apt-get install -y python3.11 python3.11-venv
```

Дальше:

```bash
make venv            # создать .venv (использует python3.11, если он есть)
make install         # установить зависимости
make test            # ruff check + ruff format --check + pytest
make fmt             # автоисправление форматирования

APP_VERSION=local PORT=8080 .venv/bin/python app.py   # запуск на http://localhost:8080
```

Если не хочется ставить Python вообще — всё то же самое в контейнере:

```bash
make test-docker     # ruff + pytest внутри python:3.11-slim
make build TAG=local && make run                     # образ + запуск на :18080
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

## Нюансы, о которые легко споткнуться

**Приватность образа.** Образ попадает в GHCR. Если пакет приватный, нода kind не сможет
его скачать и поды застрянут в `ImagePullBackOff`. Варианты: сделать пакет публичным
(Settings пакета → Change visibility → Public) или завести `imagePullSecret`.

**Регистр в имени образа.** Путь в GHCR должен быть в нижнем регистре
(`ghcr.io/ennui-data/k8s-demo`, а не `ghcr.io/Ennui-data/k8s-demo`) — Docker не принимает
заглавные буквы в имени репозитория. В workflow это учтено (`tr '[:upper:]' '[:lower:]'`).

**Read-only файловая система и gunicorn.** В `deployment.yaml` включён
`readOnlyRootFilesystem: true`, а gunicorn для служебных файлов воркеров пишет в `/tmp`.
Поэтому в манифест добавлен `emptyDir` на `/tmp` — без него контейнер не поднимется.

## Ручной прогон и откат

```bash
# ручной запуск пайплайна
gh workflow run ci-cd.yml

# откат на предыдущую ревизию
kubectl rollout undo deployment/k8s-demo
kubectl rollout history deployment/k8s-demo

# принудительный деплой конкретного тега
kubectl set image deployment/k8s-demo app=ghcr.io/owner/k8s-demo:sha-abc1234
```
