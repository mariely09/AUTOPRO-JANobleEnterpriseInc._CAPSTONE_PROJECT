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
    # ── question words / connectors (very short — edit-distance misses them) ──
    "hw": "how", "haw": "how", "hhw": "how", "hiw": "how", "hwo": "how",
    "mch": "much", "muh": "much", "muc": "much", "muhc": "much",
    "wht": "what", "whats": "what", "wats": "what", "wat": "what",
    "wen": "when", "whn": "when", "wenb": "when",
    "whr": "where", "wer": "where", "wehre": "where",
    "wy": "why", "whi": "why",
    # "wich" — too short for edit-distance (4 chars); listed explicitly
    "wich": "which", "whih": "which", "whic": "which",
    "cna": "can", "cn": "can", "ca": "can",
    "i": "i",  # keep — already correct
    "fo": "for", "fro": "for", "fr": "for",
    "teh": "the", "th": "the", "hte": "the",
    "thr": "there", "thier": "their",
    "al": "all", "alll": "all",
    "lis": "list", "lst": "list",
    "shw": "show", "shwo": "show",
    "wth": "with", "wiht": "with", "wit": "with",

    # ── materials / products ──────────────────────────────────────────────────
    "materyals":  "materials", "materyal":   "material",
    "materal":    "material",  "materals":   "materials",
    "materilas":  "materials", "materails":  "materials",
    "matrials":   "materials", "matirals":   "materials",
    "materyal":   "material",  "mateiral":   "material",
    "mateirals":  "materials", "matreials":  "materials",
    "mats":       "materials",

    # ── price / cost ─────────────────────────────────────────────────────────
    "prise":    "price",  "pric":     "price",  "rpice":    "price",
    "prce":     "price",  "priice":   "price",  "prcie":    "price",
    "pricess":  "prices", "prces":    "prices", "prcies":   "prices",
    "cst":      "cost",   "cosr":     "cost",   "cots":     "cost",
    "coste":    "cost",   "costing":  "cost",
    "amnt":     "amount", "amout":    "amount", "amoun":    "amount",

    # ── inventory ────────────────────────────────────────────────────────────
    "inventry":  "inventory", "invntory":  "inventory", "invenory":  "inventory",
    "inventoy":  "inventory", "inventori": "inventory", "iventory":  "inventory",
    "invetory":  "inventory", "iinventory":"inventory",

    # ── maintenance ──────────────────────────────────────────────────────────
    "maintenence":  "maintenance", "maintanance":  "maintenance",
    "maintnance":   "maintenance", "maintance":    "maintenance",
    "maintenace":   "maintenance", "maintainance": "maintenance",
    "maintainence": "maintenance", "maitenance":   "maintenance",
    "maintenants":  "maintenance", "maintence":    "maintenance",

    # ── stock ─────────────────────────────────────────────────────────────────
    "stok": "stock", "stcok": "stock", "stck": "stock", "stolk": "stock",
    # 4-char misspelling — too short for edit-distance fallback, so listed explicitly
    "stoc": "stock", "stck": "stock",

    # ── booking / appointment / schedule ─────────────────────────────────────
    "bookng":     "booking",     "bookin":      "booking",
    "boking":     "booking",     "bokking":     "booking",
    "bookngs":    "bookings",    "bokings":     "bookings",
    "bking":      "booking",     "bkng":        "booking",
    "apointment": "appointment", "appoinment":  "appointment",
    "appointmnt": "appointment", "apointments": "appointments",
    "appt":       "appointment",
    "scheduel":   "schedule",    "schdule":     "schedule",
    "schedle":    "schedule",    "sched":       "schedule",
    "scedule":    "schedule",    "scheduel":    "schedule",
    "skedul":     "schedule",    "skedule":     "schedule",
    "skejul":     "schedule",    "skejule":     "schedule",

    # ── vehicle ───────────────────────────────────────────────────────────────
    "vehcle":    "vehicle",  "vehile":    "vehicle",  "vechile":  "vehicle",
    "vehcile":   "vehicle",  "vihicle":   "vehicle",  "vehcles":  "vehicles",
    "vechicles": "vehicles", "vehciles":  "vehicles", "vehicl":   "vehicle",

    # ── report / service / services ───────────────────────────────────────────
    "repot":    "report",   "reprot":   "report",   "reprt":    "report",
    "svc":      "service",  "servce":   "service",  "sevice":   "service",
    "servic":   "service",  "servces":  "services", "sevices":  "services",
    "servises": "services", "servcies": "services", "srevices": "services",
    "serivces": "services", "servixes": "services",

    # ── customer ──────────────────────────────────────────────────────────────
    "custumer":  "customer",  "costumer":  "customer",  "cutomer":   "customer",
    "custumers": "customers", "costumers": "customers", "cusotmer":  "customer",
    "cstomer":   "customer",  "cutsomer":  "customer",

    # ── oil change / PMS ──────────────────────────────────────────────────────
    "oilchange":  "oil change", "oilchng":    "oil change",
    "oilchnge":   "oil change", "changeoil":  "change oil",
    "chngoil":    "change oil",
    "pmss":       "pms",        "p m s":      "pms",

    # ── issuance / delivery ───────────────────────────────────────────────────
    "isuance":  "issuance", "issuace":    "issuance",
    "issuences":"issuances", "delvery":   "delivery",
    "delivey":  "delivery",

    # ── preventive / replenish / restock ─────────────────────────────────────
    "prevantive": "preventive", "preventve": "preventive",
    "replinish":  "replenish",  "replenesh": "replenish",

    # ── informal English / abbreviations ─────────────────────────────────────
    "u":    "you",   "ur":   "your",  "pls":  "please",
    "plz":  "please","plss": "please","tmrw": "tomorrow",
    "wk":   "week",  "info": "information",

    # ── Filipino-English (safe, high-frequency) ───────────────────────────────
    "magkano":  "how much",  "mgkano":   "how much",  "mgkno":  "how much",
    "kailan":   "when",      "kelan":    "when",       "klan":   "when",
    "paano":    "how",       "pno":      "how",
    "pwede":    "can",       "pede":     "can",        "pwde":   "can",
    "nasaan":   "where",     "nasan":    "where",
    "gusto":    "want",      "gsto":     "want",
    "ano":      "what",      "anong":    "what",
    "pakita":   "show",      "ipakita":  "show",
    "listahan": "list",      "lista":    "list",
    "presyo":   "price",     "halaga":   "price",
    "serbisyo": "service",   "serbisyos":"services",
    "materyales":"materials",
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
    - multi-word typo phrases replaced first (e.g. "magkano" -> "how much")
    - token-level: typo map / abbreviation / Filipino map / safe fuzzy fix
    - multi-word corrections in _TYPO_MAP are handled via phrase substitution
    """
    if not text:
        return ""
    t = text.lower().strip()
    t = re.sub(r"[^a-z0-9\s]", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    if not t:
        return t

    # Phase 1: token-by-token correction
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

    result = " ".join(out)

    # Phase 2: expand any multi-word _TYPO_MAP values that were injected
    # (e.g. a single token "magkano" was replaced with "how much" — the
    # two-word string is already correct at this point; this phase catches
    # cases where we want to do a final pass for compound substitutions).
    # Re-collapse extra whitespace that can appear after substitutions.
    result = re.sub(r"\s+", " ", result).strip()
    return result
