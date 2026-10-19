# --- Рантайм ---
FROM python:3.11-slim

ARG VERSION=dev
ENV APP_VERSION=${VERSION} \
    PORT=8080 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# Сначала зависимости — этот слой кэшируется, пока не менялся requirements.txt.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py ./

# Не работаем от root.
RUN useradd --create-home --uid 10001 app
USER 10001

EXPOSE 8080

# exec, чтобы gunicorn был PID 1 и корректно получал сигналы (SIGTERM при rollout).
CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT} --workers 2 --access-logfile - --error-logfile - app:app"]
