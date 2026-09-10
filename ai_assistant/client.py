"""
LLM client using Groq (ONLY external AI provider).

Calls Groq with intelligent model routing:
  - qwen/qwen3.6-27b → primary / default model
  - qwen/qwen3.6-27b → secondary (same model; override via GROQ_MODEL_SECONDARY env)

Token usage is recorded after every call via token_tracker.
Rate-limit errors (HTTP 429) are surfaced as RateLimitedError so main.py
returns a friendly message instead of a 500.
AuthenticationError (HTTP 401) → InvalidApiKeyError.
Model-not-found (HTTP 404)     → InvalidApiKeyError with a model-specific message.
"""
import json
import logging
import re
import time

from reasoning_utils import strip_reasoning
from groq import Groq, BadRequestError, RateLimitError, AuthenticationError
from config import settings
from firestore_tools import TOOL_SCHEMAS, TOOL_FUNCTIONS
from verifier import verify_reply
import token_tracker

logger = logging.getLogger(__name__)

# Reused Groq client — constructing Groq(api_key=...) per call forces a fresh
# TLS handshake + connection setup on every request (~0.2-0.5 s of avoidable
# latency). One client is created per API key and reused for the process
# lifetime; a key change swaps the cached client.
_groq_client_cache: dict[str, "Groq"] = {}


# Probe ONCE per process whether the installed Groq SDK accepts
# `chat_template_kwargs` (newer SDKs pass it through to Groq, where Qwen3
# models use it to disable the internal thinking mode — faster AND cheaper
# because reasoning tokens are never generated). Older SDKs (e.g. 1.5.0)
# raise TypeError; we then fall back to a plain call for the process lifetime.
_thinking_disable_supported: bool | None = None


def create_with_optional_thinking_disable(client: "Groq", kwargs: dict):
    """
    Call client.chat.completions.create(**kwargs), adding the Qwen3
    thinking-disable parameter only when the installed SDK supports it.
    Never lets the SDK-arg mismatch escape as a user-facing error.
    """
    global _thinking_disable_supported
    if _thinking_disable_supported is not False:
        try:
            return client.chat.completions.create(
                **kwargs, chat_template_kwargs={"enable_thinking": False}
            )
        except TypeError as exc:
            if "chat_template_kwargs" in str(exc):
                _thinking_disable_supported = False
                logger.info(
                    "Installed Groq SDK does not support chat_template_kwargs — "
                    "falling back to plain calls (thinking disabled at the "
                    "prompt/output level instead)."
                )
            else:
                raise
    return client.chat.completions.create(**kwargs)


def get_groq_client(api_key: str | None = None) -> "Groq":
    """Return a process-level cached Groq client (keyed by API key)."""
    key = api_key or settings.GROQ_API_KEY
    if not key:
        raise InvalidApiKeyError(
            "No Groq API key configured. "
            "Set GROQ_API_KEY in the Render environment variables."
        )
    cached = _groq_client_cache.get(key)
    if cached is None:
        # timeout: fail fast instead of the SDK's 600 s default hang.
        cached = Groq(api_key=key, timeout=settings.GROQ_TIMEOUT_SECONDS)
        _groq_client_cache[key] = cached
    return cached


class RateLimitedError(Exception):
    """Raised when the Groq API key hits its daily/minute rate limit."""
    pass


class InvalidApiKeyError(Exception):
    """Raised when the Groq API key is invalid or revoked (HTTP 401)."""
    pass


# Keep backward-compat alias so main.py import still works
AllKeysRateLimitedError = RateLimitedError


