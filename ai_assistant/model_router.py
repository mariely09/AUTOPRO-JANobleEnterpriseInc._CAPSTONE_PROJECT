"""
model_router.py — Lightweight AI request router.

Classifies every incoming message into one of these intents:

  DATABASE_LOOKUP        → answer comes entirely from Firestore; no LLM needed
  DATABASE_CALCULATION   → numeric query answerable by Python after DB fetch
  SIMPLE_DB_EXPLANATION  → DB data + brief LLM phrasing (8B)
  GENERAL_AI_QUESTION    → general knowledge / educational (8B)
  COMPLEX_ANALYSIS       → multi-source reasoning, prioritisation (70B)
  REPORT_GENERATION      → generate PDF/Excel; LLM only to parse the request
  UNKNOWN                → fall through to default LLM tool-calling loop (8B)

Classification uses deterministic rules first (zero tokens).
No LLM is called for classification.

Model selection:
  DATABASE_LOOKUP / DATABASE_CALCULATION / REPORT_GENERATION → no model (or 8B for phrasing)
  GENERAL_AI_QUESTION / SIMPLE_DB_EXPLANATION / UNKNOWN      → PRIMARY (8B)
  COMPLEX_ANALYSIS                                            → SECONDARY (70B)
"""
import re
from config import settings
from input_normalizer import normalize as _normalize_input

# -- Intent constants ----------------------------------------------------------
DATABASE_LOOKUP        = "DATABASE_LOOKUP"
DATABASE_CALCULATION   = "DATABASE_CALCULATION"
SIMPLE_DB_EXPLANATION  = "SIMPLE_DB_EXPLANATION"
GENERAL_AI_QUESTION    = "GENERAL_AI_QUESTION"
COMPLEX_ANALYSIS       = "COMPLEX_ANALYSIS"
REPORT_GENERATION      = "REPORT_GENERATION"
UNKNOWN                = "UNKNOWN"

# -- Customer-specific intent constants ----------------------------------------
MY_VEHICLES                = "MY_VEHICLES"
MY_SERVICE_HISTORY         = "MY_SERVICE_HISTORY"
MY_BOOKINGS                = "MY_BOOKINGS"
SERVICE_RECOMMENDATION     = "SERVICE_RECOMMENDATION"
SERVICE_PRICES             = "SERVICE_PRICES"
CUSTOMER_MATERIALS         = "CUSTOMER_MATERIALS"
SERVICE_COST               = "SERVICE_COST"
MAINTENANCE_REMINDER       = "MAINTENANCE_REMINDER"
BOOK_SERVICE               = "BOOK_SERVICE"
UPDATE_BOOKING             = "UPDATE_BOOKING"
CANCEL_BOOKING             = "CANCEL_BOOKING"
GENERAL_SERVICE_INFORMATION = "GENERAL_SERVICE_INFORMATION"
GENERAL_CUSTOMER_SUPPORT   = "GENERAL_CUSTOMER_SUPPORT"
GENERAL_CONVERSATION       = "GENERAL_CONVERSATION"

# Intents that use the SECONDARY (70B) model
_SECONDARY_INTENTS = {COMPLEX_ANALYSIS}

# Intents that need NO LLM call at all (pure DB/Python response)
_NO_LLM_INTENTS = {DATABASE_LOOKUP, DATABASE_CALCULATION}


# -- Compiled patterns ---------------------------------------------------------

