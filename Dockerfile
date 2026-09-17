FROM python:3.14-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN addgroup --system monitor && adduser --system --ingroup monitor --no-create-home monitor

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
COPY templates ./templates
COPY static ./static

USER monitor
EXPOSE 5000

# gthread supports upstream keepalive; sync closes every response. Keep request
# concurrency at two workers x one thread while reducing TCP connection churn.
CMD ["gunicorn", "--workers", "2", "--worker-class", "gthread", "--threads", "1", "--keep-alive", "5", "--bind", "0.0.0.0:5000", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