def _build_report_prompt() -> str:
    """
    Build the REPORT GENERATION section of the Admin AI system prompt dynamically
    from REPORT_FILTERS — the single source of truth in report_generator.py.

    When a new report type or filter is added to REPORT_FILTERS, this prompt
    updates automatically with no manual editing required.
    """
    from report_generator import REPORT_FILTERS, REPORT_CONFIG

    today = __import__("datetime").date.today()

    filter_blocks = []
    for rtype, fkeys in REPORT_FILTERS.items():
        title = REPORT_CONFIG[rtype]["title"]
        keys_str = "\n".join(f"  - {k}" for k in fkeys)
        filter_blocks.append(f"{title} ({rtype})\n{keys_str}")

    all_types   = " | ".join(REPORT_FILTERS.keys())
    filter_text = "\n\n".join(filter_blocks)

    return f"""
════════════════════════════════════════════════════
  REPORT GENERATION BEHAVIOR
════════════════════════════════════════════════════

When the administrator requests a report, your ONLY job is to identify:
  1. report_type — which report they want
  2. format      — pdf or excel (default: pdf if not specified)
  3. filters     — extracted from natural language (do NOT invent values)

Do NOT explain your reasoning.
Do NOT display your internal decision making.
Do NOT show statements such as:
  "I identified..."  "I will now generate..."  "Report Type..."  "Filters..."
  "I will call the report generator..."  "I extracted..."

The administrator should only see the final confirmation and the appropriate
download button rendered by the frontend.

────────────────────────────────────────────────────
OUTPUT FORMAT RULES
────────────────────────────────────────────────────
If the user does NOT specify a format → default to PDF.
If the user explicitly requests Excel / XLSX / Spreadsheet → Excel only.
If the user requests BOTH PDF and Excel → both.

Never specify a format the administrator did not request.

Your reply MUST be one short sentence only. Examples:
  Correct:   "Your inventory report is ready."
  Incorrect: "I identified the report type as inventory and extracted the following filters..."

────────────────────────────────────────────────────
STRUCTURED REPORT PAYLOAD  ← REQUIRED FORMAT
────────────────────────────────────────────────────
After your one-sentence reply, you MUST output a JSON block on a new line
in EXACTLY this format so the backend can extract it:

```report_payload
{{
  "report_type": "<type>",
  "format": "<pdf|excel|both>",
  "filters": {{}}
}}
```

Rules for the JSON block:
- "report_type" must be one of: {all_types}
- "format" must be exactly "pdf", "excel", or "both"
- "filters" must contain ONLY keys the user explicitly mentioned (no invented values)
- Date filters (start_date, end_date, month) go inside "filters" too
- If no filters were mentioned, "filters" must be an empty object {{}}

Examples (apply same pattern for all other types/filters/formats):

User: Generate inventory report.
Reply: Your inventory report is ready.
```report_payload
{{"report_type":"inventory","format":"pdf","filters":{{}}}}
```

User: Generate low stock inventory report in Excel.
Reply: Your inventory report is ready.
```report_payload
{{"report_type":"inventory","format":"excel","filters":{{"status":"Low"}}}}
```

User: Generate issuance report for June 2026 in PDF and Excel.
Reply: Your issuance report is ready.
```report_payload
{{"report_type":"issuance","format":"both","filters":{{"month":"June {today.year}"}}}}
```

User: Generate completed maintenance report for July.
Reply: Your maintenance report is ready.
```report_payload
{{"report_type":"maintenance","format":"pdf","filters":{{"status":"Completed","month":"July {today.year}"}}}}
```

User: Generate active truck report.
Reply: Your vehicle fleet report is ready.
```report_payload
{{"report_type":"vehicles","format":"pdf","filters":{{"status":"Active","vehicle_type":"Truck"}}}}
```

User: Generate pending bookings report in Excel.
Reply: Your bookings report is ready.
```report_payload
{{"report_type":"bookings","format":"excel","filters":{{"status":"Pending"}}}}
```

────────────────────────────────────────────────────
REPORT FILTER RULES
────────────────────────────────────────────────────
Every filter the administrator mentions MUST be included.
Never generate the complete report if filters were provided.
Never assume or invent filter values not explicitly stated.
If no records match the filters, the backend will inform the administrator.

────────────────────────────────────────────────────
VEHICLE STATUS KEYWORD MAPPINGS
────────────────────────────────────────────────────
When filtering vehicles by status, map natural language to exact values:

  "active" / "in service" / "on track"    → status: "Active"
  "inactive" / "decommissioned" / "retired" → status: "Inactive"
  "under maintenance" / "in maintenance"
    / "due for maintenance" / "for maintenance"
    / "needs maintenance" / "being serviced"  → status: "Maintenance"
  "overdue" / "pms overdue"               → status: "Overdue"
  "due soon" / "pms due soon"             → status: "Due Soon"

VEHICLE TYPE KEYWORD MAPPINGS
────────────────────────────────────────────────────
Map plural forms to singular (the backend handles both, but use singular):
  "Trucks"  → vehicle_type: "Truck"
  "SUVs"    → vehicle_type: "SUV"
  "Sedans"  → vehicle_type: "Sedan"
  "Vans"    → vehicle_type: "Van"

────────────────────────────────────────────────────
SUPPORTED REPORT TYPES:  {all_types}
SUPPORTED FORMATS:       pdf | excel | both  (xlsx is also accepted as excel)
DEFAULT FORMAT:          pdf
────────────────────────────────────────────────────

AVAILABLE FILTERS PER REPORT TYPE:
(Only use filters the user explicitly mentioned. Never invent filter values.)

{filter_text}

────────────────────────────────────────────────────
DATE UNDERSTANDING  (today is {today})
────────────────────────────────────────────────────
Resolve natural language dates before including them in filters.

  "today"              → start_date = end_date = {today}
  "yesterday"          → start_date = end_date = (yesterday's date)
  "this week"          → start_date = Monday of current week, end_date = today
  "last week"          → start_date/end_date = Mon–Sun of last week
  "this month"         → month = "{today.strftime('%B %Y')}"
  "last month"         → month = (previous calendar month + year)
  "this year"          → start_date = {today.year}-01-01, end_date = {today.year}-12-31
  "last year"          → start_date = {today.year - 1}-01-01, end_date = {today.year - 1}-12-31
  "July"               → month = "July {today.year}"  (assume current year)
  "July 2026"          → month = "July 2026"
  "March 10, 2026"     → start_date = 2026-03-10  (exact day)
  "from March 1 to March 31"  → start_date = {today.year}-03-01, end_date = {today.year}-03-31
  "from July 1 until July 15" → start_date = {today.year}-07-01, end_date = {today.year}-07-15

Priority rule: if start_date or end_date is present, use them and leave month null.

════════════════════════════════════════════════════
"""