# DATABASE_LOOKUP - common structured-data requests
_DB_LOOKUP = re.compile(
    r"\b("
    r"show(\s+my|\s+all|\s+the)?\s+(vehicles?|fleet|cars?|trucks?|vans?|suvs?|"
    r"service\s+history|pms\s+history|maintenance\s+records?|bookings?|appointments?|"
    r"services?\s+offered|service\s+list|services?\s+available|service\s+prices?)|"
    r"(list|get|display)\s+(my\s+)?(vehicles?|bookings?|appointments?|"
    r"service\s+history|maintenance\s+records?)|"
    r"my\s+(vehicles?|fleet|cars?|bookings?|appointments?|service\s+history)|"
    r"(when\s+(was|is|are)\s+(my|the)\s+(last|latest|next|upcoming))|"
    r"(last|latest|next)\s+(service|oil\s+change|maintenance|pms|booking|appointment)|"
    r"(low\s+stock|reorder|running\s+low|out\s+of\s+stock|"
    r"almost\s+out|nearly\s+out|need[s]?\s+restock|\w+\s+stock|"
    r"what\s+\w+\s+is\s+low|which\s+\w+\s+(are|is)\s+low)|"
    r"(pending|completed|in[\s-]?progress)\s+(booking|maintenance|service|repair|job)|"
    r"(service|maintenance)\s+(booking|appointment)s?\s*(list|status|today|this\s+week)?|"
    r"(stock\s+level[s]?|inventory\s+list|current\s+stock|stock\s+status)|"
    r"(list|show|display|get|view)\s+(the\s+|all\s+|current\s+|our\s+)?"
    r"(inventory|stock|stock\s+items?|pms|maintenance|repairs?)\b|"
    r"(need|needs)\s+(restock|replenish|reorder)|"
    r"(what|which)\s+(items?|parts?|products?|supplies?)\s+need|"
    r"(items?|parts?|supplies?)\s+to\s+(restock|reorder)|"
    r"(list|show|all)\s+(deliveries|delivery|vehicles?|fleet|stock)|"
    r"pms\s+(status|schedule|due|overdue)|"
    r"(vehicle|car)\s+(status|list|registered|active|inactive)|"
    r"(booking|appointment)\s+(status|list|pending|confirmed|completed)|"
    # -- Service pricing queries -----------------------------------------------
    r"how\s+much\s+(is|for|does|would|are)|"
    r"(price|cost|rate|fee)\s+(of|for)\s+\w|"
    r"(service\s+price[s]?|service\s+rate[s]?|service\s+cost[s]?|pricing)|"
    r"(list|show|what|get)\s+(all\s+)?services?\b|"
    r"services?\s+(offered|available|you\s+offer|list)|"
    r"estimate\s+(the\s+)?cost|cost\s+estimate"
    r")\b",
    re.IGNORECASE,
)

# DATABASE_CALCULATION - "how many / count / total" questions
_DB_CALC = re.compile(
    r"\b(how\s+many|count\s+(of\s+)?|total\s+(number\s+of\s+)?)\s*"
    r"(vehicles?|cars?|bookings?|appointments?|services?|maintenance|jobs?|"
    r"customers?|users?|staff|deliveries|stock|items?|records?)\b",
    re.IGNORECASE,
)

# REPORT_GENERATION - explicit report requests
_REPORT = re.compile(
    r"\b(generate|create|make|build|produce|export|download|get)\s+"
    r"(a\s+|an\s+|the\s+)?"
    r"(inventory|issuance|maintenance|vehicle|fleet|booking|service|stock|"
    r"monthly|weekly|annual|yearly)\s*"
    r"(report|summary|pdf|excel|xlsx|spreadsheet)\b"
    r"|"
    r"\b(inventory|issuance|maintenance|vehicle|booking)\s+report\b",
    re.IGNORECASE,
)

# COMPLEX_ANALYSIS - multi-source reasoning, prioritisation
_COMPLEX = re.compile(
    r"\b("
    r"(based\s+on|given|considering|looking\s+at)\s+(my|the|all)?\s*"
    r"(maintenance|service|history|records?|data|vehicles?)|"
    r"what\s+should\s+i\s+(prioriti[sz]e|focus\s+on|do\s+first|fix\s+first)|"
    r"(prioriti[sz]e|recommend|suggest|advise)\s+(which|what|maintenance|service)|"
    r"(most\s+critical|most\s+urgent|highest\s+priority)\s+(maintenance|service|repair)|"
    r"(compare|comparison|vs\.?|versus)\s+(service|maintenance|vehicle|cost)|"
    r"analy[sz](e|is)\s+(my|the)?\s*(service|maintenance|history|cost|spending|pattern)|"
    r"(trends?|patterns?)\s+in\s+(my|the)?\s*(service|maintenance|cost|history)|"
    r"(detailed|comprehensive|full|complete)\s+(analysis|review|assessment|breakdown)\s+"
    r"of\s+(my|the|all)\s*(service|maintenance|vehicle|history|records?)|"
    r"what\s+(maintenance|service)s?\s+(is|are)\s+(most|critically|urgently)\s+(needed|overdue)|"
    r"(cost[s]?\s+analysis|spending\s+analysis|expense\s+analysis)"
    r")\b",
    re.IGNORECASE,
)

