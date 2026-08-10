"""
LLM client using Groq (fast cloud inference, OpenAI-compatible API).

API key rotation is handled transparently by ApiKeyManager:
  - On RateLimitError the manager puts the current key into cooldown and
    returns the next available key.
  - The chat() function retries up to MAX_RETRY_ATTEMPTS times across
    different keys before giving up.
  - If all keys are exhausted an AllKeysRateLimitedError is raised so
    main.py can return the standard friendly rate-limit message.
"""
import json
import logging
from groq import Groq, BadRequestError, RateLimitError
from config import settings
from firestore_tools import TOOL_SCHEMAS, TOOL_FUNCTIONS
from verifier import verify_reply
from api_key_manager import get_manager

logger = logging.getLogger(__name__)


class AllKeysRateLimitedError(Exception):
    """Raised when every configured Groq API key is rate-limited or in cooldown."""
    pass

logger = logging.getLogger(__name__)


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

If a user asks ANYTHING outside this scope — including but not limited to:
general knowledge, sports, current events, unrelated news, history, science, coding,
math, recipes, weather, entertainment, or any other non-system topic —
you MUST respond with ONLY this exact text, nothing else:
"I can only answer questions related to the Automotive Service and Inventory Management System."

Do NOT elaborate, apologize, or add any additional information.
Do NOT attempt to answer even partially.
Do NOT say "I don't know" or offer alternatives.
Just return that one sentence and nothing more.

The data you have access to:
- Stock/Inventory: physical parts and supplies with current stock levels (use get_stock_levels, get_low_stock_items)
- Item Catalog: master list of all Materials and Services offered with prices (use get_item_catalog)
- Maintenance Jobs: service/repair records per vehicle including costs (use get_maintenance_jobs, get_maintenance_summary)
- Service Bookings: customer appointment bookings (use get_service_bookings)
- Deliveries: supplier delivery records (use get_deliveries)
- Vehicles: registered fleet vehicles (use get_vehicles)
- Users: staff and customer accounts (use get_user_count)

Rules for in-scope questions:
1. Use only data returned by tool calls. Never invent numbers, names, or records.
2. For any list, count, total, or ranking — ALWAYS call the appropriate tool first.
3. If a tool returns no data, say "I could not find that information in the database."
4. Answer conversationally and naturally, in plain language.
5. Use a table when listing multiple records (items, vehicles, bookings).
6. Assume the user has administrator privileges.
7. Be concise. Lead with the direct answer, then supporting detail.
8. When calling tools, NEVER include parameters you don't have a value for — omit them entirely.
9. Use conversation history to understand follow-up questions.
10. Revenue, earnings, income, sales, and total cost questions are IN-SCOPE — answer them using maintenance job or booking data.
11. If the user writes in Filipino (Tagalog), respond in Filipino or English (whichever is clearer).

CRITICAL — Reformatting follow-ups:
If the user says "make it a list", "number them", "show as bullets", "simplify" or similar,
DO NOT call any tools. Simply reformat your PREVIOUS answer in the requested style.

Keyword mappings (English and Filipino):
- "materials", "parts", "supplies", "stock items", "inventory" → get_stock_levels
- "services", "service list", "what services", "serbisyo" → get_item_catalog with item_type='Service'
- "all items", "catalog", "price list" → get_item_catalog
- "low stock", "reorder", "running low" → get_low_stock_items
- "maintenance", "repair jobs", "service records", "trabaho", "ayos" → get_maintenance_jobs or get_maintenance_summary
- "bookings", "appointments", "booking", "mga appointment" → get_service_bookings
- "deliveries", "supplier deliveries", "delivery" → get_deliveries
- "vehicles", "fleet", "sasakyan", "mga sasakyan" → get_vehicles
- "users", "customers", "staff", "how many users", "mga user" → get_user_count
- "sales", "revenue", "earnings", "income", "total sum", "total cost", "total na kinita",
  "magkano", "kita", "bayad", "total na kita" → get_maintenance_jobs (for cost data) or get_service_bookings
- "summary of sales", "sales this month", "income this month", "kita ngayong buwan",
  "total services", "how much earned" → get_maintenance_summary or get_maintenance_jobs

