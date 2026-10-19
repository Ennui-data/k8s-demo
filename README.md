# k8s-demo — CI/CD + IaC + GitOps на GitHub Actions, OpenTofu и Argo CD

Небольшое приложение на **Python (Flask + gunicorn)** и полный цикл доставки:

```
                      ┌──────────── PR ────────────┐
                      │ тесты · валидация манифестов│
                      │ tofu fmt/validate/plan      │
                      └─────────────┬───────────────┘
                                    │ merge в main
                                    ▼
   CI (GitHub-hosted)          сборка образа → GHCR → trivy → smoke-тест
                                    │
                                    │ job update-dev: пишет новый тег в git
                                    ▼
   Git (main)  ──►  Argo CD (в кластере)  ──►  dev: применяется автоматически
                                    │
                                    │ workflow promote.yml + approve
                                    ▼
                              prod: применяется автоматически после approve

   IaC (OpenTofu, self-hosted runner):  plan на PR → apply на main после approve
                                         кластер kind + addons + Argo CD
```

Ключевая идея: **CI больше не ходит в кластер с `kubectl`**. CI обновляет тег образа
в git, а кластер сам приводит себя к состоянию из git (Argo CD). Прод от этого
защищён отдельно — правка прод-оверлея проходит через approve.

## Структура

```
app.py, test_app.py, requirements*.txt   приложение и тесты
Dockerfile, .dockerignore                образ: python:3.11-slim, non-root uid 10001
Makefile                                 все локальные команды (make help)

deploy/
  base/                                  общая часть: Deployment + Service
  overlays/dev/                          namespace demo-dev, 1 реплика, ingress k8s-demo.dev.local
  overlays/prod/                         namespace demo-prod, 3 реплики, ingress k8s-demo.prod.local
    namespace.yaml, quota.yaml           Namespace + ResourceQuota + LimitRange окружения
    ingress.yaml                         виртуальный хост
    sops-secret.enc.yaml                 секрет окружения, зашифрован SOPS

infra/                                   инфраструктура как код (OpenTofu, он же Terraform-HCL)
  kind.tf                                кластер kind: нода + проброс 80/443 на 8080/8443
  addons.tf                              helm: ingress-nginx, metrics-server, Argo CD, sops-operator
  secrets.tf                             namespace sops + Secret с приватным age-ключом
  providers.tf, variables.tf, outputs.tf
  versions.tf, tofurc                    версии провайдеров; зеркало реестра (см. «Нюансы»)

argocd/apps/
  root.yaml                              bootstrap (app-of-apps); применяется один раз руками
  dev.yaml, prod.yaml                    Applications окружений: что и куда синхронизировать
.sops.yaml                               правила шифрования (публичный age-ключ)

.github/workflows/
  ci.yml                                 тесты, валидация, сборка, тег в dev
  promote.yml                            прод: обновление тега + approve + проверка
  iac.yml                                tofu plan (PR) / apply (main, approve)
```

## Эндпоинты

| Путь | Назначение |
|---|---|
| `/` | JSON: service, version (тег сборки), hostname, python_version, token_configured |
| `/healthz` | liveness-проба, `ok` |
| `/readyz` | readiness-проба, `ok` |

Версия попадает в образ на этапе сборки (`--build-arg VERSION=<тег>` → `ENV APP_VERSION`),
поэтому `GET /` показывает, какая именно сборка отвечает. `token_configured` —
признак того, что Secret из SOPS доехал до пода (само значение наружу не отдаётся).

## Что отличает окружения

| | dev | prod |
|---|---|---|
| namespace | `demo-dev` | `demo-prod` |
| реплики | 1 | 3 |
| ingress | `k8s-demo.dev.local` | `k8s-demo.prod.local` |
| квоты | 2 CPU / 2Gi requests | 4 CPU / 4Gi requests |
| кто обновляет тег | CI автоматически (`update-dev`) | только `promote.yml` + approve |
| секрет `DEMO_TOKEN` | dev-значение | prod-значение |

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

То же самое без установки Python:

```bash
make test-docker                                    # ruff + pytest внутри python:3.11-slim
make build TAG=local && make run                    # образ + запуск на :18080
```

Манифесты можно проверить ровно тем же, чем это делает CI:

```bash
make lint-manifests ENV=dev      # kustomize build + kubeconform + kube-linter
make render ENV=prod             # посмотреть, что получится
```