# GENERAL_AI_QUESTION - educational / general knowledge
_GENERAL = re.compile(
    r"\b("
    r"what\s+is\s+(preventive|pms|regular|scheduled|routine|major)\s+maintenance|"
    r"what\s+(is|are)\s+(engine\s+oil|transmission|coolant|brake\s+fluid|tire\s+rotation)|"
    r"(why|how)\s+(is|does|should|do)\s+.*(oil|maintenance|service|tire|brake|coolant|engine)|"
    r"what\s+does\s+(pms|preventive|regular\s+service|tune-?up|oil\s+change)\s+(mean|involve|include)|"
    r"(how\s+often|how\s+frequently)\s+should\s+(i|you|we)\s+(change|replace|check|service)|"
    r"(explain|describe|tell\s+me\s+about)\s+(preventive|regular|pms|scheduled)\s+maintenance|"
    r"(importance|benefit|reason)\s+(of|for)\s+(regular|routine|preventive)\s+(maintenance|service|oil)|"
    r"what\s+happens\s+if\s+(i|you|we)\s+(don.t|skip|delay|neglect)\s+(oil|maintenance|service)|"
    r"(tire|tyre)\s+rotation\s+(meaning|explained|important|benefit)"
    r")\b",
    re.IGNORECASE,
)


# -- Public classifier ---------------------------------------------------------

# -- Customer intent patterns --------------------------------------------------

_CUSTOMER_MY_VEHICLES = re.compile(
    r"\b(my\s+(vehicles?|cars?|fleet|truck|van|suv|motorbike|motorcycle)"
    r"|list\s+(my\s+)?(vehicles?|cars?|fleet)"
    r"|show\s+(my\s+)?(vehicles?|cars?|fleet)"
    r"|what\s+(vehicles?|cars?)\s+(do\s+i|i\s+have)"
    r"|how\s+many\s+(vehicles?|cars?)\s+(do\s+i|i\s+have)"
    r"|plate\s+number|my\s+plate"
    r"|registered\s+(vehicles?|cars?)|vehicles?\s+registered\s+to\s+me"
    r"|tell\s+me\s+about\s+my\s+(toyota|honda|ford|nissan|mitsubishi|isuzu|suzuki))\b",
    re.IGNORECASE,
)

_CUSTOMER_MY_HISTORY = re.compile(
    r"\b(my\s+service\s+history|my\s+(pms|maintenance)\s+history"
    r"|past\s+services?|service\s+records?|completed\s+services?"
    r"|my\s+last\s+(service|oil\s+change|maintenance|pms|check)"
    r"|when\s+(was|is)\s+(my\s+)?(last|latest)\s+(service|oil|maintenance|pms)"
    r"|show\s+(all\s+)?my\s+service"
    r"|how\s+much\s+(did\s+i|have\s+i)\s+spent?(\s+on)?"
    r"|total\s+(spend|spending|cost)\s+(on\s+)?(maintenance|service)"
    r"|services\s+(performed|done)\s+on\s+my"
    r"|service\s+history\s+(this\s+year|last\s+year|for\s+(my|this)))\b",
    re.IGNORECASE,
)

_CUSTOMER_MY_BOOKINGS = re.compile(
    r"\b(my\s+(bookings?|appointments?)"
    r"|show\s+(my\s+)?(bookings?|appointments?)"
    r"|upcoming\s+(service|appointment|booking)"
    r"|my\s+next\s+(service|appointment|booking)"
    r"|when\s+is\s+my\s+next\s+(service|appointment)"
    r"|do\s+i\s+have\s+any\s+(upcoming\s+)?(bookings?|appointments?)"
    r"|did\s+i\s+(book|schedule|have\s+a\s+booking)"
    r"|status\s+of\s+my\s+booking)\b",
    re.IGNORECASE,
)

_SERVICE_RECOMMENDATION = re.compile(
    r"\b(what\s+maintenance\s+(do\s+i|does\s+my|should\s+my)"
    r"|maintenance\s+(recommendation|needed|due|schedule)"
    r"|what\s+service\s+should\s+i\s+get"
    r"|is\s+my\s+car\s+due"
    r"|when\s+should\s+i\s+(get|have|do|schedule)\s+(an?\s+)?(oil\s+change|maintenance|service|pms)"
    r"|what\s+should\s+i\s+have\s+checked"
    r"|next\s+(maintenance|service|pms)\s+(for|due)"
    r"|recommend(ation)?s?\s+(for|on)\s+(maintenance|service)"
    r"|service\s+recommendation)\b",
    re.IGNORECASE,
)

_SERVICE_PRICES = re.compile(
    r"\b(how\s+much\s+(is|for|does|would|are)"
    r"|price\s+(of|for)"
    r"|service\s+price[s]?"
    r"|what\s+services?\s+(do\s+you\s+offer|are\s+available|can\s+i\s+book)"
    r"|list\s+(all\s+)?services?"
    r"|services?\s+(offered|available|you\s+offer)"
    r"|how\s+much\s+(is|for)\s+(a|an|the)?\s*pms"
    r"|show\s+(me\s+)?(your\s+)?service\s+prices?)\b",
    re.IGNORECASE,
)

