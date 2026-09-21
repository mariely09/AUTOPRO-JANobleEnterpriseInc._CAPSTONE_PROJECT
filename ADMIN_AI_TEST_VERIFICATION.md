# Admin AI Assistant - Test Case Verification Guide

## Overview
This document provides step-by-step verification procedures for all Admin AI Assistant test cases, ensuring accurate real-time data retrieval from Firestore.

---

## Test Case 1: Report Generation (PDF)

### Steps:
1. Navigate to the AI Assistant chat bubble on the dashboard
2. Enter query: `"Generate the issuance report for the month of July 2026 in PDF."`
3. Click the send button

### Expected Result:
- AI retrieves data from Firestore `issuances` collection filtered by July 2026
- Confirms report is ready
- Displays **Download PDF** button
- Click button → PDF downloads successfully with July 2026 issuance data

### Backend Verification:
```
[FIRESTORE_QUERY] - Collection: issuances, Filter: month=July 2026
[REPORT_GENERATION] - Type: issuance, Format: PDF, Records: X
```

---

## Test Case 2: Report Generation (Excel)

### Steps:
1. Enter query: `"Generate inventory report as Excel"`
2. Click send button

### Expected Result:
- AI retrieves current inventory from Firestore `stock_inventory` collection
- Displays **Download Excel** button
- Click button → Excel file downloads with current inventory data

### Backend Verification:
```
[FIRESTORE_QUERY] - Collection: stock_inventory
[REPORT_GENERATION] - Type: inventory, Format: Excel, Records: X
```

---

## Test Case 3: Empty Message Input

### Steps:
1. Leave message input field empty
2. Try to submit

### Expected Result:
- Submit button remains **disabled**
- No request sent to backend
- No error displayed

---

## Test Case 4: Invalid Input Handling

### Steps:
1. Enter: `@#$%^&*`
2. Click send button

### Expected Result:
- AI handles gracefully without crashing
- Response: "I didn't quite understand that. Could you please rephrase your question?"
- OR: "Please enter a valid question about the automotive management system."

### Backend Verification:
```
[INPUT_GUARD] - Invalid characters detected, sanitized
[INTENT_CLASSIFIER] - Result: unknown/invalid
```

---

## Test Case 5: Out-of-Domain Query

### Steps:
1. Enter: `"Who won the FIFA World Cup in 2018?"`
2. Click send button

### Expected Result:
- Response: "I can only answer questions related to the Automotive Service and Inventory Management System. Please ask about inventory, vehicles, maintenance, bookings, or reports."

### Backend Verification:
```
[INTENT_CLASSIFIER] - Result: out_of_domain
[DOMAIN_GUARD] - Blocked non-automotive query
```

---

## Test Case 6: Report with No Matching Records

### Steps:
1. Enter: `"Generate the issuance report for December 2035"`
2. Click send button

### Expected Result:
- Response: "I couldn't find any issuance records for December 2035. Please check the date and try again."
- OR: "No issuances found for the specified period."
- **No download button displayed**

### Backend Verification:
```
[FIRESTORE_QUERY] - Collection: issuances, Filter: month=December 2035, Records: 0
[REPORT_GENERATION] - Skipped (no records)
```

---

## Test Case 7: Clear Chat

### Steps:
1. Click the **Clear Chat** button

### Expected Result:
- Conversation history is cleared from UI
- New conversation session starts
- Previous messages no longer visible
- Chat shows initial welcome message

---

## Test Case 8: Low Stock Query (DATA ACCURACY CRITICAL)

### Steps:
1. Enter: `"Show all low-stock inventory items."`
2. Click send button

### Expected Result:
- AI retrieves current stock levels from Firestore `stock_inventory` collection
- Scans ALL items (no limit)
- Counts items where:
  - `status == "Low"` OR
  - `stock <= min` (when min > 0) OR
  - `stock <= reorder` (when reorder > 0)
- Response shows: **"There are X items at or below the reorder point (out of Y total inventory items):"**
- X = accurate count of low stock items
- Y = total items in inventory
- Lists all low stock items with current stock levels

