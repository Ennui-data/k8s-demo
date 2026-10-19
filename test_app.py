"""Тесты сервиса: запускаются без сети и без внешних зависимостей."""

import pytest

from app import create_app


@pytest.fixture()
def client():
    app = create_app()
    app.config.update(TESTING=True)
    return app.test_client()


@pytest.mark.parametrize("path", ["/healthz", "/readyz"])
def test_health_endpoints(client, path):
    response = client.get(path)

    assert response.status_code == 200
    assert response.get_data(as_text=True).strip() == "ok"


def test_index_reports_build_info(client):
    response = client.get("/")

    assert response.status_code == 200

    body = response.get_json()
    assert body["service"] == "k8s-demo"
    assert body["path"] == "/"
    assert body["hostname"]
    assert body["version"]
    assert body["python_version"]


def test_index_reports_configured_token(client, monkeypatch):
    monkeypatch.setenv("DEMO_TOKEN", "super-secret-token")

    body = client.get("/").get_json()

    assert body["token_configured"] is True
    assert body["token_length"] == len("super-secret-token")


def test_index_without_token(client, monkeypatch):
    monkeypatch.delenv("DEMO_TOKEN", raising=False)

    body = client.get("/").get_json()

    assert body["token_configured"] is False
    assert body["token_length"] == 0
