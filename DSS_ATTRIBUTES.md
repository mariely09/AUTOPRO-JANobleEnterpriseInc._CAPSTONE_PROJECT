# DSS (Decision Support System) Attributes

## Overview

The Decision Support System (DSS) provides intelligent inventory management and preventive maintenance scheduling for AutoPro service centers. The system analyzes real-time data from Firestore to generate actionable insights, prioritize critical items, and send timely notifications to administrators and customers. This document outlines all attributes, calculations, and business logic used by both the mobile app and web platform.

The DSS consists of two main modules: Stock Replenishment and PMS Scheduling. Stock Replenishment monitors inventory levels, tracks consumption patterns, and recommends reorder quantities based on historical usage data. PMS Scheduling tracks vehicle maintenance schedules, calculates due dates, and alerts both service center staff and vehicle owners when maintenance is approaching or overdue.

Both systems operate autonomously with daily automated checks while providing manual override capabilities for administrators. All calculations are performed in real-time to ensure accuracy, and notifications are filtered based on user-specific alert preferences stored in the Firestore `users` collection.

---

## 📦 Stock Replenishment Attributes

### **Data Sources:**
- **Primary Collection**: `stock_inventory`
- **Secondary Collection**: `issuances` (for consumption tracking)

### **Core Stock Attributes:**

| Attribute | Type | Source | Description |
|-----------|------|--------|-------------|
| `name` | String | `stock_inventory.name` | Item name/description |
| `itemNum` | String | `stock_inventory.num` or `stock_inventory.itemNum` | Unique item number/SKU |
| `uom` | String | `stock_inventory.uom` | Unit of measure (pcs, ltr, kg, etc.) |
| `stock` | Integer | `stock_inventory.stock` | Current stock level |
| `min` | Integer | `stock_inventory.min` | Minimum stock threshold |
| `max` | Integer | `stock_inventory.max` | Maximum stock capacity |
| `reorderQty` | Integer | `stock_inventory.reorder` | Standard reorder quantity |
| `group` | String | `stock_inventory.group` | Commodity/product group |

### **Calculated Attributes:**

| Attribute | Type | Formula/Logic | Description |
|-----------|------|---------------|-------------|
| `consumptionRate` | Decimal | `totalConsumed / daySpan` | Daily consumption rate (units/day) |
| `totalConsumed` | Decimal | Sum of all `issuances.qty` for item | Total consumed in tracking period |
| `daySpan` | Integer | Days between earliest issuance and today (min: 1, default: 30) | Consumption tracking period |
| `daysLeft` | Integer | `stock / dailyRate` | Days until stock depletes |
| `leadNeed` | Integer | `dailyRate × 7` | 7-day lead time buffer requirement |
| `recommendQty` | Integer | `max(deficit, reorderQty)` where `deficit = max - stock` | Recommended order quantity |
| `priorityScore` | Integer | 0 = Out of Stock, 1 = Low Stock, 2 = In Stock | Numeric priority (lower = urgent) |
| `priority` | String | "Out of Stock", "Low Stock", "In Stock" | Priority label |

### **Priority System:**

The Stock Replenishment system uses a 3-tier color-coded priority classification to help administrators quickly identify critical inventory situations. Items with zero stock are marked as "Out of Stock" (red) and trigger urgent emergency order alerts. Items at or below the minimum threshold are classified as "Low Stock" (yellow) and require planning for upcoming orders. Items above the minimum threshold are considered "In Stock" (green) and only require routine monitoring. Each priority level has a corresponding action recommendation displayed in the card view: "URGENT: Emergency order" for out of stock items, "SOON: Plan to order" for low stock items, and "MONITOR: No action needed" for in-stock items.

