# Complete Price List Feature - Guide

## Overview

Customers can now request complete price lists for all services and materials. The AI assistant will show the ENTIRE catalog with prices, organized by category.

---

## How It Works

### For Services

**Customer asks:**
- "Show me all service prices"
- "List all services with prices"
- "Complete service catalog"
- "What are all your service prices?"
- "Give me the full price list"

**AI responds with:**
```
Here's our complete service catalog with prices:

**Lubricant Services:**
• Change Oil - ₱500.00
• ATF Service - ₱1,200.00
• Gear Oil Change - ₱800.00

**Tire Services:**
• Tire Rotation - ₱300.00
• Wheel Alignment - ₱800.00
• Tire Balancing - ₱400.00

**Brake Services:**
• Brake Pad Replacement - ₱1,500.00
• Brake Fluid Flush - ₱600.00

[... continues with all services ...]

We have [N] services available. Would you like to book any of these?
```

### For Materials

**Customer asks:**
- "Show me all product prices"
- "List all materials you sell"
- "Complete product catalog"
- "What products do you have?"
- "Show all material prices"

**AI responds with:**
```
Here are all our available products with prices:

**Lubricants:**
• Shell Helix 10W-40 (1L) - ₱350.00
• Castrol GTX 15W-40 (1L) - ₱320.00
• Mobil 1 5W-30 (1L) - ₱450.00

**Filters:**
• Oil Filter Toyota - ₱250.00
• Air Filter Honda - ₱180.00

**Brake Parts:**
• Brake Pads Front - ₱1,200.00
• Brake Fluid DOT 4 (500ml) - ₱280.00

[... continues with all products ...]

We have [N] products available. Need any of these?
```

---

## Implementation Details

### Tool Behavior

#### `get_service_prices()`

**When called without filter:**
```python
get_service_prices(
    customer_uid="uid",
    customer_name="Customer",
    service_name=None  # ← No filter = complete catalog
)
```

**Returns:**
```json
{
  "filter": "all services",
  "total_services": 25,
  "services": [
    {
      "num": "SVC001",
      "name": "Change Oil",
      "group": "Lubricant Services",
      "uom": "Service",
      "cost": "₱500.00"
    },
    // ... all 25 services
  ],
  "catalog_size": 25
}
```

#### `get_customer_materials()`

**When called without filter:**
```python
get_customer_materials(
    customer_uid="uid",
    customer_name="Customer",
    material_name=None  # ← No filter = complete catalog
)
```

**Returns:**
```json
{
  "filter": "all materials",
  "total_materials": 15,
  "materials": [
    {
      "name": "Shell Helix 10W-40",
      "group": "Lubricants",
      "uom": "Liter",
      "customer_price": "₱350.00",
      "available": true
    },
    // ... all 15 materials
  ]
}
```

---

## System Prompt Instructions

The AI is instructed to:

1. **Call tools without filters** when customer asks for "all" or "complete list"
2. **Show the COMPLETE catalog** - never summarize or truncate
3. **Organize by groups** for readability
4. **Never say "too long"** - always show everything
5. **Format clearly** with bullet points and prices

### Example System Prompt Section:

```
PRICING & CATALOG DISPLAY RULES:
When customer asks for "all prices", "complete list", "show all services":
1. Call get_service_prices() WITHOUT filter (service_name=None)
2. Present the COMPLETE list organized by category/group
3. Format as well-structured list with prices clearly visible
4. If list is long (>30 items), organize by groups but show ALL items
5. NEVER say "the list is too long" - always show complete catalog

Example format:
"Here's our complete service catalog with prices:

**Lubricant Services:**
• Change Oil - ₱500.00
• ATF Service - ₱1,200.00

**Tire Services:**
• Tire Rotation - ₱300.00
• Wheel Alignment - ₱800.00

[Continue with all services...]"
```

---

## Privacy & Security

### What Customers CAN See:
✅ Service names and prices  
✅ Material names and customer prices  
✅ Service/material groups (categories)  
✅ Units of measurement (UOM)  
✅ Availability status (if set)

### What Customers CANNOT See:
❌ Stock quantities  
❌ Minimum/maximum stock levels  
❌ Reorder points  
❌ Supplier information  
❌ Purchase costs  
❌ Inventory transactions  
❌ Admin-only data

---

## Testing

### Run the test suite:
```powershell
cd ai_assistant
python test_complete_price_list.py
```

### Test Cases:
1. ✅ Get complete service catalog (no filter)
2. ✅ Get filtered services (e.g., "oil change")
3. ✅ Get complete materials catalog (no filter)
4. ✅ Get filtered materials (e.g., "lubricants")
5. ✅ Verify no internal data exposed
6. ✅ Verify catalog organization by groups

---

## Example Conversations

### Scenario 1: All Service Prices

