"""
input_normalizer.py — deterministic input normalization for intent detection.

Runs BEFORE the regex intent classifiers (model_router / intent_classifier /
direct-lookup paths).  Pure Python, no network, no LLM — zero cost.

Purpose:
  Typo'd, abbreviated, or informally-phrased prompts used to fall through the
  fast deterministic paths into the slow LLM tool-calling loop.  Normalizing
  the text first lets those prompts hit the 0-token fast paths.

  "show inventry"        -> "show inventory"
  "what stok is low"     -> "what stock is low"
  "show maintenence"     -> "show maintenance"
  "show vehcle history"  -> "show vehicle history"
  "show bookngs"         -> "show bookings"
  "magkano ang pms"      -> "how much ang pms"
  "can u show the inv"   -> "can you show the inventory"

Safety:
  - Only used for INTENT DETECTION / ROUTING.  The ORIGINAL message is still
    what gets answered by the LLM or echoed in templates, so aggressive
    correction can never corrupt an actual answer.
  - Conservative correction: an exact vocabulary match is never touched, and
    fuzzy (edit-distance-1) correction only applies to tokens of 5+ chars so
    short words are never mangled.
"""
import re

# ── Domain vocabulary (exact matches are left untouched) ──────────────────────
_VOCAB = {
    # inventory / stock
    "inventory", "inventories", "stock", "stocks", "items", "item", "parts",
    "part", "materials", "material", "supplies", "supply", "supplier",
    "suppliers", "reorder", "reorder", "restock", "restocking", "replenish",
    "replenishment", "warehouse", "deliveries", "delivery",
    # maintenance
    "maintenance", "repair", "repairs", "serviced", "pms", "preventive",
    "overdue", "mechanic", "mechanics", "history", "records", "record",
    # vehicles
    "vehicle", "vehicles", "fleet", "cars", "car", "trucks", "vans",
    # customers / staff
    "customer", "customers", "client", "clients", "staff", "users", "user",
    "admin",
    # booking
    "booking", "bookings", "appointment", "appointments", "schedule",
    "scheduled", "schedules", "booked", "reservation", "reschedule",
    "cancel", "cancelled",
    # services / pricing
    "service", "services", "price", "prices", "pricing", "cost", "costs",
    "catalog", "issuance", "issuances", "report", "reports",
    "transaction", "transactions", "summary", "overview", "available",
    "pending", "completed", "progress", "list", "show", "display",
    "generate", "create",
}

# ── Explicit typo map (covers short tokens edit-distance would miss) ─────────
_TYPO_MAP = {
    # inventory
    "inventry": "inventory", "invntory": "inventory", "invenory": "inventory",
    "inventoy": "inventory", "inventori": "inventory", "iventory": "inventory",
    "inventry": "inventory",
    # maintenance
    "maintenence": "maintenance", "maintanance": "maintenance",
    "maintnance": "maintenance", "maintance": "maintenance",
    "maintenace": "maintenance", "maintainance": "maintenance",
    "maintainence": "maintenance", "maintenence": "maintenance",
    # stock
    "stok": "stock", "stcok": "stock", "stck": "stock", "stolk": "stock",
    # booking / appointment
    "bookng": "booking", "bookin": "booking", "boking": "booking",
    "bokking": "booking", "bookngs": "bookings", "bokings": "bookings",
    "apointment": "appointment", "appoinment": "appointment",
    "appointmnt": "appointment", "apointments": "appointments",
    # vehicle
    "vehcle": "vehicle", "vehile": "vehicle", "vechile": "vehicle",
    "vehcile": "vehicle", "vihicle": "vehicle", "vehcles": "vehicles",
    "vechicles": "vehicles",
    # report / schedule / service
    "repot": "report", "reprot": "report", "reprt": "report",
    "scheduel": "schedule", "schdule": "schedule", "schedle": "schedule",
    "sched": "schedule", "appt": "appointment", "svc": "service",
    "servce": "service", "sevice": "service", "servic": "service",
    "servces": "services", "sevices": "services",
    # customer
    "custumer": "customer", "costumer": "customer", "cutomer": "customer",
    "custumers": "customers", "costumers": "customers",
    # issuance / delivery
    "isuance": "issuance", "issuace": "issuance", "issuences": "issuances",
    "delvery": "delivery", "delivey": "delivery", "deliveries": "deliveries",
    # preventive / replenish / restock
    "prevantive": "preventive", "preventve": "preventive",
    "replinish": "replenish", "replenesh": "replenish",
    "replenshment": "replenishment",
    "restck": "restock", "restocking": "restocking",
    # informal English
    "u": "you", "ur": "your", "pls": "please", "plz": "please",
    "plss": "please", "info": "information", "inv": "inventory",
    "wk": "week", "tmrw": "tomorrow",
    # common Filipino-English phrasing (safe, high-frequency)
    "magkano": "how much", "kailan": "when", "kelan": "when",
    "paano": "how", "pno": "how", "pwede": "can", "pede": "can",
    "nasaan": "where", "nasan": "where", "gusto": "want",
}

# ── Multi-word phrase fixes (applied after token correction) ──────────────────
_PHRASE_MAP = {
    "preventive maintenance": "preventive maintenance",  # normalizes via tokens
    "change oil": "change oil",
    "low stok": "low stock",   # handled by tokens; kept for clarity
}

_WORD_RE = re.compile(r"[a-z0-9]+")


def _d1_match(token: str) -> str | None:
    """Return a vocabulary word at edit distance 1 from *token*, else None.

    Edit distance 1 = one insertion, deletion, substitution, or adjacent
    transposition.  Only called for tokens of 5+ chars not already in vocab.
    """
    n = len(token)
    # deletions
    for i in range(n):
        cand = token[:i] + token[i + 1:]
        if cand in _VOCAB:
            return cand
    # substitutions
    for i in range(n):
        for ch in "abcdefghijklmnopqrstuvwxyz":
            if ch != token[i]:
                cand = token[:i] + ch + token[i + 1:]
                if cand in _VOCAB:
                    return cand
    # adjacent transpositions
    for i in range(n - 1):
        if token[i] != token[i + 1]:
            cand = token[:i] + token[i + 1] + token[i] + token[i + 2:]
            if cand in _VOCAB:
                return cand
    # insertions
    for i in range(n + 1):
        for ch in "abcdefghijklmnopqrstuvwxyz":
            cand = token[:i] + ch + token[i:]
            if cand in _VOCAB:
                return cand
    return None


def normalize(text: str) -> str:
    """
    Normalize *text* for intent detection only.

    - lowercase, punctuation -> space, whitespace collapsed
    - token-level: typo map / abbreviation / Filipino map / safe fuzzy fix
    - multi-word phrases preserved as-is (tokens joined by single spaces)
    """
    if not text:
        return ""
    t = text.lower().strip()
    t = re.sub(r"[^a-z0-9\s]", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    if not t:
        return t

    out = []
    for tok in t.split(" "):
        if not tok:
            continue
        if tok.isdigit() or tok in _VOCAB:
            out.append(tok)
            continue
        fixed = _TYPO_MAP.get(tok)
        if fixed is None and len(tok) >= 5:
            fixed = _d1_match(tok)
        out.append(fixed if fixed else tok)
    return " ".join(out)
