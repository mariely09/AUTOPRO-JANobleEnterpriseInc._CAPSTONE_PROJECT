"""
LLM client using Groq (fast cloud inference, OpenAI-compatible API).
"""
import json
import logging
from groq import Groq, BadRequestError, RateLimitError
from config import settings
from firestore_tools import TOOL_SCHEMAS, TOOL_FUNCTIONS
from verifier import verify_reply

logger = logging.getLogger(__name__)

ADMIN_SYSTEM_PROMPT = """You are the internal AI assistant for the Automotive Service and Inventory Management System (Caltex AutoPro — JA Noble Enterprise Inc., Caltex San Pedro, Laguna).

STRICT SCOPE RESTRICTION — HIGHEST PRIORITY:
You ONLY answer questions that are directly related to this system's data:
inventory, stock levels, maintenance jobs, service bookings, vehicles/fleet,
issuances, deliveries, users/staff, and reports.

If a user asks ANYTHING outside this scope — including but not limited to:
general knowledge, sports, current events, news, history, science, coding,
math, recipes, weather, entertainment, or any other non-system topic —
you MUST respond with ONLY this exact text, nothing else:
"I can only answer questions related to the Automotive Service and Inventory Management System."

Do NOT elaborate, apologize, or add any additional information.
Do NOT attempt to answer even partially.
Do NOT say "I don't know" or offer alternatives.
Just return that one sentence and nothing more.

The data you have access to:
- Stock/Inventory: physical parts and supplies with current stock levels (use get_stock_levels, get_low_stock_items)
- Item Catalog: master list of all Materials and Services offered (use get_item_catalog)
- Maintenance Jobs: service/repair records per vehicle (use get_maintenance_jobs, get_maintenance_summary)
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

CRITICAL — Reformatting follow-ups:
If the user says "make it a list", "number them", "show as bullets", "simplify" or similar,
DO NOT call any tools. Simply reformat your PREVIOUS answer in the requested style.

Keyword mappings:
- "materials", "parts", "supplies", "stock items", "inventory" → get_stock_levels
- "services", "service list", "what services" → get_item_catalog with item_type='Service'
- "all items", "catalog", "price list" → get_item_catalog
- "low stock", "reorder", "running low" → get_low_stock_items
- "maintenance", "repair jobs", "service records" → get_maintenance_jobs or get_maintenance_summary
- "bookings", "appointments" → get_service_bookings
- "deliveries", "supplier deliveries" → get_deliveries
- "vehicles", "fleet" → get_vehicles
- "users", "customers", "staff", "how many users" → get_user_count
"""

_client = Groq(api_key=settings.GROQ_API_KEY)


def _call_groq(messages: list[dict], tools: list[dict] | None = None):
    """Thin wrapper around the Groq API call."""
    kwargs = {"model": settings.GROQ_MODEL, "messages": messages}
    if tools:
        kwargs["tools"] = tools
    return _client.chat.completions.create(**kwargs)


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
    messages = [{"role": "system", "content": ADMIN_SYSTEM_PROMPT}]
    if history:
        # Sanitize: drop any history entries missing a role (Groq will 400 on them)
        valid_history = [m for m in history if isinstance(m, dict) and "role" in m]
        messages.extend(valid_history)
    messages.append({"role": "user", "content": user_message})

    tool_call_log = []
    final_reply = ""

    for _ in range(5):
        try:
            response = _call_groq(messages, tools=TOOL_SCHEMAS)
        except RateLimitError:
            # Re-raise so main.py can return the structured rate-limit response
            raise
        except BadRequestError as e:
            error_str = str(e)
            logger.warning("Groq BadRequestError: %s", error_str)

            # If Groq rejected because of a null/invalid arg in a tool call,
            # retry without tools so the LLM can still answer in plain text.
            if "tool" in error_str.lower() or "function" in error_str.lower():
                try:
                    fallback = _call_groq(messages)  # no tools — plain text answer
                    final_reply = fallback.choices[0].message.content or \
                        "I could not retrieve that information. Please try rephrasing."
                    return {
                        "reply": final_reply,
                        "tool_calls": tool_call_log,
                        "verified": True,
                        "unsupported_numbers": [],
                    }
                except RateLimitError:
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

            messages.append({
                "role": "tool",
                "tool_call_id": call.id,
                "content": json.dumps(result),
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
            "reply": final_reply,
            "tool_calls": tool_call_log,
            "verified": check["verified"],
            "unsupported_numbers": check["unsupported_numbers"],
        }

    return {"reply": final_reply, "tool_calls": tool_call_log, "verified": True, "unsupported_numbers": []}
