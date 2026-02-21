FROM python:3.12-slim
WORKDIR /backend
COPY requirements.txt .
RUN useradd -u 10001 -m appuser \
    && pip install --no-cache-dir -r requirements.txt
COPY app.py .
USER 10001
EXPOSE 8080
CMD ["gunicorn", "--workers=2", "--threads=4", "--bind=0.0.0.0:8080", "app:app"]