""" + _build_report_prompt()

def _call_groq(messages: list[dict], tools: list[dict] | None = None):
    """
    Thin wrapper around the Groq API call with token limits enforced.

    - max_tokens is always set to GROQ_MAX_OUTPUT_TOKENS (default 800) so
      the model cannot generate runaway responses that drain the daily quota.
    - Uses the ApiKeyManager to get the current active key.  On RateLimitError
      it rotates to the next key and retries automatically (up to
      manager._max_retries times total).
    """
    manager = get_manager()

    def _do_call(api_key: str):
        client = Groq(api_key=api_key)
        kwargs = {
            "model":      settings.GROQ_MODEL,
            "messages":   messages,
            "max_tokens": settings.GROQ_MAX_OUTPUT_TOKENS,  # ← token cap
        }
        if tools:
            kwargs["tools"] = tools
        return client.chat.completions.create(**kwargs)

    manager._ensure_loaded()
    total_keys   = max(1, len(manager._keys))
    max_attempts = max(manager._max_retries, total_keys)

    last_key_id = manager.get_current_key_id()
    current_key = manager.get_current_key()

    if not current_key:
        current_key = settings.GROQ_API_KEY
        if not current_key:
            raise AllKeysRateLimitedError("No Groq API key configured.")

    last_exc: Exception | None = None
    tried_key_ids: set = set()

    for attempt in range(max_attempts):
        if last_key_id in tried_key_ids:
            next_key = manager.rotate_on_rate_limit(failed_key_id=last_key_id)
            if next_key is None:
                break
            last_key_id = manager.get_current_key_id()
            current_key = next_key

        tried_key_ids.add(last_key_id)

        try:
            return _do_call(current_key)
        except RateLimitError as exc:
            last_exc = exc
            logger.warning(
                "_call_groq: RateLimitError on attempt %d/%d (key_id=%s)",
                attempt + 1, max_attempts, last_key_id,
            )
            if not manager._rotation_enabled:
                raise

            next_key = manager.rotate_on_rate_limit(failed_key_id=last_key_id)
            if next_key is None:
                raise AllKeysRateLimitedError(
                    "All API keys are currently rate-limited. "
                    "Please try again in a few minutes."
                ) from exc
            last_key_id = manager.get_current_key_id()
            current_key = next_key

    if last_exc:
        raise AllKeysRateLimitedError(
            "All API keys are currently rate-limited. "
            "Please try again in a few minutes."
        ) from last_exc
    raise AllKeysRateLimitedError("Groq API key rotation exhausted all retries.")


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


def chat(user_message: str, history: list[dict] | None = None, _retry: bool = False) -> dict:
    # ── Trim history to GROQ_MAX_HISTORY_MSGS before building the payload ──
    # Each exchange = 2 messages (user + assistant). Keeping 10 messages = 5
    # turns saves up to 4,000 input tokens vs the old 30-message cap.
    trimmed_history: list[dict] = []
    if history:
        valid = [m for m in history if isinstance(m, dict) and "role" in m]
        trimmed_history = valid[-settings.GROQ_MAX_HISTORY_MSGS:]

    messages = [{"role": "system", "content": ADMIN_SYSTEM_PROMPT}]
    messages.extend(trimmed_history)
    messages.append({"role": "user", "content": user_message})

    tool_call_log = []
    final_reply = ""

    for _ in range(5):
        try:
            response = _call_groq(messages, tools=TOOL_SCHEMAS)
        except (RateLimitError, AllKeysRateLimitedError):
            raise
        except BadRequestError as e:
            error_str = str(e)
            logger.warning("Groq BadRequestError: %s", error_str)

            if "tool" in error_str.lower() or "function" in error_str.lower():
                try:
                    fallback = _call_groq(messages)
                    final_reply = fallback.choices[0].message.content or \
                        "I could not retrieve that information. Please try rephrasing."
                    return {
                        "reply": final_reply,
                        "tool_calls": tool_call_log,
                        "verified": True,
                        "unsupported_numbers": [],
                    }
                except (RateLimitError, AllKeysRateLimitedError):
                    raise
                except Exception as fallback_err:
                    logger.error("Fallback call also failed: %s", fallback_err)

            return {
                "reply": "I could not retrieve that information. Please try rephrasing your question.",
                "tool_calls": tool_call_log,
                "verified": True,
                "unsupported_numbers": [],
            }

        msg = response.choices[0].message
        assistant_msg: dict = {"role": "assistant", "content": msg.content or ""}
        if msg.tool_calls:
            assistant_msg["tool_calls"] = [tc.model_dump() for tc in msg.tool_calls]
        messages.append(assistant_msg)

        if not msg.tool_calls:
            final_reply = msg.content or ""
            break

        for call in msg.tool_calls:
            fn_name = call.function.name
            fn_args = _strip_null_args(call.function.arguments or "")

            fn = TOOL_FUNCTIONS.get(fn_name)
            if fn is None:
                result = {"error": f"Unknown tool '{fn_name}'"}
            else:
                try:
                    result = fn(**fn_args)
                except Exception as e:
                    result = {"error": str(e)}

            tool_call_log.append({"tool": fn_name, "args": fn_args, "result": result})

            # ── Cap tool result size before feeding back to the LLM ──────────
            # Large payloads (e.g. full stock catalog) can push input tokens to
            # 5,000–10,000 per call. We serialize, truncate if needed, and append
            # a note so the model knows the data was trimmed.
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

    if tool_call_log:
        check = verify_reply(final_reply, tool_call_log)
        if not check["verified"] and not _retry:
            correction_prompt = (
                f"Your previous answer contained number(s) that do not match the data "
                f"retrieved: {check['unsupported_numbers']}. "
                f"The only valid numbers from the actual tool results are: {check['source_numbers']}. "
                f"Re-answer the original question using ONLY these numbers. "
                f"If you cannot answer accurately with this data, say so explicitly."
            )
            messages.append({"role": "user", "content": correction_prompt})
            response = _call_groq(messages)
            final_reply = response.choices[0].message.content or final_reply
            check = verify_reply(final_reply, tool_call_log)

        return {
            "reply":                final_reply,
            "tool_calls":           tool_call_log,
            "verified":             check["verified"],
            "unsupported_numbers":  check["unsupported_numbers"],
        }

    return {"reply": final_reply, "tool_calls": tool_call_log, "verified": True, "unsupported_numbers": []}
