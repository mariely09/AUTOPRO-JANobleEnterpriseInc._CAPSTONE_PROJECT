"""
Formatting utilities for converting markdown to HTML in customer-facing responses.
"""
import re


def markdown_to_html(text: str) -> str:
    """
    Convert markdown bold formatting (**text**) to HTML bold tags (<b>text</b>).
    
    This function handles:
    - Simple bold: **text** → <b>text</b>
    - Bold with punctuation: **text:** → <b>text:</b>
    - Multiple bold sections in the same line
    - Preserves line breaks and other HTML tags
    
    Args:
        text: String that may contain markdown bold formatting
        
    Returns:
        String with markdown bold converted to HTML <b> tags
    
    Examples:
        >>> markdown_to_html("**Hello** world")
        '<b>Hello</b> world'
        
        >>> markdown_to_html("**Vehicle:** ABC 123")
        '<b>Vehicle:</b> ABC 123'
    """
    if not text:
        return text
    
    # Replace **text** with <b>text</b>
    # This regex matches ** followed by one or more non-** characters, followed by **
    # The non-greedy match (.*?) ensures we match the shortest span between **
    result = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', text)
    
    return result


def html_to_markdown(text: str) -> str:
    """
    Convert HTML bold tags (<b>text</b>) back to markdown (**text**).
    
    Useful for storing data in a markdown-friendly format or for testing.
    
    Args:
        text: String that may contain HTML bold tags
        
    Returns:
        String with HTML <b> tags converted to markdown bold
    
    Examples:
        >>> html_to_markdown("<b>Hello</b> world")
        '**Hello** world'
    """
    if not text:
        return text
    
    # Replace <b>text</b> with **text**
    result = re.sub(r'<b>(.+?)</b>', r'**\1**', text, flags=re.IGNORECASE)
    
    return result
