"""
access_control.py — centralized authorization gate for the Customer AI.

Runs AFTER intent classification but BEFORE any Firestore read or LLM call
(token + read + latency cost of a denied request: zero).

Categories denied for the customer role (spec #3-#10):
  OTHER_CUSTOMER_DATA   — another person's bookings/vehicles/history/records
  INVENTORY             — stock levels, quantities, low stock, restocking
  ISSUANCE              — internal issuance/delivery records
  ADMIN_REPORT          — report/PDF/Excel generation
  BUSINESS_ANALYTICS    — customer-wide / business-wide aggregates
  OFF_TOPIC             — non-system topics (already handled elsewhere; kept
                          here so every denial uses one consistent path)

Every check is deterministic (regex over a typo-normalized message) so the
LLM is never the security boundary (spec #11) and denials cost 0 tokens.

Denial replies match the user's language (spec #17): Tagalog/Taglish inputs
get a Taglish reply; everything else gets English.
"""

import re
from typing import Optional

# ── Language detection (for reply language matching) ──────────────────────────
_TAGALOG_MARKERS = re.compile(
    r"\b(ng|nga|naman|po|opo|ba|yung|ung|ko|akin|aking|sakin|sa|na|para|"
    r"kayo|ikaw|ako|kami|hindi|wala|may|meron|pakita|ipakita|makita|"
    r"pwede|pede|puwede|kailan|kelan|magkano|magpa|paano|lahat|tanong|"
    r"salamat|gusto|kita|niya|kanya|ako|kung|dahil|kung|ito|yan|yon|"
    r"regenerate|gawa|mo|kayo|nila|amin|atin)\b",
    re.IGNORECASE,
)


def _is_taglish(text: str) -> bool:
    return bool(_TAGALOG_MARKERS.search(text or ""))


# ── Other-customer detection ─────────────────────────────────────────────────
# Filipino possessive "ni <Name>" / "nina <Names>" / "kay <Name>"
_FIL_OWNER = re.compile(
    r"\b(?:ni|nina|kay|kina)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)", re.UNICODE | re.IGNORECASE,
)

# English patterns: "<Name>'s <thing>" / "<Name>s' <thing>" — the possessive
# is MANDATORY so "What are my bookings" can never match. Separate patterns
# below cover "of customer <Name>" and "belong(s) to <name>".
_EN_OWNER = re.compile(
    r"\b([A-Za-z][a-z]+(?:\s+[A-Za-z][a-z]+)*)(?:'s|s')\s+"
    r"(bookings?|vehicles?|cars?|maintenance|history|records?|profile|account|"
    r"pms|services?|appointments?|information|details?|data)",
    re.IGNORECASE,
)

# "of customer <name>" / "belong(s) to <name>" / "bookings of <name>" /
# "show <name>'s" — works on both original (capitalized) and normalised
# (lowercased) text because IGNORECASE is set and the name group accepts
# lower-case letters too.
_EN_OWNER2 = re.compile(
    r"(?:"
    r"\bof\s+(?:customer|client|user)\s+"          # "of customer Carla"
    r"|\bbelong(?:s)?\s+to\s+"                     # "belongs to Juan"
    r"|\bshow\s+(?:the\s+)?(?:bookings?|history|vehicles?|records?|maintenance)\s+of\s+"  # "show bookings of"
    r"|\b(?:bookings?|history|vehicles?|records?|maintenance)\s+of\s+(?:customer\s+|client\s+)?"  # "bookings of customer"
    r")"
    r"([A-Za-z][a-z]+(?:\s+[A-Za-z][a-z]+)*|another\s+customer|other\s+customers?)",
    re.IGNORECASE,
)

# Self-reference pronouns — if the message refers to the customer themselves
# (my/ko/akin/...), any name-like capitalized word is ignored (it may be the
# customer's own name or a greeting artifact).
_SELF_REF = re.compile(
    r"\b(my|mine|ko|akin|aking|sakin|ako|sarili|own|i|me)\b",
    re.IGNORECASE,
)