### Data Accuracy Verification:
```
[FIRESTORE_QUERY] get_low_stock_items - START
[FIRESTORE_QUERY] get_low_stock_items - COMPLETE | 
  total_inventory_items: 126 | 
  low_stock_found: 8 | 
  elapsed: 0.234s | 
  data_source: firestore_realtime
```

**CRITICAL:** The count reported in the response MUST match the actual count of items meeting the criteria. If the database has 126 total items, the AI cannot report "130 low stock items".

### How to Verify Accuracy:
1. Check backend logs for `total_inventory_items` and `low_stock_found`
2. Compare count in AI response to backend log count
3. Manually verify in Firestore console if needed:
   - Go to `stock_inventory` collection
   - Count items where `status == "Low"` OR `stock <= min` OR `stock <= reorder`
4. Numbers must match exactly

---

## Test Case 9: Customer Count Query

### Steps:
1. Enter: `"How many registered customers are in the system?"`
2. Click send button

### Expected Result:
- AI queries Firestore `users` collection with role filter
- Response: "There are **X** registered users in the system — **Y** customers, **Z** staff, etc."
- Numbers reflect current Firestore data

### Backend Verification:
```
[FIRESTORE_QUERY] - Collection: users, Query: count by role
[DB_CALCULATION] - Total: X, Breakdown: {customer: Y, staff: Z}
```

---

## Test Case 10: Pending Bookings Query

### Steps:
1. Enter: `"Show all pending service bookings."`
2. Click send button

### Expected Result:
- AI queries Firestore `service_bookings` collection with status filter
- Response lists all bookings with `status == "pending"`
- Shows booking details: customer, vehicle, service, date
- If no pending bookings: "There are currently no pending service bookings."

### Backend Verification:
```
[FIRESTORE_QUERY] - Collection: service_bookings, Filter: status=pending, Records: X
[FAST_PATH_DB] intent=service_bookings | firestore_ms=XXX | llm_calls: 0
```

---

## Test Case 11: Chat History - View

### Steps:
1. Click the **"Chat History"** button

### Expected Result:
- Chat History side panel opens
- Displays **"Delete All Chats"** button at top
- Lists previous conversations showing:
  - Timestamp (e.g., "2 hours ago", "Yesterday")
  - First query from each conversation
- Conversations ordered by most recent first

---

## Test Case 12: Chat History - Verify Display

### Steps:
1. Review displayed chat history

### Expected Result:
- Each conversation entry shows:
  - Readable timestamp
  - First user message from that session
  - Click-to-open functionality (if implemented)
- UI is clean and scrollable

---

## Test Case 13: Chat History - Delete (Cancel)

### Steps:
1. Click **"Delete All Chats"** button
2. Confirmation dialog appears
3. Click **"Cancel"**

### Expected Result:
- Confirmation dialog closes
- All chat history remains unchanged
- Can still see previous conversations

---

## Test Case 14: Chat History - Delete (Confirm)

### Steps:
1. Click **"Delete All Chats"** button again
2. Confirmation dialog appears
3. Click **"Confirm"** or **"Yes"**

### Expected Result:
- All saved chat history is **permanently deleted**
- Chat History panel shows: "No previous conversations"
- Or shows empty state message

### Backend/Storage Verification:
- Firestore: `admin_chat_sessions` or `chat_history` collection cleared
- Local storage: Chat history keys removed

---

## Test Case 15: Chat History - Verify Deletion

### Steps:
1. Close the Chat History side panel
2. Open it again immediately

### Expected Result:
- Chat History panel opens successfully
- Remains **empty** (no conversations shown)
- Confirms deletion was successful and persistent

---

## Data Integrity Requirements

### All Queries Must:
1. ✅ Query Firestore at request time (no caching)
2. ✅ Return current data as of query execution
3. ✅ Include accurate counts matching database state
4. ✅ Log `data_source: firestore_realtime` for verification
5. ✅ Complete database queries in <1 second (after performance fix)