## Команды без make

В Astra Linux `make` по умолчанию не установлен — либо поставь его
(`sudo apt-get install -y make`), либо пользуйся командами напрямую. Все таргеты
Makefile — короткие обёртки, вот их содержимое:

```bash
# приложение
python3.11 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/pytest -q

# манифесты
kubectl kustomize deploy/overlays/dev > /tmp/dev.yaml
kubeconform -strict -ignore-missing-schemas -summary /tmp/dev.yaml
kube-linter lint /tmp/dev.yaml

# инфраструктура (всегда на живом кластере, docker — через sg, если сессия без группы)
export TF_CLI_CONFIG_FILE=$PWD/infra/tofurc
cd infra && tofu init -backend-config=path=$HOME/.local/share/tofu/k8s-demo.tfstate
cd infra && sg docker -c "tofu plan"      # и tofu apply

# секреты
sops deploy/overlays/dev/sops-secret.enc.yaml        # правка
sops --decrypt deploy/overlays/dev/sops-secret.enc.yaml   # посмотреть

# Argo CD
kubectl -n argocd get applications
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

# стенд
sg docker -c 'docker stop --time 60 k8s-demo-control-plane'    # выключить
sg docker -c 'docker start k8s-demo-control-plane'             # включить
```

## Инфраструктура как код (OpenTofu)

Кластер и платформенные аддоны создаются кодом из `infra/`:

| Ресурс | Что делает |
|---|---|
| `kind_cluster.this` | кластер kind `k8s-demo`: нода + проброс 80→8080, 443→8443 |
| `helm_release.ingress_nginx` | ingress-контроллер (hostPort 80/443 внутри ноды) |
| `helm_release.metrics_server` | `kubectl top` (+ пригодится для HPA) |
| `helm_release.argo_cd` | GitOps-контроллер, опрос git раз в 30 с |
| `kubernetes_namespace_v1.sops` + `kubernetes_secret_v1` | namespace оператора и Secret с age-ключом |
| `helm_release.sops_secrets_operator` | расшифровка `SopsSecret` → `Secret` в кластере |
| `kubernetes_ingress_v1.argocd` | UI Argo CD на `argocd.local` |

```bash
make docker-check        # проверить доступ к docker (на этой машине — через sg docker)
make iac-init            # tofu init (провайдеры тянутся через зеркало, см. tofurc)
make iac-plan            # что изменится
make iac-apply           # создать/обновить кластер и аддоны
make iac-output          # URL-ы окружений, команда для пароля Argo CD
```

State лежит вне репозитория: `~/.local/share/tofu/k8s-demo.tfstate`
(в команде вместо этого — удалённый backend S3/MinIO с блокировкой).

**Bootstrap делается один раз** — единственный объект, который создаётся руками:

```bash
kubectl apply -f argocd/apps/root.yaml
```

Дальше Argo CD сам читает папку `argocd/apps` и создаёт Applications `k8s-demo-dev` и
`k8s-demo-prod`, а те, в свою очередь — оверлеи из git.

## CI/CD

| Workflow | Триггер | Что делает |
|---|---|---|
| `ci.yml` | PR, push в main, вручную | тесты (ruff, pytest) → валидация (`kustomize build` + `kubeconform -strict` + `kube-linter`) → сборка образа в GHCR → `trivy` (CRITICAL) → smoke-тест → job `update-dev`: пишет новый тег в `deploy/overlays/dev` и коммитит |
| `promote.yml` | вручную | job `promote` (environment **prod**, нужен approve) пишет тег в `deploy/overlays/prod`; job `verify` ждёт Argo CD и проверяет живой ответ |
| `iac.yml` | PR/push по `infra/**`, вручную | `tofu fmt -check`, `init`, `validate`, `plan`; на main — `apply` после approve (environment **prod**) |

Два важных свойства:

* коммиты из workflow делаются встроенным `GITHUB_TOKEN`, а такие push'и **не запускают
  другие workflow** — поэтому пайплайн не зацикливается на собственных коммитах;
* в git едет только тег (`sha-xxxxxxx`), а тег — это коммит, так что всегда видно,
  какой именно код работает в dev и в prod.

## Продвижение в прод