ADMIN_SYSTEM_PROMPT = """You are the internal AI assistant for the Automotive Service and Inventory Management System (Caltex AutoPro — JA Noble Enterprise Inc., Caltex San Pedro, Laguna).

STRICT SCOPE RESTRICTION — HIGHEST PRIORITY:
You ONLY answer questions that are directly related to this system's data:
inventory, stock levels, maintenance jobs, service bookings, vehicles/fleet,
issuances, deliveries, users/staff, reports, revenue/earnings, costs, sales
summaries, service income, financial summaries from bookings and maintenance,
and system usage questions.

This also includes questions asked in Filipino (Tagalog) about the same topics.
Examples of valid Filipino queries:
  "magkano ang total na kinita" → total revenue/earnings from services
  "ilang sasakyan" → how many vehicles
  "anong mga serbisyo" → what services
  "mga booking ngayong buwan" → bookings this month

If asked ANYTHING outside this scope (general knowledge, sports, news, science, coding,
math, recipes, weather, entertainment, or any non-system topic), respond with ONLY:
"I can only answer questions related to the Automotive Service and Inventory Management System."
Nothing else — no elaboration, no partial answers, no alternatives.

TOOLS (deterministic routing already answers most data lookups; you are the fallback):
- get_stock_levels / get_low_stock_items: inventory & low-stock queries
- get_item_catalog: materials+services catalog/prices (item_type='Service'|'Material')
- get_maintenance_jobs / get_maintenance_summary: service records, costs, revenue
- get_service_bookings: customer bookings; get_deliveries: supplier deliveries
- get_vehicles: fleet; get_user_count: users by role

Rules:
1. Use only tool-returned data. Never invent numbers, names, or records.
2. For any list/count/total/ranking, call the appropriate tool first.
3. Tool returns no data → "I could not find that information in the database."
4. Answer conversationally; use a table for multiple records; lead with the answer.
5. NEVER include tool parameters you don't have a value for — omit them.
6. Use conversation history for follow-ups. Revenue/earnings/cost questions are IN-SCOPE via maintenance/booking data.
7. Filipino (Tagalog) questions: respond in Filipino or English, whichever is clearer.

CRITICAL — Reformatting follow-ups ("make it a list", "simplify"): DO NOT call tools;
simply reformat your PREVIOUS answer.

Keyword mappings (English/Filipino): materials|parts|supplies|stock items|inventory→get_stock_levels;
services|serbisyo→get_item_catalog(item_type='Service'); all items|catalog|price list→get_item_catalog;
low stock|reorder|running low→get_low_stock_items; maintenance|repair jobs|service records|trabaho|ayos→
get_maintenance_jobs/get_maintenance_summary; bookings|appointments→get_service_bookings;
deliveries→get_deliveries; vehicles|fleet|sasakyan→get_vehicles; users|customers|staff→get_user_count;
sales|revenue|earnings|income|kita|magkano|bayad→get_maintenance_jobs (cost) or get_service_bookings.

"""

