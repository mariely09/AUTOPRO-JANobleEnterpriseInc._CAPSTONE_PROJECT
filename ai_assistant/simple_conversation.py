"""
Simple conversation handler for instant responses without AI model inference.

Handles greetings, thanks, basic capability questions, and simple conversational
messages with deterministic template responses (0 tokens, <1ms response time).

All patterns are case-insensitive and match whole words or common variations.
"""
import re
from typing import Optional

# ══════════════════════════════════════════════════════════════════════════════
# ADMIN GREETING PATTERNS
# ══════════════════════════════════════════════════════════════════════════════

_ADMIN_GREETINGS = {
    # Simple greetings
    r"^(hi|hello|hey|greetings?)$": "Hello! I'm your Admin AI Assistant. How can I help you with inventory, maintenance, bookings, or reports today?",
    
    # Morning greetings
    r"^(good\s+morning|morning)$": "Good morning! How can I assist you with the system today?",
    
    # Afternoon greetings
    r"^(good\s+afternoon|afternoon)$": "Good afternoon! How can I help you manage your operations today?",
    
    # Evening greetings
    r"^(good\s+evening|evening)$": "Good evening! What can I help you with?",
    
    # Night greetings
    r"^(good\s+night|night)$": "Good night! Feel free to ask me anything about the system before you go.",
    
    # How are you
    r"^(how\s+are\s+you|how\s+r\s+u|how\s+are\s+u|hows\s+it\s+going|how's\s+it\s+going)[\?!.]*$": 
        "I'm functioning perfectly, thank you! Ready to assist you with inventory, maintenance tracking, booking management, or report generation. What would you like to check?",
    
    # Thank you
    r"^(thanks?|thank\s+you|ty|thx|tysm|thank\s+u)[\?!.]*$": 
        "You're welcome! Let me know if you need anything else.",
    
    # OK/Okay acknowledgments
    r"^(ok|okay|k|kk|got\s+it|i\s+see|i\s+understand|alright|sure)[\?!.]*$":
        "Great! Feel free to ask me anything else about the system.",
}

_ADMIN_CAPABILITY_QUESTIONS = {
    # What can you do
    r"^(what\s+can\s+you\s+(do|help(\s+me)?(\s+with)?)|what\s+do\s+you\s+do|what\s+are\s+you\s+for)[\?!.]*$":
        "I can help you with:\n\n"
        "📦 **Inventory Management** - Stock levels, low-stock alerts, item catalog\n"
        "🔧 **Maintenance Tracking** - Service history, PMS schedules, overdue vehicles\n"
        "📅 **Booking Management** - Service appointments, booking status\n"
        "👥 **User Management** - Customer accounts, staff records\n"
        "📊 **Reports** - Generate PDF/Excel reports for inventory, maintenance, issuances\n"
        "🧮 **Calculations** - Reorder points, stock arithmetic, cost analysis\n\n"
        "Just ask me in natural language!",
    
    # Who are you
    r"^(who\s+are\s+you|what\s+are\s+you|what\s+is\s+this)[\?!.]*$":
        "I'm the Admin AI Assistant for the AutoPro Integrated Vehicle Maintenance and Inventory Management System. "
        "I can answer questions about your inventory, maintenance records, bookings, users, and generate reports.",
    
    # What is this system
    r"^(what\s+is\s+this\s+system|what\s+is\s+this\s+for|what\s+does\s+this\s+system\s+do)[\?!.]*$":
        "This is the **AutoPro Integrated Vehicle Maintenance and Inventory Management System**. "
        "It helps you manage automotive service operations including:\n\n"
        "• Vehicle fleet tracking and preventive maintenance schedules\n"
        "• Inventory and stock management\n"
        "• Service booking and appointment management\n"
        "• Maintenance job tracking\n"
        "• Customer and staff account management\n"
        "• Comprehensive reporting and analytics",
    
    # Help
    r"^(help|help\s+me|i\s+need\s+help)[\?!.]*$":
        "I'm here to help! You can ask me about:\n\n"
        "• **Inventory** - \"What items are low in stock?\", \"Show me the engine oil stock level\"\n"
        "• **Maintenance** - \"Which vehicles are overdue for service?\", \"Show maintenance summary\"\n"
        "• **Bookings** - \"Show pending service bookings\", \"How many bookings this month?\"\n"
        "• **Reports** - \"Generate an inventory report for July 2026\"\n"
        "• **Calculations** - \"Calculate reorder point with ADU 5, LT 7 days, SS 10\"\n\n"
        "Just type your question in plain English!",
}