_CUSTOMER_MATERIALS = re.compile(
    r"\b(do\s+you\s+(sell|carry|have|offer)\s+"
    r"(engine\s+oil|oil|brake\s+fluid|coolant|tire|parts?|materials?|products?)"
    r"|what\s+(materials?|products?|parts?)\s+do\s+you\s+(have|offer|sell|carry)"
    r"|engine\s+oil\s+(available|for\s+sale)"
    r"|products?\s+(available|for\s+sale|offered))\b",
    re.IGNORECASE,
)

_SERVICE_COST = re.compile(
    r"\b(how\s+much\s+(did|have)\s+i\s+(spend|spent|pay|paid)"
    r"|total\s+(cost|spend|spending|amount)\s+.*(service|maintenance|this\s+year)"
    r"|how\s+much\s+was\s+my\s+last\s+service"
    r"|cost\s+of\s+my\s+(last|previous|recent)\s+(service|maintenance)"
    r"|how\s+much\s+would\s+(a|an)\s+.+cost"
    r"|estimate\s+(the\s+)?cost\s+for)\b",
    re.IGNORECASE,
)

_MAINTENANCE_REMINDER = re.compile(
    r"\b(is\s+my\s+car\s+due\s+(for)?\s+maintenance"
    r"|what\s+maintenance\s+is\s+coming\s+up"
    r"|when\s+should\s+i\s+get\s+my\s+next\s+service"
    r"|overdue\s+maintenance|pms\s+(overdue|due|reminder|status|schedule)"
    r"|is\s+my\s+car\s+overdue"
    r"|maintenance\s+(reminder|alert|notification)"
    r"|due\s+(for\s+)?(maintenance|service|pms)"
    r"|upcoming\s+(maintenance|service|pms)"
    # "When is/should my next PMS/maintenance?" phrasings
    r"|when\s+(is|should|do)\s+(my|the|i)\s+(next\s+)?(pms|maintenance|service)"
    r"|when\s+is\s+my\s+next\s+(pms|maintenance|service)"
    r"|next\s+(pms|maintenance|service)\s+(date|due|schedule)"
    r"|when\s+should\s+i\s+schedule\s+my\s+next\s+(maintenance|pms|service)"
    r"|when\s+should\s+i\s+bring\s+my\s+(car|vehicle)"
    r"|when\s+should\s+i\s+schedule\s+my\s+(car|vehicle))\b",
    re.IGNORECASE,
)

_BOOK_SERVICE = re.compile(
    r"\b(i\s+want\s+to\s+book"
    r"|book\s+(me\s+)?(a\s+|an\s+)?(service|appointment|pms|oil\s+change|maintenance)"
    r"|book\s+me\s+(a\s+|an\s+)?"
    r"|schedule\s+(me\s+)?(a\s+|an\s+)?(service|appointment|maintenance|pms)"
    r"|schedule\s+(a\s+|an\s+)?(pms|oil\s+change|service|maintenance|appointment)\s+(for|on)"
    r"|make\s+(a\s+|an\s+)?(booking|appointment|reservation)"
    r"|i\s+(need|want)\s+to\s+(schedule|book)\s+(a|an)?"
    r"|how\s+do\s+i\s+book"
    r"|can\s+i\s+book"
    # informal / typo-tolerant booking phrasings
    r"|can\s+you\s+help\s+me\s+book"
    r"|help\s+me\s+book"
    r"|i\s+need\s+an?\s+(oil\s+change|pms|service)"
    r"|i\s+want\s+to\s+have\s+my\s+(car|vehicle)\s+serviced"
    r"|have\s+my\s+(car|vehicle)\s+serviced"
    r"|book\s+(a\s+)?preventive\s+maintenance"
    r"|can\s+you\s+schedule\s+(a\s+|my\s+)?(service|car|vehicle)"
    r"|can\s+you\s+book\s+my\s+(car|vehicle)"
    r"|can\s+i\s+schedule\s+my\s+(car|vehicle))\b",
    re.IGNORECASE,
)

