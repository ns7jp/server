FROM python:3.14-slim

# 本体の Dockerfile と同じ方針で、非 root ユーザーで動かす。
RUN useradd --system --create-home --shell /usr/sbin/nologin apuser

WORKDIR /srv/ap

COPY requirements.txt ./
RUN pip install --no-cache-dir --requirement requirements.txt

COPY app.py ./

USER apuser

EXPOSE 8000

# 障害注入で DB を止めたときにワーカーが張り付かないよう、
# 要求のタイムアウトを明示する。
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--timeout", "15", "app:app"]