# ══════════════════════════════════════════════════════════════════════════════
# CUSTOMER GREETING PATTERNS
# ══════════════════════════════════════════════════════════════════════════════

_CUSTOMER_GREETINGS = {
    # Simple greetings
    r"^(hi|hello|hey|greetings?|kumusta|kamusta)$": 
        "Hello! I'm your AI Assistant. How can I help you with your vehicles, maintenance schedules, or service bookings today?",
    
    # Morning greetings
    r"^(good\s+morning|morning|magandang\s+umaga)$": 
        "Good morning! How can I assist you today?",
    
    # Afternoon greetings
    r"^(good\s+afternoon|afternoon|magandang\s+hapon)$": 
        "Good afternoon! How can I help you?",
    
    # Evening greetings
    r"^(good\s+evening|evening|magandang\s+gabi)$": 
        "Good evening! What can I do for you?",
    
    # Night greetings
    r"^(good\s+night|night)$": 
        "Good night! Let me know if you need anything before you go.",
    
    # How are you
    r"^(how\s+are\s+you|how\s+r\s+u|how\s+are\s+u|kumusta\s+ka|kamusta\s+ka)[\?!.]*$":
        "I'm doing great, thank you! Ready to help you with your vehicles, maintenance schedules, or booking appointments. What would you like to check?",
    
    # Thank you
    r"^(thanks?|thank\s+you|ty|thx|tysm|thank\s+u|salamat)[\?!.]*$":
        "You're welcome! Happy to help anytime.",
    
    # OK/Okay acknowledgments
    r"^(ok|okay|k|kk|got\s+it|i\s+see|i\s+understand|alright|sure|sige)[\?!.]*$":
        "Great! Let me know if you have any other questions.",
}

_CUSTOMER_CAPABILITY_QUESTIONS = {
    # What can you do
    r"^(what\s+can\s+you\s+(do|help(\s+me)?(\s+with)?)|what\s+do\s+you\s+do|ano\s+ang\s+kaya\s+mo)[\?!.]*$":
        "I can help you with:\n\n"
        "🚗 **My Vehicles** - View your registered vehicles and their status\n"
        "🔧 **Maintenance** - Check PMS schedules, service history, overdue alerts\n"
        "📅 **Bookings** - Schedule service appointments, check booking status\n"
        "💰 **Service Costs** - Estimate service costs, view service prices\n"
        "📋 **Service Info** - Learn about available services and materials\n\n"
        "Just ask me your question!",
    
    # Who are you
    r"^(who\s+are\s+you|what\s+are\s+you|sino\s+ka)[\?!.]*$":
        "I'm your AI Assistant for AutoPro! I can help you check your vehicle maintenance schedules, "
        "book service appointments, view your service history, and answer questions about our services.",
    
    # Help
    r"^(help|help\s+me|i\s+need\s+help|tulong)[\?!.]*$":
        "I'm here to help! You can ask me:\n\n"
        "• \"Show my vehicles\" or \"Ipakita ang aking sasakyan\"\n"
        "• \"Is my car overdue for service?\"\n"
        "• \"When is my next PMS due?\"\n"
        "• \"I want to book a service\" or \"Gusto kong mag-book\"\n"
        "• \"How much is an oil change?\"\n"
        "• \"Show my booking history\"\n\n"
        "Type your question in English or Tagalog!",
}

# ══════════════════════════════════════════════════════════════════════════════
# COMPILED PATTERNS (for performance)
# ══════════════════════════════════════════════════════════════════════════════