# REPORT_PROMPT_BLOCK — appended to the system prompt ONLY for report-related
# requests (see chat()).  Appending unconditionally cost ~1,700 tokens on every
# admin call, even "show inventory".
REPORT_PROMPT_BLOCK = _build_report_prompt()

# Matches report-generation requests for conditional prompt injection
_REPORT_REQUEST_RE = re.compile(
    r"\b(generate|create|make|build|produce|export|download|print)\b[^\n]{0,40}\b"
    r"(report|pdf|excel|xlsx|spreadsheet)\b|\b(report|pdf|excel)\s+report\b",
    re.IGNORECASE,
)

def _is_model_not_found(exc: Exception) -> bool:
    """Return True if the Groq error is a model_not_found / 404."""
    s = str(exc).lower()
    return (
        "model_not_found" in s
        or "does not exist" in s
        or "404" in s
        or "no access to it" in s
    )


def _call_groq(messages: list[dict], tools: list[dict] | None = None,
               model: str | None = None):
    """
    Thin wrapper around the Groq API call with token limits enforced.

    model — pass an explicit model string to override the default (8B).
    max_tokens is capped at GROQ_MAX_OUTPUT_TOKENS.
    RateLimitError  → re-raised as RateLimitedError (friendly rate-limit message).
    AuthenticationError → re-raised as InvalidApiKeyError (friendly auth message).

    Returns the raw Groq response (usage.prompt_tokens etc. available on it).
    """
    api_key = settings.GROQ_API_KEY
    if not api_key:
        raise InvalidApiKeyError(
            "No Groq API key configured. "
            "Set GROQ_API_KEY in the Render environment variables."
        )

    chosen_model = model or settings.GROQ_MODEL_PRIMARY

    try:
        import perf_metrics
        with perf_metrics.groq_timer():
            client = get_groq_client(api_key)
            kwargs: dict = {
                "model":      chosen_model,
                "messages":   messages,
                "max_tokens": settings.GROQ_MAX_OUTPUT_TOKENS,
            }
            if tools:
                kwargs["tools"] = tools
            resp = create_with_optional_thinking_disable(client, kwargs)
        try:
            u = resp.usage
            perf_metrics.record_usage(getattr(u, "prompt_tokens", 0) or 0,
                                      getattr(u, "completion_tokens", 0) or 0)
        except Exception:
            pass
        return resp
    except AuthenticationError as exc:
        logger.error(
            "Groq AuthenticationError (HTTP 401) — invalid or revoked API key. "
            "Raw error: %s", exc,
        )
        raise InvalidApiKeyError(
            "The Groq API key is invalid or has been revoked. "
            "Please update GROQ_API_KEY in the Render environment variables."
        ) from exc
    except RateLimitError as exc:
        logger.warning("Groq RateLimitError (HTTP 429): %s", exc)
        raise RateLimitedError(
            "The AI service has reached its daily usage limit (Groq free tier). "
            "Please try again later."
        ) from exc
    except Exception as exc:
        if _is_model_not_found(exc):
            logger.error(
                "Groq model_not_found for model=%s — check GROQ_MODEL_PRIMARY / "
                "GROQ_MODEL_SECONDARY env vars. Raw error: %s",
                chosen_model, exc,
            )
            raise InvalidApiKeyError(
                f"The AI model '{chosen_model}' is no longer available on Groq. "
                "Please update GROQ_MODEL_PRIMARY / GROQ_MODEL_SECONDARY in the "
                "Render environment variables to a currently supported model."
            ) from exc
        # Log the full exception so the real Groq error is visible in server
        # logs during development — the caller decides what to show the user.
        logger.error(
            "Groq API call failed (model=%s). %s: %s",
            chosen_model, type(exc).__name__, exc,
        )
        raise


