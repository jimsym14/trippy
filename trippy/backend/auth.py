"""Supabase asymmetric JWT verification against a fixed, trusted issuer."""

from dataclasses import dataclass
from urllib.parse import urlparse
from uuid import UUID

import jwt

from .common import DomainError


@dataclass(frozen=True)
class Principal:
    owner_id: str
    admin: bool = False


class SupabaseJWTVerifier:
    def __init__(self, supabase_url, *, key_resolver=None):
        parsed = urlparse(supabase_url)
        if parsed.scheme != "https" or not parsed.netloc or parsed.path not in ("", "/") or parsed.query or parsed.fragment:
            raise ValueError("A trusted HTTPS Supabase project URL is required")
        self.issuer = supabase_url.rstrip("/") + "/auth/v1"
        self.client = None
        if key_resolver is None:
            self.client = jwt.PyJWKClient(self.issuer + "/.well-known/jwks.json",
                                         cache_jwk_set=True, lifespan=300, timeout=5)
            key_resolver = lambda token: self.client.get_signing_key_from_jwt(token).key
        self.key_resolver = key_resolver

    def verify(self, token):
        try:
            header = jwt.get_unverified_header(token)
            if header.get("alg") not in {"RS256", "ES256"} or not header.get("kid"):
                raise ValueError("Unsupported signing key")
            claims = jwt.decode(token, self.key_resolver(token), algorithms=["RS256", "ES256"],
                                issuer=self.issuer, audience="authenticated", leeway=5,
                                options={"require": ["exp", "iat", "sub", "iss", "aud"]})
            if claims.get("role") != "authenticated":
                raise ValueError("Not a user access token")
            owner = str(UUID(claims["sub"]))
            metadata = claims.get("app_metadata", {})
            # app_metadata is signed and server-managed. user_metadata and
            # client-provided owner/admin flags never grant authorization.
            admin = isinstance(metadata, dict) and metadata.get("trippy_role") == "admin" and claims.get("aal") == "aal2"
            return Principal(owner, admin)
        except (jwt.PyJWTError, ValueError, TypeError, KeyError):
            raise DomainError("invalid_access_token", 401) from None


class RejectAllAuth:
    def verify(self, token):
        raise DomainError("auth_not_configured", 503)