_ADMIN_GREETING_PATTERNS = [(re.compile(p, re.IGNORECASE), r) for p, r in _ADMIN_GREETINGS.items()]
_ADMIN_CAPABILITY_PATTERNS = [(re.compile(p, re.IGNORECASE), r) for p, r in _ADMIN_CAPABILITY_QUESTIONS.items()]

_CUSTOMER_GREETING_PATTERNS = [(re.compile(p, re.IGNORECASE), r) for p, r in _CUSTOMER_GREETINGS.items()]
_CUSTOMER_CAPABILITY_PATTERNS = [(re.compile(p, re.IGNORECASE), r) for p, r in _CUSTOMER_CAPABILITY_QUESTIONS.items()]


# ══════════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ══════════════════════════════════════════════════════════════════════════════

def get_simple_response(message: str, role: str = "admin") -> Optional[str]:
    """
    Check if the message is a simple greeting or capability question.
    Returns an instant template response, or None if the message requires
    AI model inference or database lookup.
    
    Args:
        message: User's message (will be normalized)
        role: "admin" or "customer"
    
    Returns:
        Template response string, or None to fall through to normal flow
    
    Performance: <1ms for pattern matching, 0 tokens, 0 DB reads
    """
    if not message or not message.strip():
        return None
    
    # Normalize: strip whitespace, collapse multiple spaces
    normalized = " ".join(message.strip().lower().split())
    
    # Select appropriate pattern sets based on role
    if role == "customer":
        greeting_patterns = _CUSTOMER_GREETING_PATTERNS
        capability_patterns = _CUSTOMER_CAPABILITY_PATTERNS
    else:  # admin
        greeting_patterns = _ADMIN_GREETING_PATTERNS
        capability_patterns = _ADMIN_CAPABILITY_PATTERNS
    
    # Check greetings first (most common)
    for pattern, response in greeting_patterns:
        if pattern.match(normalized):
            return response
    
    # Check capability questions
    for pattern, response in capability_patterns:
        if pattern.match(normalized):
            return response
    
    return None  # fall through to normal AI flow


def is_simple_conversation(message: str) -> bool:
    """
    Quick check if a message is a simple greeting/conversation without
    generating the response. Useful for metrics/logging.
    
    Returns:
        True if get_simple_response would return a response, False otherwise
    """
    if not message or not message.strip():
        return False
    
    normalized = " ".join(message.strip().lower().split())
    
    # Check both admin and customer patterns
    all_patterns = (
        _ADMIN_GREETING_PATTERNS + 
        _ADMIN_CAPABILITY_PATTERNS +
        _CUSTOMER_GREETING_PATTERNS + 
        _CUSTOMER_CAPABILITY_PATTERNS
    )
    
    for pattern, _ in all_patterns:
        if pattern.match(normalized):
            return True
    
    return False


# ══════════════════════════════════════════════════════════════════════════════
# TESTS (run with: python -m doctest simple_conversation.py)
# ══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    # Admin tests
    assert get_simple_response("hello", "admin") is not None
    assert get_simple_response("HELLO", "admin") is not None
    assert get_simple_response("  hello  ", "admin") is not None
    assert get_simple_response("good morning", "admin") is not None
    assert get_simple_response("how are you?", "admin") is not None
    assert get_simple_response("thanks", "admin") is not None
    assert get_simple_response("what can you do?", "admin") is not None
    assert get_simple_response("who are you", "admin") is not None
    assert get_simple_response("help", "admin") is not None
    
    # Customer tests
    assert get_simple_response("hello", "customer") is not None
    assert get_simple_response("kumusta", "customer") is not None
    assert get_simple_response("salamat", "customer") is not None
    assert get_simple_response("magandang umaga", "customer") is not None
    
    # Should NOT match (requires AI/DB)
    assert get_simple_response("show my vehicles", "customer") is None
    assert get_simple_response("what items are low in stock", "admin") is None
    assert get_simple_response("how many bookings", "admin") is None
    
    # is_simple_conversation tests
    assert is_simple_conversation("hello") is True
    assert is_simple_conversation("thanks") is True
    assert is_simple_conversation("show inventory") is False
    
    print("✓ All simple_conversation tests passed!")