```bash
# 1. тег уже проверен в dev — смотрим его
curl -s -H "Host: k8s-demo.dev.local" http://localhost:8080/ | jq -r .version

# 2. запускаем продвижение (потребуется approve в UI или через API/gh)
gh workflow run promote.yml -f tag=sha-abc1234
```

В UI: `Actions → Promote → Run workflow`, затем в pending deployment нажать
**Review deployments → Approve**. Гейт настраивается в
`Settings → Environments → prod → Required reviewers`; сейчас там стоит владелец репозитория
(self-review разрешён, иначе запускать некому).

Проверка руками:

```bash
curl -s -H "Host: k8s-demo.prod.local" http://localhost:8080/ | jq
```

## Секреты (SOPS + age)

Приватный ключ лежит **вне git**: `~/.config/sops/age/keys.txt` (он же попадает в кластер
как Secret и монтируется в sops-секрет-оператор). В git хранится только зашифрованный
манифест и публичный ключ.

```bash
# посмотреть/поправить секрет окружения (откроется в $EDITOR, сохранит шифртекст)
make secrets-edit ENV=dev

# или вручную
sops deploy/overlays/prod/sops-secret.enc.yaml

# проверить, что расшифровывается
sops --decrypt deploy/overlays/dev/sops-secret.enc.yaml
```

Как это работает: в оверлее лежит `SopsSecret` (CRD) с зашифрованным поддеревом
`secretTemplates`. Оператор в кластере расшифровывает его age-ключом и создаёт обычный
`Secret` `k8s-demo-secret`, который Deployment подключает через `envFrom`.
Плейнтекст в git не попадает никогда — `.gitignore` дополнительно страхует файлы
`sops-secret.yaml` и `*.dec.yaml`.

## Откат

Откат — это тоже правка git (история и self-heal в Argo CD):

```bash
git revert <коммит с cd: prod -> sha-...>   # Argo CD вернёт предыдущий тег
git push
```

## Как выключить и включить стенд

Кластер kind — это один контейнер, поэтому выключение не трогает ни git, ни state:

```bash
make cluster-stop          # остановить кластер, память освободится
make cluster-start         # включить и дождаться, пока нода станет Ready
```

После запуска Argo CD сам приведёт окружения к состоянию из git (опрос раз в 30 c) —
вручную ничего делать не нужно. Пара оговорок:

* пока кластер остановлен, `tofu plan/apply` **падают**: провайдер читает kubeconfig
  из живого контейнера (`docker exec ... cat /etc/kubernetes/admin.conf`). IaC — только
  на работающем кластере;
* остановка ноды завершается сигналом (kind-нода не укладывается в graceful timeout,
  `docker stop` возвращает код 137). etcd поднимается реплеем WAL — это штатное
  поведение kind, но если стенд не нужен надолго, честнее снести его совсем:
  запустить → `cd infra && tofu apply` (или `tofu destroy`) → при необходимости
  заново `kubectl apply -f argocd/apps/root.yaml`;
* если кластер выключен, jobs, которым нужен кластер (`tofu apply`, проверка после
  promote), будут падать. Чтобы не ловить это, можно остановить и раннер:
  `systemctl --user stop github-runner`.

## Требования и разовая настройка

1. **Docker** на машине (кластер kind — это контейнер): через `sg docker`, если сессия
   не имеет группы `docker`.
2. **Self-hosted runner** с метками `self-hosted, linux, x64, kind` — на нём работают
   `tofu apply` и проверка после продвижения (кластер локальный, из облака до него не достать).

```bash
OWNER_REPO=ВАШ_ЛОГИН/k8s-demo
TOKEN=$(curl -fsS -X POST -H "Authorization: Bearer $GH_TOKEN" \
  https://api.github.com/repos/$OWNER_REPO/actions/runners/registration-token | jq -r .token)

mkdir -p ~/actions-runner && cd ~/actions-runner
curl -fsSLO https://github.com/actions/runner/releases/download/v2.338.0/actions-runner-linux-x64-2.338.0.tar.gz
tar xzf actions-runner-linux-x64-2.338.0.tar.gz
./config.sh --unattended --replace --name "$(hostname)-kind" --labels kind \
  --url "https://github.com/$OWNER_REPO" --token "$TOKEN"
./run.sh
```

Сервис через user-systemd (`~/.config/systemd/user/github-runner.service`):

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

3. **GitHub Environment `prod`** с required reviewers (см. раздел про прод).

