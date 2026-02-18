import os
import time
from flask import Flask, jsonify, Response
from sqlalchemy import create_engine, text
from sqlalchemy.exc import SQLAlchemyError
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST

try:
    from opentelemetry import trace
    from opentelemetry.instrumentation.flask import FlaskInstrumentor
    from opentelemetry.instrumentation.requests import RequestsInstrumentor
    from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter

    OTEL_ENABLED = True
except Exception:
    # If OpenTelemetry or its transitive dependencies (e.g. pkg_resources)
    # are not available, run the service without tracing instead of crashing.
    OTEL_ENABLED = False

# Optional explicit toggle via env. If imports failed above, this stays False.
otel_env = os.getenv("OTEL_ENABLED")
if otel_env is not None and OTEL_ENABLED:
    OTEL_ENABLED = otel_env.lower() in ("1", "true", "yes", "on")

app = Flask(__name__)

DB_HOST = os.getenv("DB_HOST", "postgres.prod.svc.cluster.local")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "counter")
DB_USER = os.getenv("DB_USER", "counter")
DB_PASSWORD = os.getenv("DB_PASSWORD", "counter")
DB_POOL_SIZE = int(os.getenv("DB_POOL_SIZE", "5"))
DB_MAX_OVERFLOW = int(os.getenv("DB_MAX_OVERFLOW", "2"))

DATABASE_URL = (
    f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
)

engine = create_engine(
    DATABASE_URL,
    pool_size=DB_POOL_SIZE,
    max_overflow=DB_MAX_OVERFLOW,
    pool_pre_ping=True,
    pool_recycle=300,
    future=True,
)

REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"],
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "endpoint"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.3, 0.5, 1.0, 2.5, 5.0),
)
COUNTER_VALUE = Gauge("counter_value", "Current counter value")


def setup_tracing() -> None:
    if not OTEL_ENABLED:
        return

    endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
    if not endpoint:
        return

    resource = Resource.create(
        {
            "service.name": os.getenv("OTEL_SERVICE_NAME", "counter-backend"),
            "deployment.environment": os.getenv("OTEL_ENV", "prod"),
        }
    )
    tracer_provider = TracerProvider(resource=resource)
    exporter = OTLPSpanExporter(endpoint=f"{endpoint}/v1/traces")
    tracer_provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(tracer_provider)


if OTEL_ENABLED:
    setup_tracing()
    FlaskInstrumentor().instrument_app(app)
    RequestsInstrumentor().instrument()
    SQLAlchemyInstrumentor().instrument(engine=engine)


def init_db() -> None:
    try:
        with engine.begin() as conn:
            # Use information_schema check instead of CREATE TABLE IF NOT EXISTS
            # to avoid UniqueViolation on pg_type when an orphaned type exists
            # from a previous failed transaction.
            table_exists = conn.execute(
                text(
                    "SELECT EXISTS (SELECT 1 FROM information_schema.tables "
                    "WHERE table_schema = 'public' AND table_name = 'request_counter_state')"
                )
            ).scalar()
            if not table_exists:
                conn.execute(
                    text(
                        """
                        DROP TYPE IF EXISTS request_counter_state;
                        CREATE TABLE request_counter_state (
                            id INTEGER PRIMARY KEY,
                            value BIGINT NOT NULL DEFAULT 0
                        );
                        """
                    )
                )
            )
            conn.execute(
                text(
                    """
                    INSERT INTO request_counter_state (id, value)
                    VALUES (1, 0)
                    ON CONFLICT (id) DO NOTHING;
                    """
                )
            )
    except SQLAlchemyError as exc:
        print(f"DB init skipped due to error: {exc}", flush=True)


@app.before_request
def before_request_metrics():
    from flask import g, request

    g.start_time = time.time()
    g.endpoint = request.path


@app.after_request
def after_request_metrics(response):
    from flask import g, request

    elapsed = time.time() - getattr(g, "start_time", time.time())
    endpoint = getattr(g, "endpoint", "unknown")
    REQUEST_COUNT.labels(request.method, endpoint, response.status_code).inc()
    REQUEST_LATENCY.labels(request.method, endpoint).observe(elapsed)
    return response


@app.get("/api/counter")
def get_counter():
    try:
        with engine.begin() as conn:
            value = conn.execute(
                text("SELECT value FROM request_counter_state WHERE id = 1")
            ).scalar_one()
        COUNTER_VALUE.set(value)
        return jsonify({"value": value})
    except SQLAlchemyError as exc:
        return jsonify({"error": "database error", "detail": str(exc)}), 500


@app.post("/api/counter")
def post_counter():
    try:
        with engine.begin() as conn:
            value = conn.execute(
                text(
                    "UPDATE request_counter_state SET value = value + 1 WHERE id = 1 RETURNING value;"
                )
            ).scalar_one()
        COUNTER_VALUE.set(value)
        return jsonify({"value": value})
    except SQLAlchemyError as exc:
        return jsonify({"error": "database error", "detail": str(exc)}), 500


@app.get("/healthz")
def healthz():
    try:
        with engine.begin() as conn:
            conn.execute(text("SELECT 1"))
        return jsonify({"status": "ok"})
    except SQLAlchemyError:
        return jsonify({"status": "degraded"}), 500


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


init_db()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)