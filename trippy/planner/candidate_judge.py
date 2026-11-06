"""Grounded candidate judging: ambiguity detection, sanitized payloads, and strict validation.

The candidate judge is an optional evaluation step used ONLY when the deterministic
planner detects a ranking ambiguity (tie) among retrieved catalog candidates.
It cannot:
- Add or invent new places.
- Alter coordinates, opening hours, prices, or ratings.
- Override explicit locked stops, user exclusions, or hard constraints.
- Override the priority advantage of saved personal pins (personal_priority=100).
"""
from __future__ import annotations

from dataclasses import dataclass
import logging
from typing import Any, Dict, List, Optional, Set

logger = logging.getLogger(__name__)

MAX_JUDGE_CANDIDATES = 8

JUDGE_SYSTEM = (
    "You are a travel candidate ranking evaluator. "
    "Your role is strictly to score and rank already-retrieved candidate venues for a trip. "
    "You MUST ONLY reference place_ids from the provided candidate list. "
    "Never invent places, place_ids, coordinates, prices, opening hours, or factual claims. "
    "Return only the structured output conforming to the response schema."
)

JUDGE_SCHEMA = {
    "type": "object",
    "properties": {
        "rankings": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "place_id": {"type": "string"},
                    "score": {"type": "number"},
                    "reason": {"type": "string"},
                },
                "required": ["place_id", "score", "reason"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["rankings"],
    "additionalProperties": False,
}


@dataclass(frozen=True)
class RankingItem:
    place_id: str
    score: float
    reason: str


@dataclass(frozen=True)
class JudgeResult:
    rankings: List[RankingItem]
    model_name: str
    status: str = "succeeded"


def sanitize_candidates_for_judge(candidates: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Sanitize candidates to the minimal non-private fields required for ranking.

    Never passes raw personal notes, library graph nodes, private user data, or coordinates.
    """
    sanitized = []
    for c in candidates[:MAX_JUDGE_CANDIDATES]:
        sanitized.append({
            "id": c["id"],
            "name": c.get("name", ""),
            "category": c.get("category", ""),
            "description": (c.get("description") or "")[:200],
            "why_recommended": (c.get("why_recommended") or "")[:200],
            "tags": list(c.get("tags") or [])[:10],
            "neighborhood": c.get("neighborhood") or (c.get("address") or "")[:80],
        })
    return sanitized


def detect_ranking_ambiguity(
    places: List[Dict[str, Any]],
    brief: Dict[str, Any],
    max_candidates: int = MAX_JUDGE_CANDIDATES,
) -> List[Dict[str, Any]]:
    """Identify whether retrieved catalog candidates have a meaningful ranking ambiguity.

    A ranking ambiguity occurs when two or more catalog candidates in the same category
    share identical deterministic preference scores (e.g., preference tag matches) and
    are competing for schedule slots.

    Saved personal pins (personal_priority=100) are never considered ambiguous with
    catalog candidates; personal pins always take precedence.
    Excluded places and locked stops are ignored.
    """
    excluded = set(brief.get("excluded_place_ids") or [])
    locked_ids = {x.get("place_id") for x in (brief.get("locked_stops") or [])}
    preference_tags = set(brief.get("preference_tags") or [])

    # Consider only catalog candidates (personal_priority == 0) that are not locked/excluded
    eligible = [
        p for p in places
        if p.get("personal_priority", 0) == 0
        and p["id"] not in excluded
        and p["id"] not in locked_ids
        and p.get("identity_status") == "source_matched"
    ]

    by_category: Dict[str, List[Dict[str, Any]]] = {}
    for p in eligible:
        by_category.setdefault(p.get("category", "other"), []).append(p)

    ambiguous: List[Dict[str, Any]] = []
    seen_ids: Set[str] = set()

    for category, items in by_category.items():
        if len(items) < 2:
            continue

        # Score candidates deterministically by matching preference tags
        scored = [
            (len(set(p.get("tags") or []) & preference_tags), p)
            for p in items
        ]
        scored.sort(key=lambda x: -x[0])

        # Check if the top candidates are tied in score
        top_score = scored[0][0]
        tied_top = [p for score, p in scored if score == top_score]

        if len(tied_top) >= 2:
            for p in tied_top:
                if p["id"] not in seen_ids:
                    seen_ids.add(p["id"])
                    ambiguous.append(p)

    return ambiguous[:max_candidates]


def validate_judge_response(
    raw: Any,
    allowed_ids: Set[str],
    model_name: str,
) -> Optional[JudgeResult]:
    """Validate a judge response against strict integrity constraints.

    Rejects immediately if:
    - The response is not a dict or missing 'rankings'.
    - Any place_id is not in allowed_ids.
    - Any place_id is duplicated.
    - Any score is not a float between 0.0 and 1.0.
    """
    if not isinstance(raw, dict):
        logger.warning("Judge validation failed: response is not a dict (%s)", type(raw).__name__)
        return None

    rankings_raw = raw.get("rankings")
    if not isinstance(rankings_raw, list):
        logger.warning("Judge validation failed: 'rankings' is not a list")
        return None

    seen_ids: Set[str] = set()
    validated_items: List[RankingItem] = []

    for item in rankings_raw:
        if not isinstance(item, dict):
            logger.warning("Judge validation failed: item in rankings is not a dict")
            return None

        pid = item.get("place_id")
        if not isinstance(pid, str) or pid not in allowed_ids:
            logger.warning("Judge validation failed: unknown or fabricated place_id %r", pid)
            return None

        if pid in seen_ids:
            logger.warning("Judge validation failed: duplicate place_id %r", pid)
            return None
        seen_ids.add(pid)

        score = item.get("score")
        if not isinstance(score, (int, float)) or not (0.0 <= score <= 1.0):
            logger.warning("Judge validation failed: invalid score %r for place_id %s", score, pid)
            return None

        reason = item.get("reason", "")
        if not isinstance(reason, str):
            reason = str(reason)

        validated_items.append(RankingItem(place_id=pid, score=float(score), reason=reason[:250]))

    return JudgeResult(rankings=validated_items, model_name=model_name, status="succeeded")

