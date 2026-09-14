"""
auth_middleware.py — Firebase ID token verification for customer AI endpoints.

WHY THIS EXISTS
===============
The original customer chat endpoint trusted `customer_uid` and `customer_name`
values sent in the request body by the Flutter app.  Any client could forge
these values and access any customer's data.

FIX
===
All customer endpoints now require a Firebase Authentication ID token in the
`Authorization: Bearer <token>` header.  The token is verified server-side
using the Firebase Admin SDK.  The authenticated UID is extracted from the
*verified* token — never from the request body.

The request body fields `customer_uid` and `customer_name` are IGNORED for
authorization.  They may still be present for backwards-compatibility logging
but are not used for any data lookup.

USAGE
=====
    from auth_middleware import verify_customer_token, AuthError

    @app.post("/customer/chat")
    def customer_chat(req: CustomerChatRequest, request: Request):
        uid, display_name = verify_customer_token(request)
        # uid is now guaranteed to be the authenticated Firebase UID
"""

import logging
from typing import Tuple

from fastapi import Request, HTTPException
from firebase_admin import auth as firebase_auth

logger = logging.getLogger(__name__)


class AuthError(HTTPException):
    """Raised when Firebase token verification fails."""
    def __init__(self, detail: str, code: str = "AUTHENTICATION_REQUIRED"):
        super().__init__(
            status_code=401,
            detail={"success": False, "error": detail, "error_code": code},
        )


def _extract_bearer_token(request: Request) -> str:
    """
    Extract the raw JWT from the Authorization header.
    Raises AuthError if the header is absent or malformed.
    """
    auth_header = request.headers.get("Authorization", "")
    if not auth_header:
        raise AuthError(
            "Authentication required. Please provide a valid Firebase ID token "
            "in the Authorization header.",
            code="MISSING_TOKEN",
        )
    parts = auth_header.strip().split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise AuthError(
            "Invalid Authorization header format. Expected: Bearer <token>",
            code="INVALID_TOKEN_FORMAT",
        )
    return parts[1]


def verify_customer_token(request: Request) -> Tuple[str, str]:
    """
    Verify the Firebase ID token from the Authorization header.

    Returns
    -------
    (uid, display_name) — both extracted from the *verified* token.
        uid          : Firebase Auth UID (str)
        display_name : user's display name from Firebase (str, may be empty)

    Raises
    ------
    AuthError (HTTP 401) on any failure:
        - Missing header
        - Malformed header
        - Invalid/forged token
        - Expired token
        - Revoked token
        - Firebase Admin SDK error
    """
    token = _extract_bearer_token(request)

    try:
        # check_revoked=True ensures revoked tokens are immediately rejected
        decoded = firebase_auth.verify_id_token(token, check_revoked=True)
    except firebase_auth.RevokedIdTokenError:
        logger.warning("auth: revoked token attempt from IP=%s",
                       request.client.host if request.client else "unknown")
        raise AuthError(
            "Your session has been revoked. Please sign in again.",
            code="TOKEN_REVOKED",
        )
    except firebase_auth.ExpiredIdTokenError:
        raise AuthError(
            "Your session has expired. Please sign in again.",
            code="TOKEN_EXPIRED",
        )
    except firebase_auth.InvalidIdTokenError as exc:
        logger.warning("auth: invalid token — %s", exc)
        raise AuthError(
            "Invalid authentication token. Please sign in again.",
            code="TOKEN_INVALID",
        )
    except Exception as exc:
        # Catch-all: Firebase Admin SDK errors, network issues, etc.
        logger.error("auth: unexpected token verification error — %s: %s",
                     type(exc).__name__, exc)
        raise AuthError(
            "Authentication service unavailable. Please try again.",
            code="AUTH_SERVICE_ERROR",
        )

    uid          = decoded.get("uid") or decoded.get("sub") or ""
    display_name = decoded.get("name") or ""

    if not uid:
        raise AuthError(
            "Could not extract user identity from token.",
            code="UID_MISSING",
        )

    return uid, display_name


def verify_customer_token_optional(request: Request) -> Tuple[str, str] | Tuple[None, None]:
    """
    Like verify_customer_token() but returns (None, None) instead of raising
    when no Authorization header is present.  Used for endpoints that support
    both authenticated and unauthenticated contexts.
    """
    if not request.headers.get("Authorization"):
        return None, None
    return verify_customer_token(request)