# Explicit "another/other customer" references
_OTHER_CUSTOMER = re.compile(
    r"\b(other\s+customers?|another\s+customers?|different\s+customer|"
    r"all\s+customers?|every\s+customer|customer\s+w\w*de|"
    r"lahat\s+ng\s+(?:customers?|users?|accounts?)|"
    r"ibang\s+(?:customer|users?|tao)|"
    r"customers?\s+(?:records?|list|lista|bookings?|data))\b",
    re.IGNORECASE,
)

# Proper names of people (heuristic: two capitalized words, or single
# capitalized word that is a known first name and NOT a system term)
_KNOWN_FIRST_NAMES = {
    # Common English names
    "juan", "maria", "jose", "pedro", "ana", "anna", "james", "john", "jane",
    "mike", "michael", "david", "chris", "christopher", "daniel", "mark",
    "paul", "tony", "lisa", "grace", "joy", "angel", "karen", "sharon",
    "jim", "jun", "nena", "ningning", "rosa", "lorna", "beth",
    # Additional common Filipino names (covers the demo/test cases)
    "carla", "carlo", "carlos", "jessica", "jennifer", "maricel", "maricon",
    "rhea", "rhen", "rhenz", "myra", "mylene", "vanessa", "veronica",
    "cherry", "charry", "charlene", "clarisse", "clarise", "clarice",
    "joanne", "joanna", "joane", "dianne", "diana", "diane", "raquel",
    "marilou", "maribel", "maricel", "maricris", "maricar", "maricor",
    "eden", "edna", "evelyn", "elvie", "elaine", "elisa", "elisea",
    "ferdinand", "felimon", "felicidad", "felicia", "fely",
    "george", "gerald", "geraldine", "gloria", "grace",
    "henry", "harold", "harvey", "helen", "herma", "herminia",
    "irma", "imelda", "iris", "isabel", "isabelita",
    "liza", "lizabeth", "luz", "lurdes", "lourdes",
    "noel", "noemi", "norma", "nora", "norbert",
    "oliver", "olivia", "oscar", "ofelia",
    "perla", "patricia", "patrick", "peter",
    "ramon", "ramos", "randy", "raymond", "rhoda", "richard", "roberto",
    "roger", "rolando", "romeo", "ronald", "rosario", "rose", "roselyn",
    "sonia", "susan", "susana", "stella",
    "victor", "victoria", "villafranca", "vincent",
    "william", "willy", "winnie",
}
# Words that look like names but are system terms — never treat as people.
_NOT_NAMES = {
    "caltex", "autopro", "pms", "toyota", "honda", "ford", "hyundai",
    "kia", "nissan", "suzuki", "mitsubishi", "mazda", "bmw", "innova",
    "vios", "raptor", "ranger", "habal", "fortuner", "montero", "hillux",
}

_NAME_LIKE = re.compile(r"\b([A-Z][a-z]{2,})\b")


def _other_customer_reference(text: str) -> bool:
    """
    True when the message references data belonging to a DIFFERENT person:
    "Juan Dela Cruz's bookings", "booking ni Juan", "of customer Maria",
    "belong to another customer", "lahat ng customers", etc.
    A plain self-reference ("my bookings", "PMS history ko") never triggers it.
    """
    t = text or ""

    # Explicit other/all-customer phrasing first (no name needed).
    if _OTHER_CUSTOMER.search(t):
        return True

    # English possessive of a named person before a data noun
    if _EN_OWNER.search(t):
        return True

    # "of customer X" / "belong(s) to X"
    if _EN_OWNER2.search(t):
        return True

    # Filipino possessive "ni <Name>" / "kay <Name>"
    if _FIL_OWNER.search(t):
        return True

    # A self-referencing message without any third-party marker is allowed.
    if _SELF_REF.search(t):
        return False

    # Known first name used as an owner ("show juan bookings", "si juan")
    lowered = t.lower()
    for name in _KNOWN_FIRST_NAMES:
        if re.search(rf"\b{name}\b", lowered):
            return True

    return False