def _strip_null_args(raw_args: str) -> dict:
    """
    Parse tool call arguments and remove any null/None/empty-string values.
    Groq validates args against the schema BEFORE returning to Python, so
    null optional params cause a 400. We strip them here as a safety net,
    but the schema's additionalProperties:false should prevent them reaching us.
    """
    if not raw_args or not raw_args.strip():
        return {}
    try:
        args = json.loads(raw_args)
    except json.JSONDecodeError:
        return {}
    if not isinstance(args, dict):
        return {}
    # Remove nulls and empty strings — optional params should just be absent
    return {k: v for k, v in args.items() if v is not None and v != ""}


def chat(user_message: str, history: list[dict] | None = None,
         model: str | None = None,
         intent: str = "UNKNOWN",
         user_id: str = "admin",
         _retry: bool = False) -> dict:
    """
    Admin LLM chat.

    model  — explicit model override; defaults to primary (8B).
    intent — the classified intent; used only for token-usage logging.
    user_id — admin session or UID; used only for token-usage logging.
    """
    from model_router import GENERAL_AI_QUESTION, COMPLEX_ANALYSIS
    from input_guard import truncate_message, build_request_context

    # Request-level memoization for read-only tools (dedupes repeated calls).
    import request_cache
    _bucket = request_cache.begin_request()
    tool_fns = request_cache.memoize(TOOL_FUNCTIONS, _bucket)

    # Oversized-input guard — a pasted document must never flood the model.
    safe_message = truncate_message(user_message, settings.MAX_INPUT_CHARS)

    # Trim history to GROQ_MAX_HISTORY_MSGS before building the payload.
    trimmed_history: list[dict] = []
    if history:
        valid = [m for m in history if isinstance(m, dict) and "role" in m]
        trimmed_history = valid[-settings.GROQ_MAX_HISTORY_MSGS:]

    chosen_model = model or settings.GROQ_MODEL_PRIMARY

    # Conditional report block: the ~1,700-token report instructions are only
    # needed when the user is actually requesting a report.
    system_prompt = ADMIN_SYSTEM_PROMPT
    if _REPORT_REQUEST_RE.search(safe_message):
        system_prompt += REPORT_PROMPT_BLOCK

    # Per-request token budget: trims history deterministically rather than
    # sending an oversized context to Groq.
    messages, _budget_stats = build_request_context(
        system_prompt,
        trimmed_history,
        safe_message,
        history_max_msgs=settings.GROQ_MAX_HISTORY_MSGS,
        history_msg_max_chars=settings.HISTORY_MSG_MAX_CHARS,
        budget_tokens=settings.ADMIN_MAX_REQUEST_TOKENS,
    )

    tool_call_log = []
    final_reply = ""
    t0 = time.time()
    call_succeeded = True

    for _ in range(max(1, settings.MAX_TOOL_LOOP_TURNS)):
        try:
            response = _call_groq(messages, tools=TOOL_SCHEMAS, model=chosen_model)
        except (RateLimitError, AllKeysRateLimitedError):
            call_succeeded = False
            raise
        except BadRequestError as e:
            error_str = str(e)
            logger.warning("Groq BadRequestError: %s", error_str)
            call_succeeded = False

            if "tool" in error_str.lower() or "function" in error_str.lower():
                try:
                    fallback = _call_groq(messages, model=chosen_model)
                    _record_usage(fallback, chosen_model, intent, user_id, True,
                                  time.time() - t0)
                    final_reply = fallback.choices[0].message.content or \
                        "I could not retrieve that information. Please try rephrasing."
                    request_cache.end_request(_bucket)
                    return {
                        "reply": final_reply,
                        "tool_calls": tool_call_log,
                        "verified": True,
                        "unsupported_numbers": [],
                        "model": chosen_model,
                        "intent": intent,
                    }
                except (RateLimitError, AllKeysRateLimitedError):
                    raise
                except Exception as fallback_err:
                    logger.error("Fallback call also failed: %s", fallback_err)

            request_cache.end_request(_bucket)
            return {
                "reply": "I could not retrieve that information. Please try rephrasing your question.",
                "tool_calls": tool_call_log,
                "verified": True,
                "unsupported_numbers": [],
                "model": chosen_model,
                "intent": intent,
            }

        msg = response.choices[0].message
        # Defense in depth: even with thinking disabled, strip any
        # <think>...</think> reasoning the model still emitted so the
        # customer only ever sees the final answer.
        msg.content = strip_reasoning(msg.content or "")
        assistant_msg: dict = {"role": "assistant", "content": msg.content or ""}
        if msg.tool_calls:
            assistant_msg["tool_calls"] = [tc.model_dump() for tc in msg.tool_calls]
        messages.append(assistant_msg)

        if not msg.tool_calls:
            final_reply = msg.content or ""
            _record_usage(response, chosen_model, intent, user_id, True,
                          time.time() - t0)
            break

        for call in msg.tool_calls:
            fn_name = call.function.name
            fn_args = _strip_null_args(call.function.arguments or "")

            fn = tool_fns.get(fn_name)
            if fn is None:
                result = {"error": f"Unknown tool '{fn_name}'"}
            else:
                try:
                    result = fn(**fn_args)
                except Exception as e:
                    result = {"error": str(e)}

            tool_call_log.append({"tool": fn_name, "args": fn_args, "result": result})

            result_json = json.dumps(result)
            max_chars   = settings.GROQ_MAX_TOOL_RESULT_CHARS
            if len(result_json) > max_chars:
                result_json = result_json[:max_chars] + \
                    '... [TRUNCATED — too many records. Summarise from the data shown above.]"}'
                logger.info("Tool result for '%s' truncated to %d chars.", fn_name, max_chars)

            messages.append({
                "role":         "tool",
                "tool_call_id": call.id,
                "content":      result_json,
            })
    else:
        final_reply = "Sorry, I had trouble completing that request."

    request_cache.end_request(_bucket)

    if tool_call_log:
        check = verify_reply(final_reply, tool_call_log)
        if not check["verified"] and not _retry:
            # Token-efficient correction: send ONLY the tool data (compacted) +
            # correction instruction — NOT the entire previous conversation.
            compact_results = json.dumps(tool_call_log, default=str)
            if len(compact_results) > 2500:
                compact_results = compact_results[:2500] + '... [truncated]'
            correction_prompt = (
                f"Your previous answer contained number(s) that do not match the data "
                f"retrieved: {check['unsupported_numbers']}. "
                f"The only valid numbers from the actual tool results are: {check['source_numbers']}. "
                f"Re-answer the original question using ONLY these numbers. "
                f"If you cannot answer accurately with this data, say so explicitly."
            )
            correction_messages = [
                {"role": "system", "content": "Answer using ONLY the provided tool data. Be concise."},
                {"role": "user", "content": f"Original question: {user_message}\n\nTool data: {compact_results}\n\n{correction_prompt}"},
            ]
            try:
                correction_resp = _call_groq(correction_messages, model=chosen_model)
                _record_usage(correction_resp, chosen_model, intent, user_id, True,
                              time.time() - t0)
                final_reply = strip_reasoning(
                    correction_resp.choices[0].message.content or "") or final_reply
                check = verify_reply(final_reply, tool_call_log)
            except Exception:
                # Correction is best-effort; never let it kill the original answer
                logger.warning("Correction pass failed; keeping original reply", exc_info=True)

        return {
            "reply":                final_reply,
            "tool_calls":           tool_call_log,
            "verified":             check["verified"],
            "unsupported_numbers":  check["unsupported_numbers"],
            "model":                chosen_model,
            "intent":               intent,
        }

    return {
        "reply":               final_reply,
        "tool_calls":          tool_call_log,
        "verified":            True,
        "unsupported_numbers": [],
        "model":               chosen_model,
        "intent":              intent,
    }


def _record_usage(response, model: str, intent: str, user_id: str,
                  success: bool, elapsed_s: float) -> None:
    """Extract token counts from a Groq response and record them."""
    try:
        usage = getattr(response, "usage", None)
        if usage:
            token_tracker.record(
                user_id=user_id,
                role="admin",
                model=model,
                intent=intent,
                input_tokens=getattr(usage, "prompt_tokens", 0),
                output_tokens=getattr(usage, "completion_tokens", 0),
                response_ms=elapsed_s * 1000,
                success=success,
            )
    except Exception:
        pass  # never let tracking crash the main request
