# Report Download Button - Test Checklist

## Setup
1. Start the AI backend: `cd ai_assistant && venv\Scripts\activate && uvicorn main:app --port 8001`
2. Start the Flask web server: `python automotive_website/caltexautopro.py`
3. Open admin dashboard in browser
4. Open the Smart Reports AI widget

---

## Test 1: Basic Download Button (No Filters)

**Prompts to test:**
- "Generate vehicle report"
- "Download the vehicle report"
- "Export vehicle report as PDF"
- "Export vehicle report as Excel"

**Expected:**
- ✅ One sentence reply: "Your vehicle fleet report is ready."
- ✅ Single download button appears (PDF or Excel as requested)
- ✅ Button is clickable (no JS errors in console)
- ✅ File downloads successfully
- ✅ File contains ALL vehicles

---

## Test 2: Owner Filter

**Prompts:**
- "Generate a vehicle report for Juan Dela Cruz"
- "Generate a vehicle report for Maria Santos"

**Expected:**
- ✅ Reply: "Your vehicle fleet report is ready."
- ✅ Button appears and is clickable
- ✅ Downloaded file contains ONLY vehicles belonging to that owner
- ✅ If owner has no vehicles, error message appears: "No records were found matching the requested filters"

---

## Test 3: Status Filter

**Prompts:**
- "Generate an active vehicle report"
- "Generate an inactive vehicle report"
- "Generate a vehicle report for vehicles due for maintenance"

**Expected:**
- ✅ "due for maintenance" maps to status="Maintenance"
- ✅ Downloaded file contains ONLY vehicles with that status
- ✅ If no vehicles match, error message appears

---

## Test 4: Vehicle Type Filter (Plural Handling)

**Prompts:**
- "Generate a report for Trucks"
- "Generate a report for SUVs"
- "Generate a report for Sedans"
- "Generate a report for Vans"

**Expected:**
- ✅ "Trucks" matches vehicles with type="Truck" (plural → singular)
- ✅ "SUVs" matches type="SUV"
- ✅ "Sedans" matches type="Sedan"
- ✅ "Vans" matches type="Van"
- ✅ Downloaded file contains ONLY vehicles of that type

---

## Test 5: Multiple Filters

**Prompts:**
- "Generate an active truck report"
- "Generate a PDF report of active sedans"
- "Generate an Excel report for Juan Dela Cruz's vehicles"

**Expected:**
- ✅ Both filters applied (status AND vehicle_type, or owner AND format)
- ✅ Downloaded file contains ONLY records matching ALL filters
- ✅ Correct format button appears (PDF or Excel)

---

## Test 6: Date Filter - Past Month

**Prompts:**
- "Generate a vehicle report for the month of July" (if July is past)
- "Generate vehicle report for January 2024"

**Expected:**
- ✅ Downloaded file contains ONLY vehicles whose lastSvcDate falls in that month
- ✅ If no vehicles serviced in that month, error: "No records were found..."

---

## Test 7: Future Date - Should Fail

**Prompts:**
- "Generate vehicle report for December 2099"
- "Generate vehicle report for next year"

**Expected:**
- ❌ NO download button appears
- ✅ Error message: "No records found — the requested date range is in the future. Reports can only be generated for dates with existing historical data."
- ✅ User sees red error message in chat

---

## Test 8: Format Handling

**Prompts:**
- "Generate inventory report" → should default to PDF
- "Generate inventory report in Excel" → Excel button only
- "Generate inventory report in PDF and Excel" → BOTH buttons

**Expected:**
- ✅ Default (no format specified) = single PDF button
- ✅ Excel requested = single Excel button
- ✅ Both requested = both buttons (PDF primary red, Excel secondary grey)

---

## Test 9: Browser Console Checks

**Open browser DevTools Console and verify:**
- ✅ NO JavaScript errors when button appears
- ✅ NO syntax errors when button is clicked
- ✅ `window._ragReportParams` object exists and contains report data
- ✅ Network tab shows POST to `/api/ai-report` with correct payload
- ✅ Response is either a blob (success) or JSON error (failure)

---

## Test 10: Special Characters in Filters

**Prompts:**
- "Generate vehicle report for owner O'Brien" (apostrophe)
- "Generate vehicle report for owner María García" (accents)
- "Generate vehicle report for owner Smith & Sons" (ampersand)

**Expected:**
- ✅ Button renders without breaking HTML
- ✅ Button is clickable
- ✅ Downloaded file filters correctly by that exact owner name

---

## Known Issues Fixed

### ✅ FIXED: Button not clickable
**Cause:** `JSON.stringify(filters)` with quotes inside an HTML onclick attribute broke the syntax.

**Fix:** Report params stored in `window._ragReportParams[id]`, button only references the ID.

### ✅ FIXED: Wrong format buttons showing
**Cause:** Always showed both PDF and Excel regardless of request.

**Fix:** Checks `data.report_format` value ("pdf", "excel", or "both") and renders accordingly.

### ✅ FIXED: Reports generated for future dates
**Cause:** No validation — empty reports generated for dates with no data.

**Fix:** Pre-flight record count in `build_report()` — raises error before generating file.

### ✅ FIXED: Filters ignored
**Cause:** AI extracted filters but they never reached `_fetch_vehicles()`.

**Fix:** Full chain updated — AI → Flask → FastAPI → report_generator all pass filters correctly.

---

## How to Verify the Fix

1. **Open browser DevTools Console**
2. **Ask:** "Generate an Excel report for Juan Dela Cruz's vehicles"
3. **Check console — you should see:**
   ```
   window._ragReportParams
   // {
   //   rp_1234567890_5678: {
   //     reportType: "vehicles",
   //     month: null,
   //     startDate: null,
   //     endDate: null,
   //     filters: {owner: "Juan Dela Cruz"}
   //   }
   // }
   ```
4. **Click the button**
5. **Network tab should show:**
   ```
   POST /api/ai-report
   Request: {
     report_type: "vehicles",
     format: "excel",
     filters: {owner: "Juan Dela Cruz"}
   }
   Response: (blob download) or {success: false, error: "..."}
   ```
6. **Open the downloaded Excel file**
7. **Verify it contains ONLY Juan Dela Cruz's vehicles**

---

## If Button Still Doesn't Work

### Check 1: Is ragDownloadReport defined?
```javascript
// In browser console:
typeof window.ragDownloadReport
// Should output: "function"
```

### Check 2: Are params stored?
```javascript
// After clicking a report request:
Object.keys(window._ragReportParams || {})
// Should output: ["rp_1234567890_1234"]
```

### Check 3: What's the onclick attribute?
```javascript
// In browser console:
document.querySelector('.rag-bub button').getAttribute('onclick')
// Should output: "ragDownloadReport('rp_1234567890_1234','pdf')"
// NOT: "ragDownloadReport('vehicles','pdf',null,null,null,{"owner":"..."})"
```

### Check 4: Any JS errors?
Look for red errors in Console when:
1. Button appears
2. Button is clicked

### Check 5: Is Flask returning report_ready?
```javascript
// Watch Network tab → /api/ai-chat response:
{
  success: true,
  report_ready: true,
  report_type: "vehicles",
  report_format: "pdf",  // or "excel" or "both"
  report_filters: {owner: "Juan Dela Cruz"},
  answer: "Your vehicle fleet report is ready."
}
```

---

## Success Criteria

✅ All 10 test scenarios pass
✅ No JavaScript console errors
✅ Downloaded files contain correctly filtered data
✅ Future dates are rejected with clear error messages
✅ Special characters in filter values don't break the button