# ── Restricted categories ─────────────────────────────────────────────────────
_INVENTORY_RE = re.compile(
    r"\b(inventory|invntory|inventry|stock|stok|stocks|"
    r"reorder|restock\w*|replenish\w*|supplier|suppliers|"
    r"warehouse|purchase\s+order|purchase\s+orders|\bpo\s+number|"
    r"low\s+stock|stocks?\s+level|stocks?\s+status|in\s+stock|"
    r"how\s+many\s+(bottles?|liters?|litres?|pieces?|units?|cans?|drums?)|"
    r"how\s+much\s+\S+\s+(do\s+you\s+have|is\s+available|available)|"
    r"brake\s+pads?\s+(in\s+)?stock|may\s+stock|stock\s+pa|"
    r"meron\s+pa\s+ba\s+kayong|mayroon\s+pa\s+ba\s+kayong|"
    # "what products are running low" / "what parts are almost out" /
    # "which items are running low" — stock-depletion phrasings without the
    # word "stock" itself.
    r"(products?|parts?|items?|materials?)\s+(are\s+)?(running\s+low|"
    r"almost\s+(out|gone)|nearly\s+(out|gone)|out\s+of\s+stock|"
    r"need(s)?\s+(reSTOCKING|reORDER|rePLENISH\w*)|"
    r"low\s+on\s+stock)|"
    r"running\s+low\s+on\s+(products?|parts?|items?|materials?|stock))\b",
    re.IGNORECASE,
)

_ISSUANCE_RE = re.compile(
    r"\b(issuance|issuances|issuence|issuance\s+history|"
    r"delivered|deliveries|delivery\s+records?|"
    r"items?\s+(?:that\s+were\s+)?issued|issued\s+(?:today|this\s+week))\b",
    re.IGNORECASE,
)

_REPORT_RE = re.compile(
    r"\b(generate|create|make|produce|export|download|pa-?generate|"
    r"pa\s?generate|gawan|gumawa)\b[^.?!]*\b(report|pdf|excel|xlsx|"
    r"spreadsheet|csv|export)\b|"
    r"\b(report|pdf|excel)\s+(na|naman|po)\b|"
    r"\b(monthly|weekly|daily|annual)\s+(report|pdf|excel)\b|"
    r"\binventory\s+report|issuance\s+report|maintenance\s+report|"
    r"booking\s+report|sales\s+report|stock\s+report|"
    r"\bpdf\s+report\b",
    re.IGNORECASE,
)

_ANALYTICS_RE = re.compile(
    r"\b(how\s+many\s+(customers?|users?|accounts?|vehicles?|cars?|bookings?|"
    r"maintenances?|services?)\s+(do|did|were|are|have)|"
    r"how\s+many\s+(vehicles?|cars?)\s+(are\s+)?registered|"
    r"(total|overall|business[-\s]?wide|company[-\s]?wide|"
    r"monthly|weekly|annual)\s+(revenue|sales|income|earnings)|"
    r"how\s+much\s+revenue|revenue\s+(did|this|last|per)|"
    r"most\s+popular\s+(service|item)|top\s+selling|"
    r"(all|every)\s+(maintenance|maintenances|services?|bookings?)\b(?!.*\b(my|ako|ko|akin)\b)|"
    r"serviced\s+this\s+month|total\s+inventory\s+value|"
    r"(most|least)\s+popular|popular\s+(service|item)|"
    r"best[-\s]?selling|top\s+\d+|"
    r"show\s+all\s+(bookings?|vehicles?|customers?|maintenance|records?)|"
    r"lahat\s+ng\s+(bookings?|vehicles?|maintenance|records?|services?)|"
    r"bookings?\s+ng\s+customers?)\b",
    re.IGNORECASE,
)

_OFF_TOPIC_RE = re.compile(
    r"\b(weather|news|sports|politics|celebrit\w+|recipe|joke|game|movie|"
    r"music|song|love\s+advice|horoscope)\b",
    re.IGNORECASE,
)


