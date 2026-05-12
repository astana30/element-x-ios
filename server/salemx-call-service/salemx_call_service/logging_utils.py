"""Redacted structured logging helpers."""

from __future__ import annotations

import hashlib
import logging


def configure_logging(level: str) -> None:
    logging.basicConfig(level=getattr(logging, level.upper(), logging.INFO), format="%(levelname)s %(name)s %(message)s")


def stable_redacted_id(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:16]
