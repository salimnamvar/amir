"""Logging infrastructure — async queue-based structured logging.

Mirrors the formatting policy from arian bootstrap:
  Diagnostic (< INFO):  LEVEL WHEN WHERE RESOURCE : MESSAGE
  Operational (>= INFO): LEVEL WHEN RESOURCE : MESSAGE

File rotation is handled by a background listener process.
"""

from __future__ import annotations

from datetime import UTC
from datetime import datetime
import logging
import logging.config
import logging.handlers
import queue
from typing import Any

from amir.contract.config import LoggingConfig

APPLICATION_LOGGER_NAME = "amir"

_PROPAGATING_LOGGERS = (APPLICATION_LOGGER_NAME,)

_MODULE = "amir.infrastructure.logging"


def _format_utc_timestamp(epoch_seconds: float) -> str:
    """Format Unix epoch seconds as canonical UTC ISO-8601 (microseconds + Z)."""
    dt = datetime.fromtimestamp(epoch_seconds, tz=UTC)
    return dt.astimezone(UTC).isoformat(timespec="microseconds").replace("+00:00", "Z")


class IsoUtcFormatter(logging.Formatter):
    """UTC ISO-8601 timestamp formatter."""

    def formatTime(  # noqa: N802 — required by logging.Formatter API
        self,
        record: logging.LogRecord,
        datefmt: str | None = None,  # noqa: ARG002
    ) -> str:
        return _format_utc_timestamp(record.created)


class ResourceFilter(logging.Filter):
    """Inject format-safe resource attribute; always admit the record."""

    def filter(self, record: logging.LogRecord) -> bool:
        resource = getattr(record, "resource", None)
        record.resource = f" {resource}" if resource else ""
        return True


class DiagnosticLevelFilter(logging.Filter):
    """Admit diagnostic (< INFO) records only."""

    def filter(self, record: logging.LogRecord) -> bool:
        return record.levelno < logging.INFO


def _build_logging_config(config: LoggingConfig) -> dict[str, Any]:
    """Build dictConfig: named loggers propagate to root; root owns handlers."""
    handlers: dict[str, dict[str, Any]] = {
        "console_debug": {
            "class": "logging.StreamHandler",
            "level": "NOTSET",
            "formatter": "diagnostic",
            "filters": ["diagnostic_level", "resource"],
            "stream": "ext://sys.stderr",
        },
        "console_ops": {
            "class": "logging.StreamHandler",
            "level": "INFO",
            "formatter": "operational",
            "filters": ["resource"],
            "stream": "ext://sys.stderr",
        },
    }

    root_handlers: list[str] = ["console_debug", "console_ops"]

    if config.log_dir is not None:
        log_dir = config.log_dir
        log_dir.mkdir(parents=True, exist_ok=True)
        log_file = log_dir / "amir.log"

        handlers["file"] = {
            "class": "logging.handlers.RotatingFileHandler",
            "level": "NOTSET",
            "formatter": "file",
            "filters": ["resource"],
            "filename": str(log_file),
            "maxBytes": config.max_bytes,
            "backupCount": config.backup_count,
            "encoding": "utf-8",
        }
        root_handlers.append("file")

    return {
        "version": 1,
        "disable_existing_loggers": False,
        "filters": {
            "resource": {"()": f"{_MODULE}.ResourceFilter"},
            "diagnostic_level": {"()": f"{_MODULE}.DiagnosticLevelFilter"},
        },
        "formatters": {
            "diagnostic": {
                "()": f"{_MODULE}.IsoUtcFormatter",
                "format": "%(levelname)s %(asctime)s %(filename)s:%(lineno)d%(resource)s : %(message)s",
            },
            "operational": {
                "()": f"{_MODULE}.IsoUtcFormatter",
                "format": "%(levelname)s %(asctime)s%(resource)s : %(message)s",
            },
            "file": {
                "()": f"{_MODULE}.IsoUtcFormatter",
                "format": "%(levelname)s %(asctime)s %(filename)s:%(lineno)d%(resource)s : %(message)s",
            },
        },
        "handlers": handlers,
        "loggers": {name: {"level": config.level, "handlers": [], "propagate": True} for name in _PROPAGATING_LOGGERS},
        "root": {"level": "WARNING", "handlers": root_handlers},
    }


def _replace_handlers(logger: logging.Logger, handler: logging.Handler) -> None:
    logger.handlers.clear()
    logger.addHandler(handler)


def _enable_async_logging() -> logging.handlers.QueueListener:
    """Route root handlers through QueueHandler for non-blocking I/O."""
    root = logging.getLogger()
    targets = [h for h in root.handlers if not isinstance(h, logging.handlers.QueueHandler)]
    if not targets:
        msg = "Cannot enable async logging: root logger has no handlers"
        raise RuntimeError(msg)

    log_queue: queue.SimpleQueue[logging.LogRecord] = queue.SimpleQueue()
    queue_handler = logging.handlers.QueueHandler(log_queue)
    _replace_handlers(root, queue_handler)

    listener = logging.handlers.QueueListener(log_queue, *targets, respect_handler_level=True)
    listener.start()
    return listener


def configure_logging(config: LoggingConfig | None = None) -> logging.handlers.QueueListener | None:
    """Apply dictConfig + captureWarnings once at process startup.

    Returns a running QueueListener when async logging is enabled.
    """
    cfg = config or LoggingConfig()
    logging.config.dictConfig(_build_logging_config(cfg))
    logging.captureWarnings(True)

    listener: logging.handlers.QueueListener | None = None
    if cfg.async_logging:
        listener = _enable_async_logging()
    return listener


class StructuredLogSink:
    """Implements LogSink protocol using stdlib logging."""

    def __init__(self, logger_name: str = APPLICATION_LOGGER_NAME) -> None:
        self._logger = logging.getLogger(logger_name)

    def write(self, level: str, message: str, resource: str = "") -> None:
        log_level = getattr(logging, level.upper(), logging.INFO)
        extra: dict[str, str] = {}
        if resource:
            extra["resource"] = resource
        self._logger.log(log_level, message, extra=extra)

    def flush(self) -> None:
        for handler in logging.getLogger().handlers:
            handler.flush()