## Нюансы, о которые легко споткнуться

**Реестр провайдеров и зеркало.** `registry.terraform.io` и `registry.opentofu.org`
из этого региона отдают `403` (CloudFront WAF: `x-amzn-waf-reason: geo`). Поэтому
`infra/tofurc` настраивает `network_mirror` на публичное зеркало
`terraform-mirror.yandexcloud.net`, а адреса провайдеров в `versions.tf` указаны
явно с хостом (`registry.terraform.io/...`). В CI переменная
`TF_CLI_CONFIG_FILE` указывает на этот файл.

**Образы из `ecr-public.aws.com`.** Чарт Argo CD по умолчанию тянет redis оттуда, и
из этого региона он не загружается (`ImagePullBackOff`). В `addons.tf` репозиторий
переопределён на Docker Hub.

**Долгая первая загрузка образов.** `registry.k8s.io/ingress-nginx/controller`
(~116 МБ) на этом канале тянется несколько минут — Pod висит в `ContainerCreating`,
это не поломка. Смотреть причину: `kubectl -n ingress-nginx describe pod`.

**Регистр в имени образа.** В GHCR путь должен быть в нижнем регистре
(`ghcr.io/ennui-data/k8s-demo`): Docker не принимает заглавные буквы, а логин GitHub
может их содержать. В workflow это учтено (`tr '[:upper:]' '[:lower:]'`).

**Приватность пакета.** Если пакет в GHCR приватный, нода kind застрянет в
`ImagePullBackOff`. Варианты: сделать пакет публичным (`Settings → Change visibility`)
или завести `imagePullSecret`.

**Read-only rootfs и gunicorn.** При `readOnlyRootFilesystem: true` gunicorn пишет
служебные файлы воркеров в `/tmp`, поэтому в манифесте есть `emptyDir` на `/tmp`.

**Порядок namespace → Secret → релиз (sops-оператор).** Если отдать создание namespace
чарту (`create_namespace = true`) и `wait = true`, получится блокировка: Pod ждёт Secret
с age-ключом, а Secret создаётся Terraform уже после релиза. Поэтому в `secrets.tf`
namespace и Secret создаются явно, до релиза.

**App-of-apps: root лежит внутри своей же папки.** Это не случайность. Если вынести
`root.yaml` из `argocd/apps`, живой объект `k8s-demo-root` станет для приложения
«сиротой»: при `prune: true` Argo CD удалит его, а `resources-finalizer` унесёт за ним
дочерние Applications вместе с содержимым `demo-dev` и `demo-prod`. Ловушка коварна тем,
что проявляется не сразу, а на следующей синхронизации.

**Если `tofu apply` упал на helm-релизе.** Helm-релиз может остаться в кластере
(`failed`), при этом в state он не запишется. Следующий apply тогда ругается
`cannot re-use a name that is still in use`. Лечение — удалить недоделанный релиз
вместе с его ресурсами и применить заново:

```bash
kubectl delete ns <namespace релиза>
# CRD чарта (если их ставил он) тоже придётся убрать при переустановке:
kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io
make iac-apply
```

**Уже существующий ресурс нужно импортировать.** Если объект был создан не Terraform
(например, namespace — чартом), а теперь попал в код, `apply` упадёт с `already exists`.
Правильный путь — не удалять, а импортировать: `tofu import <адрес> <id>`.

**Docker у сервиса раннера.** `systemctl --user` сессия была запущена до добавления
пользователя в группу `docker`, поэтому в `iac.yml` команды идут через
`sg docker -c "..."`. После перелогина это не обязательно, но и не мешает.

**DNS для ingress-контроллера не настраивается.** Хосты `k8s-demo.dev.local`,
`k8s-demo.prod.local`, `argocd.local` резолвятся только если добавить их в `/etc/hosts`
(нужен root) — поэтому проверка идёт заголовком `Host:`, а не именем.

## Что можно добавить дальше

* HPA в prod (metrics-server уже стоит) и `PodDisruptionBudget`;
* ingress-nginx как отдельный Application (управляется Argo CD, а не Terraform);
* внешние секреты (Vault / External Secrets) вместо SOPS;
* e2e-тесты в одноразовом namespace и прогрессивная доставка (Argo Rollouts);
* удалённый backend для state (S3/MinIO) с блокировкой и `prevent_self_review: true`
  в настройках environment `prod`.