class DenialCategory:
    OTHER_CUSTOMER_DATA = "OTHER_CUSTOMER_DATA"
    INVENTORY = "INVENTORY"
    ISSUANCE = "ISSUANCE"
    ADMIN_REPORT = "ADMIN_REPORT"
    BUSINESS_ANALYTICS = "BUSINESS_ANALYTICS"
    OFF_TOPIC = "OFF_TOPIC"


# Denial messages per category, per language style.
_MESSAGES = {
    DenialCategory.OTHER_CUSTOMER_DATA: {
        "en": ("Sorry, you don't have access to other customers' information. "
               "I can only help with information related to your own account, "
               "vehicles, maintenance history, and bookings."),
        "tl": ("Sorry, hindi po available sa inyong account ang impormasyon ng "
               "ibang customer. Maaari lang po kitang tulungan tungkol sa "
               "inyong sariling vehicles, maintenance history, at bookings."),
    },
    DenialCategory.INVENTORY: {
        "en": ("Sorry, inventory and stock information is only available to "
               "authorized staff or administrators. I can still help you with "
               "services, your vehicle, maintenance history, or bookings."),
        "tl": ("Sorry, hindi po available sa customer accounts ang inventory "
               "at stock information. Maaari po kitang tulungan sa services, "
               "inyong vehicle, maintenance history, o bookings."),
    },
    DenialCategory.ISSUANCE: {
        "en": ("Sorry, issuance records are internal system information and "
               "are only accessible to authorized staff or administrators."),
        "tl": ("Sorry, ang issuance records ay internal na impormasyon at "
               "para lang po sa authorized staff o administrators."),
    },
    DenialCategory.ADMIN_REPORT: {
        "en": ("Sorry, administrative report generation is only available to "
               "authorized administrators. I can help you with your own "
               "service history or bookings instead."),
        "tl": ("Sorry, ang pag-generate ng administrative reports ay para "
               "lang po sa authorized administrators. Maaari po kitang "
               "tulungan sa inyong service history o bookings."),
    },
    DenialCategory.BUSINESS_ANALYTICS: {
        "en": ("Sorry, business-wide analytics and management information are "
               "restricted to authorized staff and administrators. I can help "
               "you with your own vehicles, maintenance, or bookings."),
        "tl": ("Sorry, ang business-wide analytics at management information "
               "ay nakareserba po sa authorized staff at administrators. "
               "Maaari po kitang tulungan sa inyong vehicles, maintenance, o "
               "bookings."),
    },
    DenialCategory.OFF_TOPIC: {
        "en": ("I can only answer questions related to the Automotive Service "
               "and Inventory Management System."),
        "tl": ("Pasensya na po, mga tanong lang po tungkol sa Automotive "
               "Service and Inventory Management System ang nasagot ko."),
    },
}


def classify_denial(message: str) -> Optional[str]:
    """
    Return a DenialCategory constant if this customer request is unauthorized,
    or None if it may proceed to data retrieval / the LLM.
    Deterministic — no Firestore, no LLM.
    """
    from input_normalizer import normalize as _norm
    # Normalized copy (typo tolerance: "invntory", "issuence", "bookng"...).
    # The ORIGINAL text is used for name/capitalization checks.
    t = _norm(message or "") or (message or "")
    orig = message or ""

    # Order matters: most specific first. Third-party checks run against the
    # ORIGINAL text (capitalized names) AND the normalized copy (typo'd text).
    if _other_customer_reference(orig) or _other_customer_reference(t):
        return DenialCategory.OTHER_CUSTOMER_DATA
    if _REPORT_RE.search(t):
        return DenialCategory.ADMIN_REPORT
    if _ISSUANCE_RE.search(t):
        return DenialCategory.ISSUANCE
    if _INVENTORY_RE.search(t):
        return DenialCategory.INVENTORY
    if _ANALYTICS_RE.search(t):
        return DenialCategory.BUSINESS_ANALYTICS
    if _OFF_TOPIC_RE.search(t):
        return DenialCategory.OFF_TOPIC
    return None


def denial_message(category: str, message: str = "") -> str:
    """Access-denied reply, matching the user's language style."""
    lang = "tl" if _is_taglish(message or "") else "en"
    return _MESSAGES[category][lang]
