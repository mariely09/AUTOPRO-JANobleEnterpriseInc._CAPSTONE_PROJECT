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

# ── Intent constants ──────────────────────────────────────────────────────────
DATABASE_LOOKUP        = "DATABASE_LOOKUP"
DATABASE_CALCULATION   = "DATABASE_CALCULATION"
SIMPLE_DB_EXPLANATION  = "SIMPLE_DB_EXPLANATION"
GENERAL_AI_QUESTION    = "GENERAL_AI_QUESTION"
COMPLEX_ANALYSIS       = "COMPLEX_ANALYSIS"
REPORT_GENERATION      = "REPORT_GENERATION"
UNKNOWN                = "UNKNOWN"

# Intents that use the SECONDARY (70B) model
_SECONDARY_INTENTS = {COMPLEX_ANALYSIS}

# Intents that need NO LLM call at all (pure DB/Python response)
_NO_LLM_INTENTS = {DATABASE_LOOKUP, DATABASE_CALCULATION}


# ── Compiled patterns ─────────────────────────────────────────────────────────

# DATABASE_LOOKUP — common structured-data requests
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
    r"(low\s+stock|reorder|running\s+low|out\s+of\s+stock)|"
    r"(pending|completed|in[\s-]?progress)\s+(booking|maintenance|service|repair|job)|"
    r"(service|maintenance)\s+(booking|appointment)s?\s*(list|status|today|this\s+week)?|"
    r"(stock\s+level|inventory\s+list|current\s+stock|stock\s+status)|"
    r"(list|show|all)\s+(deliveries|delivery|vehicles?|fleet|stock)|"
    r"pms\s+(status|schedule|due|overdue)|"
    r"(vehicle|car)\s+(status|list|registered|active|inactive)|"
    r"(booking|appointment)\s+(status|list|pending|confirmed|completed)"
    r")\b",
    re.IGNORECASE,
)

# DATABASE_CALCULATION — "how many / count / total" questions
_DB_CALC = re.compile(
    r"\b(how\s+many|count\s+(of\s+)?|total\s+(number\s+of\s+)?)\s*"
    r"(vehicles?|cars?|bookings?|appointments?|services?|maintenance|jobs?|"
    r"customers?|users?|staff|deliveries|stock|items?|records?)\b",
    re.IGNORECASE,
)

# REPORT_GENERATION — explicit report requests
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

# COMPLEX_ANALYSIS — multi-source reasoning, prioritisation
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

# GENERAL_AI_QUESTION — educational / general knowledge
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


# ── Public classifier ─────────────────────────────────────────────────────────

def classify_intent(message: str) -> str:
    """
    Classify *message* using only deterministic rules.
    Returns one of the intent constants.  Never calls an LLM.
    """
    t = message.strip()

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