| Priority | Condition | Color | Action Required |
|----------|-----------|-------|-----------------|
| **Out of Stock** | `stock == 0` | 🔴 Red (#e53e3e) | URGENT: Emergency order |
| **Low Stock** | `stock <= min` | 🟡 Yellow (#d69e2e) | SOON: Plan to order |
| **In Stock** | `stock > min` | 🟢 Green (#38a169) | MONITOR: No action needed |

### **Consumption Tracking (from `issuances`):**

| Field | Type | Usage |
|-------|------|-------|
| `itemNum` | String | Links to stock item |
| `qty` or `quantity` | Number/String | Quantity issued |
| `date` | String | Issuance date (YYYY-MM-DD, M/D/YYYY, or "Jan 1, 2025") |

---

## 🚗 PMS (Preventive Maintenance Scheduling) Attributes

### **Data Source:**
- **Primary Collection**: `vehicles`

### **Core Vehicle Attributes:**

| Attribute | Type | Source | Description |
|-----------|------|--------|-------------|
| `plate` | String | `vehicles.plate` | Vehicle plate number |
| `desc` | String | `vehicles.desc` | Vehicle description/model |
| `lastSvcDate` | String | `vehicles.lastSvcDate` | Last service date (YYYY-MM-DD) |
| `svcFreq` | Integer | `vehicles.svcFreq` | Service frequency (months) |
| `ownerId` | String | `vehicles.ownerId` or `vehicles.customerId` | Vehicle owner UID (for customer alerts) |

### **Calculated Attributes:**

| Attribute | Type | Formula/Logic | Description |
|-----------|------|---------------|-------------|
| `nextPMS` | Date String | `lastSvcDate + svcFreq months` (YYYY-MM-DD) | Next scheduled service date |
| `daysUntil` | Integer | `(nextPMS midnight - today midnight).days` | Days until next service |
| `due` | String | Formatted message based on `daysUntil` | Human-readable due status |
| `priority` | String | Based on `daysUntil` thresholds | Priority category |

### **Priority System:**

The PMS Scheduling system employs a 5-tier priority classification that categorizes vehicles based on how soon their preventive maintenance is due. This granular approach ensures that administrators can effectively prioritize service appointments and resource allocation. Overdue vehicles (red) require immediate scheduling as they have missed their maintenance window. Vehicles due today (blue) need same-day service attention. Those due this week (orange) should have appointments booked within the current week. Vehicles due soon (brown) fall within a 8-14 day window and require advance planning. Active vehicles (green) have maintenance scheduled more than two weeks out and only need routine monitoring. Customer notifications are sent separately to vehicle owners with the same priority logic but personalized messaging.

| Priority | Condition | Color | Days Until | Action Required |
|----------|-----------|-------|------------|-----------------|
| **Overdue** | `daysUntil < 0` | 🔴 Red (#E8001C) | Negative | URGENT: Schedule immediately |
| **Due Today** | `daysUntil == 0` | 🔵 Blue (#0033A0) | 0 | TODAY: Service required |
| **Due This Week** | `daysUntil <= 7` | 🟠 Orange (#dd6b20) | 1-7 days | THIS WEEK: Book appointment |
| **Due Soon** | `daysUntil <= 14` | 🟤 Brown (#b7791f) | 8-14 days | SOON: Plan ahead |
| **Active** | `daysUntil > 14` | 🟢 Green (#276749) | 15+ days | ACTIVE: Monitor |

### **Due Message Format:**

| Priority | Message Format | Example |
|----------|----------------|---------|
| Overdue | `"Overdue X day(s)"` | "Overdue 5 day(s)" |
| Due Today | `"Due today"` | "Due today" |
| Due This Week | `"Due in X day(s)"` | "Due in 3 day(s)" |
| Due Soon | `"Due in X days"` | "Due in 10 days" |
| Active | `"Due in X days"` | "Due in 25 days" |

---

## 🔔 Notification Triggers

The DSS notification system sends real-time push notifications via OneSignal and creates in-app notifications in the Firestore `notifications` collection. All notifications respect user-defined alert preferences stored in the `users` collection under specific preference keys such as `lowStock`, `pmsOverdue`, `pmsDueThisWeek`, and `pmsDueSoon`. This ensures that users only receive notifications for alert types they have explicitly enabled. Notifications are sent once per calendar day using a Firestore deduplication sentinel document to prevent spam, though administrators can manually force-resend alerts when needed for urgent situations or testing purposes.

### **Stock Replenishment Notifications:**

| Alert Type | Trigger Condition | Target | Emoji | Preference Key |
|------------|-------------------|--------|-------|----------------|
| **Out of Stock** | `stock == 0` | Admin | 🚨 | `lowStock` |
| **Low Stock** | `stock <= min` | Admin | ⚠️ | `lowStock` |

**Notification Message Format:**
- Out of Stock: `"{name} is out of stock. Recommend ordering {recommendQty} {uom}."`
- Low Stock: `"{name} is low ({stock} {uom}). Recommend ordering {recommendQty} {uom}."`

### **PMS Notifications:**

#### **Admin Alerts:**

| Alert Type | Trigger Condition | Emoji | Preference Key |
|------------|-------------------|-------|----------------|
| **PMS Overdue** | `daysUntil < 0` | 🚗 | `pmsOverdue` |
| **PMS Due Today** | `daysUntil == 0` | ⏰ | `pmsDueThisWeek` |
| **PMS Due This Week** | `daysUntil <= 7` | 📅 | `pmsDueThisWeek` |
| **PMS Due Soon** | `daysUntil <= 14` | 🔔 | `pmsDueSoon` |

#### **Customer Alerts:**

| Alert Type | Trigger Condition | Emoji | Preference Key |
|------------|-------------------|-------|----------------|
| **Your PMS is Overdue** | `daysUntil < 0` | 🚗 | `pmsOverdue` |
| **Your PMS is Due Today** | `daysUntil == 0` | ⏰ | `pmsDueThisWeek` |
| **Your PMS is Due This Week** | `daysUntil <= 7` | 📅 | `pmsDueThisWeek` |
| **Your PMS is Due Soon** | `daysUntil <= 14` | 🔔 | `pmsDueSoon` |

**Notification Message Format:**
- Overdue: `"{plate} is {X} day(s) overdue for maintenance."`
- Due Today: `"{plate} is due for maintenance today."`
- Due This Week: `"{plate} is due for maintenance this week ({X} day(s))."`
- Due Soon: `"{plate} is due for maintenance in {X} day(s)."`

---

## 🎯 KPI Metrics Display

The DSS displays real-time Key Performance Indicator (KPI) metrics at the top of each module to provide administrators with an at-a-glance overview of critical items requiring attention. These KPI chips are interactive and serve as filters—tapping a KPI immediately filters the list to show only items in that category. The counts update automatically as inventory levels change or vehicles approach their maintenance dates, ensuring administrators always have current information for decision-making. Stock Replenishment shows counts for out-of-stock and low-stock items, while PMS Scheduling displays counts across all five priority levels (overdue, due today, due this week, due soon, and active).

### **Stock Replenishment KPIs:**
- **Out of Stock Count**: Number of items with `stock == 0`
- **Low Stock Count**: Number of items with `stock <= min`

### **PMS Scheduling KPIs:**
- **Overdue Count**: Vehicles with `daysUntil < 0`
- **Due Today Count**: Vehicles with `daysUntil == 0`
- **Due This Week Count**: Vehicles with `daysUntil <= 7`
- **Due Soon Count**: Vehicles with `daysUntil <= 14`
- **Active Count**: Vehicles with `daysUntil > 14`

---

## 🔍 Filter & Sort Options

The DSS provides comprehensive filtering and sorting capabilities to help administrators focus on specific subsets of data and organize information according to their workflow needs. Filters allow narrowing down the list to specific priority categories, while sort options enable ordering items by various criteria such as urgency, stock levels, or alphabetical order. A real-time search feature filters items as you type, searching across multiple fields including item names, numbers, descriptions, and categories. All filters, sorts, and searches work together seamlessly and update the list instantly without requiring page reloads.

### **Stock Replenishment:**

**Filters:**
- All (default)
- Out of Stock only
- Low Stock only

**Sort Options:**
- Stock (Lowest First) - default
- Stock (Highest First)
- Item Name A → Z
- Item Name Z → A

**Search Fields:**
- Item name
- Item number
- Commodity group

### **PMS Scheduling:**

**Filters:**
- All (default)
- Overdue only
- Due Today only
- Due This Week only
- Due Soon only
- Active only

**Sort Options:**
- Next PMS Date (Soonest) - default
- Next PMS Date (Latest)
- Plate A → Z
- Plate Z → A

**Search Fields:**
- Plate number
- Vehicle description
- Priority status

---

## 📊 Card Display Layout

Each DSS module presents data in a card-based layout designed for quick scanning and detailed inspection. Stock Replenishment cards display comprehensive inventory analytics including consumption rates, days remaining until depletion, and actionable recommendations. PMS Scheduling cards show vehicle maintenance status with clear visual priority indicators and due date information. Tapping any card opens a detailed modal with complete information about that item or vehicle. The card design follows the Caltex AutoPro color scheme with priority-based color coding for immediate visual recognition of critical items.

### **Stock Replenishment Card Shows:**
1. **Header**: Item name, item number, UOM, priority badge
2. **Stock Status**: Progress bar, min/current/max values
3. **Consumption Analysis**: Rate, total consumed, lead time need
4. **Days Left**: Time until depletion
5. **Recommended Order**: Quantity to order
6. **Decision**: Actionable recommendation

### **PMS Scheduling Card Shows:**
1. **Header**: Plate number, priority badge
2. **Vehicle Info**: Description
3. **Status**: Days until due, due date message
4. **Detail Modal**: Last service date, next PMS date, full vehicle info

---

## 🕒 Alert Schedule

The DSS notification system operates on a once-per-day schedule to balance timely alerts with user experience. Notifications are sent automatically when administrators open the DSS screen on the mobile app, or via the `checkDSSAlerts` Cloud Function on the web platform (triggered hourly by cron or manually by administrators). A Firestore sentinel document stored in the `dss_alert_log` collection with the current date as the document ID prevents duplicate notifications within the same calendar day. This deduplication mechanism resets at midnight, allowing fresh alerts the next day. Administrators can bypass this deduplication by using the force-resend feature, which deletes the sentinel document and triggers new alerts immediately—useful for testing or urgent situations requiring immediate notification.

**Key Details:**
- **Frequency**: Once per calendar day
- **Deduplication**: Firestore sentinel doc (`dss_alert_log/{YYYY-MM-DD}`)
- **Manual Trigger**: Force resend available (bypasses dedup)
- **Target Users**: Filtered by user alert preferences in `users` collection

---

## 📱 Implementation Details

The DSS is implemented across both mobile (Flutter) and web (Python/Flask) platforms with consistent business logic to ensure identical calculations and recommendations regardless of the access point. The mobile app performs all DSS calculations client-side using Firestore real-time snapshots, providing instant updates as inventory or vehicle data changes. Push notifications are sent directly via the OneSignal REST API with proper user preference filtering. The web platform delegates scheduled processing to Firebase Cloud Functions, specifically the `checkDSSAlerts` function which runs on an hourly cron schedule and can also be triggered manually by administrators. Both platforms share the same consumption rate algorithms, priority classification logic, and notification message templates to maintain consistency across the user experience.

### **Mobile App (Flutter):**
- Location: `automotive_mobile/lib/admin_dss.dart`
- Real-time updates via Firestore snapshots
- Direct OneSignal push notification integration
- In-app deduplication guard (session + Firestore sentinel)

### **Website (Python/Flask):**
- Location: `automotive_website/templates/admin_dss.html`
- Cloud Function trigger: `checkDSSAlerts` (hourly cron + manual)
- Same calculation logic as mobile for consistency

### **Firestore Collections Used:**
```
stock_inventory/        → Stock items
issuances/             → Consumption records
vehicles/              → Vehicle fleet
users/                 → Alert preferences
notifications/         → In-app notifications
dss_alert_log/         → Daily deduplication
```

---

## 🧮 Calculation Examples

### **Stock Replenishment Example:**
```
Item: "Mobil 1 5W-30 Motor Oil"
- Current Stock: 15 liters
- Min: 20 liters
- Max: 100 liters
- Reorder: 50 liters
- Consumption: 60 liters over 30 days
- Daily Rate: 60 ÷ 30 = 2 liters/day
- Days Left: 15 ÷ 2 = 7 days
- Lead Need: 2 × 7 = 14 liters
- Deficit: 100 - 15 = 85 liters
- Recommend: max(85, 50) = 85 liters
- Priority: "Low Stock" (stock <= min)
- Decision: "SOON: Plan to order"
```

### **PMS Scheduling Example:**
```
Vehicle: "ABC-1234"
- Last Service: 2026-07-15
- Service Freq: 6 months
- Next PMS: 2027-01-15
- Today: 2026-09-14
- Days Until: 123 days
- Priority: "Active"
- Due: "Due in 123 days"
- Action: "ACTIVE: Monitor"
```

---

## 📝 Notes

**Consumption Rate Accuracy**: The accuracy of stock replenishment recommendations depends heavily on consistent and complete data entry in the issuances collection. Missing issuance records or irregular data entry patterns can significantly affect consumption rate calculations and lead to inaccurate reorder recommendations. Service centers should establish a disciplined process for recording all inventory issuances in real-time to maximize the DSS's effectiveness.

**Date Format Flexibility**: The system handles multiple date formats including ISO standard (YYYY-MM-DD), US format (M/D/YYYY), and locale-specific formats (e.g., "Jan 1, 2025") to ensure backward compatibility with existing data and accommodate different data entry practices across locations. This flexibility prevents migration issues but may introduce edge cases if date formats are inconsistent within the same collection.

**Customer Privacy and Preferences**: Customer PMS alerts are only sent to vehicle owners identified by the `ownerId` field in the vehicles collection. Each customer has independent alert preference settings in their user profile, ensuring they only receive notifications they've explicitly enabled. This separation between admin and customer notifications respects user autonomy and prevents unwanted alerts while still keeping vehicle owners informed about their maintenance schedules.

**Admin Control and Testing**: Administrators have full control over the notification system including the ability to force-resend alerts by bypassing the daily deduplication guard. This feature is essential for testing notification flows during development and deployment, as well as for urgent situations where immediate re-notification is required regardless of the daily limit. The force-resend function deletes the sentinel document and triggers a fresh round of calculations and notifications.

**Performance Considerations**: All DSS calculations in the mobile app are performed client-side on the device to provide instant visual feedback and eliminate server round-trips for basic list filtering and sorting. This approach scales well even with hundreds of inventory items or vehicles because modern mobile processors handle these calculations efficiently. The web platform uses Cloud Functions for scheduled processing to distribute the computational load and ensure consistent background operation even when no users are actively viewing the DSS screens.

1. **Consumption Rate Accuracy**: Requires consistent issuance data entry. Missing or irregular entries affect recommendations.

2. **Date Format Flexibility**: System handles multiple date formats (ISO, M/D/YYYY, locale) for backward compatibility.

3. **Customer Privacy**: Customer PMS alerts only sent to vehicle owners (via `ownerId` field) with their own preference settings.

4. **Admin Control**: Admins can force-resend alerts to bypass daily deduplication for testing or urgent updates.

5. **Performance**: All calculations done client-side on mobile for instant updates; Cloud Functions used for scheduled/background processing on web.