_UPDATE_BOOKING = re.compile(
    r"\b(reschedule\s+(my\s+)?(booking|appointment)"
    r"|move\s+my\s+(appointment|booking)"
    r"|change\s+my\s+(appointment|booking)\s+(date|time|schedule)"
    r"|update\s+my\s+(booking|appointment)"
    r"|can\s+i\s+reschedule"
    r"|i\s+want\s+to\s+reschedule)\b",
    re.IGNORECASE,
)

_CANCEL_BOOKING = re.compile(
    r"\b(cancel\s+(my\s+)?(booking|appointment)"
    r"|i\s+want\s+to\s+cancel"
    r"|can\s+i\s+cancel\s+my\s+(booking|appointment)"
    r"|how\s+do\s+i\s+cancel)\b",
    re.IGNORECASE,
)

_GENERAL_SERVICE_INFO = re.compile(
    r"\b(what\s+services?\s+do\s+you\s+offer"
    r"|what\s+can\s+i\s+book"
    r"|how\s+does\s+booking\s+work"
    r"|what\s+information\s+do\s+i\s+need\s+to\s+(provide|book)"
    r"|how\s+do\s+i\s+(book|cancel|reschedule)"
    r"|can\s+i\s+(reschedule|cancel)\s+(my\s+)?(appointment|booking)"
    r"|what\s+is\s+(pms|preventive\s+maintenance|change\s+oil))\b",
    re.IGNORECASE,
)


def classify_customer_intent(message: str) -> str:
    """
    Classify a CUSTOMER message into a customer-specific intent.
    Returns a customer intent constant, or falls back to classify_intent()
    for generic admin/general intents.
    Never calls an LLM.
    """
    # Typo/abbreviation/informal normalization — routing only; the ORIGINAL
    # message is still what gets answered.
    t = _normalize_input(message) or message.strip()

    if _CANCEL_BOOKING.search(t):
        return CANCEL_BOOKING
    if _UPDATE_BOOKING.search(t):
        return UPDATE_BOOKING
    if _BOOK_SERVICE.search(t):
        return BOOK_SERVICE
    if _MAINTENANCE_REMINDER.search(t):
        return MAINTENANCE_REMINDER
    if _SERVICE_RECOMMENDATION.search(t):
        return SERVICE_RECOMMENDATION
    if _CUSTOMER_MY_VEHICLES.search(t):
        return MY_VEHICLES
    if _CUSTOMER_MY_HISTORY.search(t):
        return MY_SERVICE_HISTORY
    if _CUSTOMER_MY_BOOKINGS.search(t):
        return MY_BOOKINGS
    if _SERVICE_COST.search(t):
        return SERVICE_COST
    if _CUSTOMER_MATERIALS.search(t):
        return CUSTOMER_MATERIALS
    if _SERVICE_PRICES.search(t):
        return SERVICE_PRICES
    if _GENERAL_SERVICE_INFO.search(t):
        return GENERAL_SERVICE_INFORMATION
    # Fall through to generic classification for COMPLEX_ANALYSIS / GENERAL_AI_QUESTION
    generic = classify_intent(t)
    if generic in (DATABASE_LOOKUP, DATABASE_CALCULATION):
        return MY_SERVICE_HISTORY  # map ambiguous DB queries to service history
    return generic


def classify_intent(message: str) -> str:
    """
    Classify *message* using only deterministic rules.
    Returns one of the intent constants.  Never calls an LLM.
    """
    # Typo/abbreviation/informal normalization — routing only; the ORIGINAL
    # message is still what gets answered.
    t = _normalize_input(message) or message.strip()

    if _REPORT.search(t):
        return REPORT_GENERATION

    if _COMPLEX.search(t):
        return COMPLEX_ANALYSIS

    if _DB_CALC.search(t):
        return DATABASE_CALCULATION

    if _DB_LOOKUP.search(t):
        return DATABASE_LOOKUP

    if _GENERAL.search(t):
        return GENERAL_AI_QUESTION

    return UNKNOWN


def select_model(intent: str) -> str:
    """
    Return the Groq model name appropriate for *intent*.

    Rules:
      COMPLEX_ANALYSIS → secondary (70B)
      everything else  → primary (8B)

    DATABASE_LOOKUP / DATABASE_CALCULATION don't need an LLM at all, but if
    a phrasing call is still made the 8B model handles it just fine.
    """
    if intent in _SECONDARY_INTENTS:
        return settings.GROQ_MODEL_SECONDARY
    return settings.GROQ_MODEL_PRIMARY


def needs_llm(intent: str) -> bool:
    """
    Return False when the intent can be served entirely by backend logic
    (DB query + Python formatting) with no LLM involvement.
    """
    return intent not in _NO_LLM_INTENTS