```
Customer: "Show me all your service prices"

AI: (calls get_service_prices with no filter)
    "Here's our complete service catalog with prices:
    
    **Lubricant Services:**
    • Change Oil - ₱500.00
    • ATF Service - ₱1,200.00
    • Gear Oil Change - ₱800.00
    
    **Tire Services:**
    • Tire Rotation - ₱300.00
    • Wheel Alignment - ₱800.00
    • Wheel Balancing - ₱400.00
    
    **Brake Services:**
    • Brake Pad Replacement - ₱1,500.00
    • Brake Fluid Flush - ₱600.00
    • Brake Inspection - ₱200.00
    
    **Engine Services:**
    • Tune Up - ₱1,800.00
    • Engine Diagnostic - ₱500.00
    
    **Other Services:**
    • Battery Replacement - ₱2,500.00
    • Wiper Blade Replacement - ₱250.00
    • Light Bulb Replacement - ₱150.00
    
    We have 15 services available in total. Would you like to book 
    any of these for your vehicle?"
```

### Scenario 2: Specific Category

```
Customer: "What are your tire service prices?"

AI: (calls get_service_prices with service_name="tire")
    "Here are our tire services with prices:
    
    • Tire Rotation - ₱300.00
    • Wheel Alignment - ₱800.00
    • Wheel Balancing - ₱400.00
    • Tire Pressure Check - Free
    
    These services help maintain even tire wear and proper vehicle 
    handling. Would you like to book any of these?"
```

### Scenario 3: All Products

```
Customer: "What products do you sell?"

AI: (calls get_customer_materials with no filter)
    "Here are all our available products with prices:
    
    **Engine Oils:**
    • Shell Helix 10W-40 (1L) - ₱350.00
    • Castrol GTX 15W-40 (1L) - ₱320.00
    • Mobil 1 5W-30 (1L) - ₱450.00
    
    **Filters:**
    • Oil Filter Toyota - ₱250.00
    • Oil Filter Honda - ₱220.00
    • Air Filter Universal - ₱180.00
    
    **Brake Parts:**
    • Brake Pads (Front Set) - ₱1,200.00
    • Brake Fluid DOT 4 (500ml) - ₱280.00
    
    **Cooling System:**
    • Coolant Long Life (1L) - ₱200.00
    • Radiator Cap - ₱150.00
    
    We carry 12 products in total. These are available for purchase 
    during service or separately. Need any of these?"
```

### Scenario 4: Complete List with Booking

```
Customer: "Show me all services and I want to book one"

AI: (calls get_service_prices with no filter)
    "Here's our complete service catalog:
    
    [... shows complete list ...]
    
    We have 15 services available. Which service would you like to 
    book for your vehicle?"

Customer: "I'll take the oil change"

AI: (proceeds with booking workflow)
    "Great choice! Let me help you book an oil change. Which vehicle 
    is this for?"
```

---

## Key Features

### 1. Complete Visibility
- Customers see EVERYTHING available
- No hidden services or products
- Transparent pricing

### 2. Organized Presentation
- Grouped by category for easy browsing
- Clear formatting with bullets
- Prices prominently displayed

### 3. Context-Aware
- Can filter by keyword if customer specifies
- Shows complete list when customer asks for "all"
- Integrates with booking workflow

### 4. Privacy Protected
- No internal data exposed
- Only customer-facing prices shown
- Stock/supplier info hidden

---

## Benefits

### For Customers:
- ✅ See all options at once
- ✅ Compare prices easily
- ✅ Make informed decisions
- ✅ No need to ask repeatedly

### For Business:
- ✅ Transparent pricing builds trust
- ✅ Customers know what's available
- ✅ Reduces "do you have X?" questions
- ✅ Facilitates upselling opportunities

---

## Troubleshooting

### Issue: List appears empty

**Check:**
1. Are there items in `item_master` collection?
2. Do items have `type='Service'` or `type='Material'`?
3. Do items have a `cost` field with a price?

**Solution:**
Run the diagnostic endpoint:
```
GET http://localhost:8000/debug/item-master
```

### Issue: Not all items showing

**Check:**
1. Item type field (case-sensitive: "Service" vs "service")
2. Query in customer_tools.py uses both cases
3. Cache may need invalidation

**Solution:**
```
POST http://localhost:8000/cache/invalidate?key=service_catalog
```

### Issue: AI not showing complete list

**Check:**
1. System prompt includes PRICING & CATALOG DISPLAY RULES
2. Tool called without filter (service_name=None)
3. AI not truncating response

**Solution:**
Verify system prompt in main.py includes complete list instructions

---

## Technical Notes

### Database Query
```python
# Services from item_master
catalog = cache_manager.get_service_catalog(db)
# Returns all items where type='Service'

# Materials from item_master
docs = db.collection("item_master")
         .where(filter=FF("type", "==", "Material"))
         .stream()
```

### Caching
- Service catalog cached for 5 minutes (300 seconds)
- Reduces Firestore reads by ~90%
- Invalidate when prices change

### Response Format
```python
{
  "filter": "all services" | "keyword",
  "total_services": int,
  "services": [
    {
      "name": str,
      "cost": "₱X.XX",
      "group": str,
      "uom": str
    }
  ],
  "catalog_size": int
}
```

---

## Future Enhancements

Potential improvements:
- [ ] Sort by price (low to high, high to low)
- [ ] Filter by price range ("services under ₱1000")
- [ ] Service package bundles with discounts
- [ ] Seasonal pricing or promotions
- [ ] Most popular services highlighted
- [ ] Service duration estimates
- [ ] PDF export of price list
- [ ] Comparison between similar services

---

**Status:** ✅ COMPLETE AND READY

The AI assistant now provides complete, organized price lists when customers request them, improving transparency and helping customers make informed decisions.
