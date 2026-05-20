"""Secret-keyed storage identifiers for shared direct-call backend state."""

from __future__ import annotations

import hashlib
import hmac
from dataclasses import dataclass


@dataclass(frozen=True)
class StorageKeyHasher:
    """Build Redis-safe keys without embedding raw Matrix or credential identifiers."""

    secret: str

    def digest(self, *parts: str) -> str:
        material = "\x1f".join(parts).encode("utf-8")
        return hmac.new(self.secret.encode("utf-8"), material, hashlib.sha256).hexdigest()

    def redis_key(self, prefix: str, *parts: str) -> str:
        return f"{prefix}:{self.digest(*parts)}"
