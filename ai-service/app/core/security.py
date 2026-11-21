import hashlib
import hmac
import time
from fastapi import Header, HTTPException, Request, status
from app.core.config import get_settings


async def verify_internal_request(
    request: Request,
    x_internal_service_token: str | None = Header(default=None),
    x_internal_timestamp: str | None = Header(default=None),
    x_internal_signature: str | None = Header(default=None),
) -> None:
    settings = get_settings()

    if not x_internal_service_token or not hmac.compare_digest(
        x_internal_service_token, settings.internal_service_token
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid internal service token.",
        )

    if not x_internal_timestamp or not x_internal_signature:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing internal HMAC signature headers.",
        )

    try:
        ts = int(x_internal_timestamp)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid timestamp header.",
        ) from exc

    if abs(int(time.time()) - ts) > 300:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Internal request signature timestamp expired.",
        )

    raw_body = (await request.body()).decode("utf-8")
    expected = hmac.new(
        settings.internal_hmac_secret.encode("utf-8"),
        f"{x_internal_timestamp}.{raw_body}".encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    if not hmac.compare_digest(expected, x_internal_signature):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Internal HMAC signature verification failed.",
        )