### Counts Must Be Accurate:
- **Low stock count** ≤ **Total inventory count**
- **Pending bookings** = actual count of `status == "pending"` in Firestore
- **Customer count** = actual count in `users` collection
- **Report records** = actual records matching filter criteria

### Response Time Targets:
- Database queries: <1 second
- Report generation: 2-5 seconds (depending on record count)
- Health check: <10 seconds
- Initial connection: <36 seconds (worst case with retries)

---

## Common Issues & Solutions

### Issue: Count Mismatch (e.g., "130 items" when only 126 total)

**Cause:** Query logic error or incorrect counting

**Fix Applied:**
- Removed `.limit(200)` - now scans ALL items for accurate count
- Added `total_inventory_items` field to response for verification
- Enhanced logging to show both counts

**Verification:**
```python
# Backend logs should show:
total_inventory_items: 126
low_stock_found: 8

# Response should say:
"There are 8 items at or below the reorder point (out of 126 total inventory items):"
```

### Issue: Slow Response (>5 seconds for database query)

**Cause:** Unnecessary LLM call

**Check:** Backend logs should show `llm_calls: 0` for database queries

**Fix:** Ensure query intent is in `DB_QUERY_INTENTS` set

### Issue: "Backend offline" False Positive

**Cause:** Health check timeout too long

**Fix Applied:** Reduced timeout from 60s to 10s with 3 retries

### Issue: Stale Data in Response

**Cause:** Caching or local fallback

**Verification:** Check for `data_source: firestore_realtime` in logs

**Fix:** All queries now bypass cache and query Firestore directly

---

## Performance Benchmarks

After the performance fix, expected timings:

| Query Type | Target Time | Firestore Time | LLM Calls |
|------------|-------------|----------------|-----------|
| Low stock items | <1s | 200-500ms | 0 |
| Inventory overview | <1s | 200-500ms | 0 |
| Vehicle list | <1s | 200-400ms | 0 |
| Customer count | <1s | 100-300ms | 0 |
| Pending bookings | <1s | 200-400ms | 0 |
| Report generation | 2-5s | 500ms-2s | 0 |
| General AI query | 1-3s | 0ms | 1 |

---

## Test Execution Checklist

Before marking tests as PASSED:

- [ ] Verify response accuracy against Firestore console
- [ ] Check backend logs for performance metrics
- [ ] Confirm `data_source: firestore_realtime` in logs
- [ ] Verify counts are mathematically sound (low stock ≤ total)
- [ ] Test with fresh data (update Firestore, requery)
- [ ] Check response time is within target (<1s for DB queries)
- [ ] Verify no false "offline" messages during normal operation
- [ ] Confirm graceful error handling for invalid inputs
- [ ] Test report downloads (PDF and Excel) actually work
- [ ] Verify chat history persistence and deletion

---

## Logging Checklist

For each test, backend should log:

```
[FIRESTORE_QUERY] <function_name> - START
[FIRESTORE_QUERY] <function_name> - COMPLETE | 
  total_records: X | 
  records_returned: Y | 
  elapsed: 0.XXXs | 
  data_source: firestore_realtime

[FAST_PATH_DB] intent=<intent> | 
  firestore_ms=XXX | 
  llm_calls: 0

[AI PERFORMANCE] 
  firestore_reads: X | 
  firestore_ms: XXX | 
  llm_calls: 0 | 
  total_latency: 0.XXXs
```

---

## Final Verification

All tests PASS when:

1. ✅ All queries return accurate real-time Firestore data
2. ✅ Counts match database state exactly
3. ✅ Response times are within targets
4. ✅ No crashes on invalid input
5. ✅ Domain guard blocks non-automotive questions
6. ✅ Reports generate and download successfully
7. ✅ Chat history works (view, delete, persist)
8. ✅ Empty input is properly prevented
9. ✅ No-records scenarios handled gracefully
10. ✅ Backend logs confirm data source and performance

---

**Test Date:** December 2024  
**Status:** Ready for Execution  
**Critical Fix:** Low stock count accuracy (removed limit, added verification)
