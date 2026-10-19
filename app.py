"""Минимальный HTTP-сервис для демонстрации CI/CD: Flask + gunicorn.

Версия сборки приходит из переменной окружения APP_VERSION, которую
подставляет Dockerfile при сборке образа (build-arg VERSION).
"""

import os
import platform
import socket

from flask import Flask, jsonify, request

APP_VERSION = os.getenv("APP_VERSION", "dev")
PORT = int(os.getenv("PORT", "8080"))


def create_app() -> Flask:
    """Фабрика приложения: удобно и для тестов, и для gunicorn."""
    app = Flask(__name__)
    app.json.sort_keys = False

    @app.get("/")
    def index():
        """JSON с версией сборки — по нему видно, что именно задеплоилось."""
        return jsonify(
            service="k8s-demo",
            version=APP_VERSION,
            hostname=socket.gethostname(),
            path=request.path,
            python_version=platform.python_version(),
        )

    @app.get("/healthz")
    def healthz():
        """Liveness-проба: процесс жив."""
        return "ok\n", 200, {"Content-Type": "text/plain; charset=utf-8"}

    @app.get("/readyz")
    def readyz():
        """Readiness-проба: готов принимать трафик."""
        return "ok\n", 200, {"Content-Type": "text/plain; charset=utf-8"}

    return app


app = create_app()

if __name__ == "__main__":
    # Только для локальной разработки; в контейнере приложение запускает gunicorn.
    app.run(host="0.0.0.0", port=PORT)
