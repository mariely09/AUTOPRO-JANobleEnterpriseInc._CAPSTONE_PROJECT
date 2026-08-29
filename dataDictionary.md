# Data Dictionary — Automotive Service (Firestore)

> **Database:** Google Cloud Firestore (NoSQL document database)
> **Project:** Caltex AutoPro — Automotive Service Management System
> **Last Updated:** August 27, 2026

---

## Collections Overview

| # | Collection | Purpose |
|---|---|---|
| 1 | `users` | Registered users (admin, staff, customer) |
| 2 | `vehicles` | Fleet / customer vehicles |
| 3 | `maintenance` | Vehicle service and repair jobs |
| 4 | `service_bookings` | Customer service appointment requests |
| 5 | `stock_inventory` | Current physical stock levels |
| 6 | `item_master` | Product and service catalog |
| 7 | `issuances` | Materials/services issued per maintenance job |
| 8 | `deliveries` | Supplier purchase orders and received stock |
| 9 | `transactions` | Inventory movement log (IN/OUT) |
| 10 | `notifications` | In-app notifications for all users |
| 11 | `otp_requests` | OTP codes for email verification |
| 12 | `domains` | Admin-managed lookup/dropdown lists |
| 13 | `_pmsAlertLog` | DSS alert deduplication guard |
| 14 | `archive` | Soft-deleted records (vehicles, users, items) |

---

## 1. Collection: `users`

**Document ID:** Firebase Auth UID
**Purpose:** Stores all registered user accounts — admins, staff, and customers.

| Field Name | Data Type | Constraints | Description |
|---|---|---|---|
| `uid` | String | Required | Firebase Auth UID; mirrors the document ID |
| `firstName` | String | Required | User's first name |
| `lastName` | String | Required | User's last name |
| `name` | String | Required | Full name (`firstName + " " + lastName`); used for vehicle owner matching |
| `email` | String | Required, Unique | Firebase Auth email address |
| `role` | String | Required; Enum: `admin`, `staff`, `customer` | Access role; controls feature visibility in the app |
| `status` | String | Enum: `Active`, `Inactive`, `Pending` | Account status |
| `phoneNumber` | String | Optional; format: `+63XXXXXXXXXX` | Mobile phone number |
| `companyName` | String | Optional; customers only | Company or fleet operator name |
| `photoUrl` | String | Optional; base64 data URI | Profile photo stored as `data:image/jpeg;base64,...` |
| `mustChangePassword` | Boolean | Default: `false` | Set to `true` for admin-created accounts; forces password change on first login |
| `oneSignalId` | String | Optional | OneSignal subscription ID for push notifications |
| `createdAt` | Timestamp | Server-set | Server timestamp written on account creation |

### Subcollection: `users/{uid}/settings`

**Document ID:** `alerts` (always this fixed ID)
**Purpose:** Per-user notification and alert preferences.

| Field Name | Data Type | Constraints | Description |
|---|---|---|---|
| `inAppEnabled` | Boolean | Default: `true`; all roles | Enable in-app notification display |
| `emailEnabled` | Boolean | Default: `true`; all roles | Enable email notifications to registered address |
| `pmsOverdue` | Boolean | Default: `true`; all roles | Notify when a vehicle is overdue for scheduled maintenance |
| `pmsDueToday` | Boolean | Default: `true`; all roles | Notify when PMS is due today |
| `pmsDueThisWeek` | Boolean | Default: `true`; all roles | Notify when PMS is due within 7 days |
| `pmsDueSoon` | Boolean | Default: `true`; all roles | Notify when PMS is due within 14 days |
| `serviceUpdate` | Boolean | Default: `true`; staff & admin only | Notify on service status changes |
| `newAssignment` | Boolean | Default: `true`; staff & admin only | Notify when a service job is assigned |
| `lowStock` | Boolean | Default: `true`; admin only | Notify when stock falls below minimum level |
| `bookingReminder` | Boolean | Default: `true`; customer only | Notify customer of upcoming booking |
| `vehicleUnderMaint` | Boolean | Default: `true`; customer only | Notify customer when their vehicle goes under maintenance |
| `newBookingRequest` | Boolean | Default: `true`; staff & admin only | Notify when a customer submits a new booking |
| `bookingCancellation` | Boolean | Default: `true`; staff & admin only | Notify when a booking is cancelled |
| `updatedAt` | Timestamp | Server-set | Server timestamp of last preference save |

---

## 2. Collection: `vehicles`

**Document ID:** Auto-generated
**Purpose:** Registry of all fleet and customer vehicles.

> **Note — Dual-field pattern:** Older documents store fields under short legacy names. New documents write both canonical and legacy names simultaneously. Queries must check both.

| Field Name | Data Type | Constraints | Description |
|---|---|---|---|
| `plateNumber` | String | Canonical; uppercase; enforced unique at write | Vehicle plate number (e.g., `ABC 1234`) |
| `plate` | String | Legacy alias for `plateNumber` | Written in parallel with `plateNumber` for backward compatibility |
| `description` | String | Canonical | Vehicle make, model, and year (e.g., `Toyota Hilux 2022`) |
| `desc` | String | Legacy alias for `description` | Older documents use this field |
| `assetDescription` | String | Legacy alias | Used in older import scripts |
| `type` | String | Value from `domains/vehicle_types` | Vehicle type (e.g., `Car`, `Truck`, `SUV`, `Van`) |
| `owner` | String | Required | Customer full name or company name; used for fuzzy owner-to-vehicle joins |
| `ownerId` | String | FK → `users` (doc ID) | Firebase Auth UID of the owning customer; authoritative foreign key |
| `odometer` | Number | Canonical; in kilometers | Current odometer reading |
| `odo` | String | Legacy alias; format: `"12345 km"` | Older documents store odometer as a formatted string |
| `lastServiceDate` | String | Canonical; format: `YYYY-MM-DD` | Date of most recent completed service |
| `lastSvcDate` | String | Legacy alias for `lastServiceDate` | Older documents use this field |
| `lastServiceOdometer` | Number | Canonical | Odometer reading at the time of the last service |
| `lastSvcOdo` | String | Legacy alias | Older documents use this field |
| `serviceFrequency` | Number | Canonical; in months | How often scheduled PMS should occur |
| `svcFreq` | String | Legacy alias for `serviceFrequency` | Older documents store frequency as a string |
| `status` | String | Enum: `Active`, `Under Maintenance`, `Overdue`, `PMS Due Soon`, `Completed` | Current operational status of the vehicle |
| `nextPMSDue` | String | Format: `YYYY-MM-DD` | Calculated next PMS due date; updated on service completion |
| `completedAt` | Timestamp | Server-set | When the latest maintenance was completed |
| `archived` | Boolean | Default: `false` | Soft-delete flag; `true` means vehicle is archived |
| `archivedAt` | Timestamp | Set on archive | Server timestamp when the vehicle was archived |
| `createdAt` | Timestamp | Server-set | Server timestamp of document creation |

---

## 3. Collection: `maintenance`

**Document ID:** Auto-generated
**Purpose:** Individual vehicle service and repair job records.

| Field Name | Data Type | Constraints | Description |
|---|---|---|---|
| `id` | String | Format: `SVC-YYYYMMDD-HHmmss` | Human-readable job ID |
| `plateNumber` | String | Canonical; uppercase | Vehicle plate number |
| `plate` | String | Legacy alias for `plateNumber` | Older records use this field |
| `vehicleId` | String | FK → `vehicles` (doc ID) | Firestore document ID of the serviced vehicle |
| `ownerId` | String | FK → `users` (doc ID) | Firebase Auth UID of the vehicle owner; authoritative FK |
| `desc` | String | Snapshot at job creation | Vehicle description captured when the job was created |
| `mechanic` | String | Required | Full name of the assigned mechanic or staff member |
| `date` | String | Format: `"Mon DD, YYYY"` (e.g., `"Jan 5, 2026"`) | Display date of the service |
| `odometer` | Number | In kilometers | Odometer reading at time of service |
| `cost` | String | Format: `"₱1,234.50"` | Total job cost as a formatted currency string |
| `status` | String | Enum: `Ongoing`, `Completed` | Current job status |
| `issues` | Array of Strings | Optional | Vehicle issues reported by the customer (e.g., `["Brake Issue", "Oil Leak"]`) |
| `svcRows` | Array of Maps | Optional | Services performed; each map contains: `name` (string), `qty` (string), `uom` (string), `cost` (string) |
| `matRows` | Array of Maps | Optional | Materials used; each map contains: `name` (string), `qty` (string), `uom` (string), `cost` (string) |
| `bookingId` | String | Optional; FK → `service_bookings` (doc ID) | Links back to the originating booking, if the job came from a customer booking |
| `archived` | Boolean | Default: `false` | Soft-delete flag |
| `archivedAt` | Timestamp | Set on archive | Server timestamp when record was archived |
| `createdAt` | Timestamp | Server-set | Server timestamp of document creation |

### Embedded Map — `svcRows[*]` and `matRows[*]`

| Field Name | Data Type | Description |
|---|---|---|
| `name` | String | Item or service name (FK to `item_master.name`) |
| `qty` | String | Quantity (stored as string) |
| `uom` | String | Unit of measure |
| `cost` | String | Unit cost as a numeric string |

---

## 4. Collection: `service_bookings`

**Document ID:** Auto-generated
**Purpose:** Customer-submitted service appointment requests and their lifecycle states.

| Field Name | Data Type | Constraints | Description |
|---|---|---|---|
| `customerId` | String | Required; FK → `users` (doc ID) | Firebase Auth UID of the booking customer |
| `customerName` | String | Snapshot | Customer full name captured at booking time |
| `vehicleId` | String | FK → `vehicles` (doc ID) | Firestore document ID of the vehicle to be serviced |
| `plate` | String | Snapshot | Vehicle plate captured at booking time |
| `vehicleDesc` | String | Snapshot | Vehicle description captured at booking time |
| `services` | Array of Strings | Required; min 1 item | Names of the requested services |
| `preferredDate` | String | Format: `YYYY-MM-DD` | Customer's preferred service date |
| `preferredTime` | String | e.g., `"8:00 AM"` | Customer's preferred time slot |
| `notes` | String | Optional | Additional notes or instructions from the customer |
| `status` | String | Enum: `Pending`, `Approved`, `Under Maintenance`, `Completed`, `Cancelled` | Booking lifecycle status |
| `autoApproved` | Boolean | Default: `false` | `true` when booking was approved automatically without admin review |
| `usedAiSuggestion` | Boolean | Default: `false` | `true` if the customer used an AI-suggested date |
| `previousDate` | String | Set on reschedule; format: `YYYY-MM-DD` | Original preferred date before rescheduling |
| `previousTime` | String | Set on reschedule | Original preferred time before rescheduling |
| `rescheduledBy` | String | Set on reschedule; e.g., `"admin"` | Who performed the reschedule |
| `rescheduledAt` | Timestamp | Server-set on reschedule | When the booking was rescheduled |
| `cancelledAt` | Timestamp | Server-set on cancellation | When the booking was cancelled |
| `cancelledBy` | String | e.g., `"admin"`, `"system"`, `"customer"` | Who or what triggered the cancellation |
| `cancellationReason` | String | Optional | Reason for system or admin cancellation |
| `createdAt` | Timestamp | Server-set | Server timestamp of booking creation |

---

## 5. Collection: `stock_inventory`

**Document ID:** Auto-generated
**Purpose:** Tracks the current on-hand quantity for each material item.

| Field Name | Data Type | Constraints | Description |
|---|---|---|---|
| `num` | String | Unique; FK → `item_master.num` | Item number; synced from the item master catalog |
| `supplierCode` | String | Synced from `item_master` | Supplier's own item code |
| `name` | String | Synced from `item_master` | Item name |
| `group` | String | Synced from `item_master` | Commodity group |
| `uom` | String | Synced from `item_master` | Unit of measure |
| `stock` | Number | Default: `0`; non-negative | Current quantity on hand |
| `min` | Number | Default: `0` | Minimum stock level; stock at or below this triggers `Low` status |
| `max` | Number | Default: `0` | Maximum stock level; stock above this triggers `Over` status |
| `reorder` | Number | Default: `0` | Reorder quantity; calculated as `max - stock` |
| `status` | String | Auto-computed; Enum: `OK`, `Low`, `Over` | Stock level status: `Low` if `stock ≤ min`, `Over` if `stock > max`, else `OK` |
| `createdAt` | Timestamp | Server-set | Server timestamp of document creation |
| `updatedAt` | Timestamp | Server-set | Server timestamp of last stock update |

---

## 6. Collection: `item_master`

**Document ID:** Auto-generated
**Purpose:** Master catalog of all materials and services offered or used.

| Field Name | Data Type | Constraints | Description |
|---|---|---|---|
| `num` | String | Auto-incremented; zero-padded (e.g., `"001"`) | Internal item number; unique identifier |
| `supplierCode` | String | Optional | Supplier's item code; used as the seed for barcode generation |
| `oem` | String | Optional | OEM (Original Equipment Manufacturer) part number |
| `sku` | String | Optional | Internal stock-keeping unit code |
| `name` | String | Required | Item or service name |
| `desc` | String | Optional | Detailed description of the item |
| `group` | String | Value from `domains/commodity_groups` | Commodity group category |
| `uom` | String | Value from `domains/uom` | Unit of measure |
| `cost` | String | Format: `"₱123.45"` | Unit cost as a formatted currency string |
| `type` | String | Canonical; Enum: `Material`, `Service` | Distinguishes physical materials from labor/service items |
| `itemType` | String | Legacy alias for `type` | Older documents use this field |
| `barcode` | String | Auto-generated for `Material` type | EAN-13 barcode value |
| `qr` | String | Format: `"QR-{supplierCode}"` | QR code value for scanning |
| `archived` | Boolean | Default: `false` | Soft-delete flag |
| `archivedAt` | Timestamp | Set on archive | Server timestamp when the item was archived |
| `createdAt` | Timestamp | Server-set | Server timestamp of document creation |

---

## 7. Collection: `issuances`

**Document ID:** Auto-generated
**Purpose:** Audit trail of every material and service item issued against a maintenance job. Auto-created when a maintenance job is marked Completed.

| Field Name | Data Type | Constraints | Description |
|---|---|---|---|
| `id` | String | Format: `ISS-AUTO-{timestamp}` or `ISS-AUTO-{timestamp}-S` (services) | Human-readable issuance ID |
| `maintenanceId` | String | FK → `maintenance.id` | Human-readable ID of the parent maintenance job (e.g., `SVC-20260105-083000`) |
| `plate` | String | Legacy; uppercase | Vehicle plate number |
| `plateNumber` | String | Canonical alias for `plate` | Canonical vehicle plate field |
| `assetDesc` | String | Snapshot | Vehicle description at time of issuance |
| `itemNum` | String | FK → `item_master.num` | Item number of the issued material or service |
| `itemName` | String | Snapshot | Item name at time of issuance |
| `itemType` | String | Enum: `Material`, `Service` | Whether this issuance is for a physical material or a service |
| `commodityGroup` | String | Snapshot from `item_master` | Commodity group at time of issuance |
| `uom` | String | | Unit of measure |
| `qty` | String | Positive numeric string | Quantity issued |
| `unitCost` | String | Numeric string | Unit cost at time of issuance |
| `subtotal` | String | Numeric string; `qty × unitCost` | Total cost for this line item |
| `createdBy` | String | | Full name of the admin or staff who created the record |
| `date` | String | Format: `"Mon DD, YYYY"` | Display date of issuance |
| `createdAt` | Timestamp | Server-set | Server timestamp of document creation |

---

## 8. Collection: `deliveries`

**Document ID:** Auto-generated
**Purpose:** Tracks incoming supplier deliveries and purchase orders through a multi-step receiving and approval workflow.

| Field Name | Data Type | Constraints | Description |
|---|---|---|---|
| `supplier` | String | Required | Name of the supplier |
| `date` | String | ISO or display format | Expected or actual delivery date |
| `status` | String | Enum: `Pending`, `For Admin Review`, `Awaiting Double Check`, `Approved`, `Rejected` | Overall delivery status |
| `receivedBy` | String | | Name of the staff who received the delivery |
| `checkedBy` | String | | Name of the admin who performed double-check |
| `notes` | String | Optional | General notes about the delivery |
| `reviewNotes` | String | Optional | Admin comments from the review step |
| `receivedAt` | Timestamp | Server-set | When the delivery was received |
| `reviewedAt` | Timestamp | Server-set | When the admin reviewed the delivery |
| `createdAt` | Timestamp | Server-set | When the delivery order was created |
| `items` | Array of Maps | Required; min 1 item | Embedded list of line items in the delivery (see below) |

### Embedded Map — `items[*]`

| Field Name | Data Type | Description |
|---|---|---|
| `itemNum` | String | FK → `item_master.num`; item number |
| `itemName` | String | Item name |
| `uom` | String | Unit of measure |
| `supplierCode` | String | Supplier's item code |
| `expectedQty` | Number | Ordered/expected quantity |
| `actualQty` | Number | Quantity actually received; filled during receiving step |
| `condition` | String | Enum: `OK`, `Defective`, `Shortage` — condition of received item |
| `remark` | String | Optional per-item remarks |
| `itemStatus` | String | Per-item status; mirrors delivery `status` enum |
| `receivedBy` | String | Name of who received this specific item |
| `receivedAt` | String | ISO datetime string of when item was received |
| `checkedBy` | String | Name of admin who verified this item |
| `reviewNotes` | String | Per-item admin review notes |
| `reviewedAt` | String | ISO datetime string of when item was reviewed |
| `stockAtReceive` | Number | Stock level frozen at receive time for reference |

---

## 9. Collection: `transactions`

**Document ID:** Auto-generated
**Purpose:** Immutable inventory movement log recording every stock IN (receiving) and stock OUT (issuance) event.

| Field Name | Data Type | Constraints | Description |
|---|---|---|---|
| `item` | String | FK → `item_master.name` (by name) | Name of the item involved in the transaction |
| `desc` | String | | Human-readable description: e.g., `"Issued for maintenance SVC-... — ABC 1234"` or `"Stock received — delivery"` |
| `type` | String | Enum: `IN`, `OUT` | Direction of stock movement: `IN` for receiving, `OUT` for issuance |
| `qty` | String | Format: `"-3"` (OUT) or `"+5"` (IN) | Signed quantity string |
| `date` | String | Format: `"Mon DD, YYYY"` | Display date of the transaction |
| `by` | String | | Full name of the staff or admin who performed the action |
| `commodityGroup` | String | | Commodity group of the item |
| `assetDesc` | String | OUT transactions only | Vehicle description (for issuances tied to a maintenance job) |
| `plate` | String | OUT transactions only | Vehicle plate (for issuances tied to a maintenance job) |
| `createdAt` | Timestamp | Server-set | Server timestamp of document creation |

---

## 10. Collection: `notifications`

**Document ID:** Auto-generated
**Purpose:** In-app notifications displayed to users. Each document targets either all users of a given role or a specific individual.

| Field Name | Data Type | Constraints | Description |
|---|---|---|---|
| `title` | String | Required | Notification title |
| `message` | String | Required | Notification body text |
| `type` | String | Enum: `info`, `warning`, `success`, `danger` | Notification severity/category for visual styling |
| `targetRole` | String | Enum: `admin`, `staff`, `customer`; empty string if targeting a specific user | Role of users who should see this notification |
| `targetUid` | String | FK → `users` (doc ID); empty string if targeting a role | Firebase UID of the specific recipient (single-user notifications) |
| `readBy` | Map | Map of `{uid: true}` | Tracks which users have read the notification; key is Firebase UID, value is `true` |
| `isRead` | Boolean | Default: `false` | Convenience read flag; initially `false` for all; not updated server-side (deprecated in favor of `readBy`) |
| `createdAt` | Timestamp | Server-set | Server timestamp of notification creation |

---

## 11. Collection: `otp_requests`

**Document ID:** User email address
**Purpose:** Stores temporary OTP codes for email verification during Google Sign-In or password-sensitive operations.

| Field Name | Data Type | Constraints | Description |
|---|---|---|---|
| `otp` | String | 6 digits | One-time passcode |
| `expiry` | String | ISO datetime (UTC); valid for 5 minutes | Expiration timestamp of the OTP |
| `email` | String | Matches the document ID | User's email address |
| `createdAt` | Timestamp | Server-set | Server timestamp of OTP creation |

---

## 12. Collection: `domains`

**Structure:** `domains/{domainKey}/items/{auto-id}`
**Purpose:** Admin-managed master lists that populate dropdowns throughout the app. Admins can add, edit, or delete entries without a code change.

**Domain Keys:**

| Domain Key | Purpose | Default Seeded Values |
|---|---|---|
| `commodity_groups` | Commodity group categories for items | Lubricants, Filters, Brakes, Tires, Electrical, Body Parts, Fluids, Labor |
| `uom` | Units of measure | pcs, L, set, job, kg, box, pair, m |
| `vehicle_types` | Vehicle type options | Truck, SUV, Sedan, Van, Motorcycle, Bus, Pickup |

**Each `items` sub-document contains:**

| Field Name | Data Type | Constraints | Description |
|---|---|---|---|
| `name` | String | Required; unique per domain | Display value shown in dropdowns |
| `createdAt` | Timestamp | Server-set | Server timestamp of entry creation |

---

## 13. Collection: `_pmsAlertLog`

**Document ID:** Date string `YYYY-MM-DD`
**Purpose:** Deduplication guard for the DSS (Decision Support System) alert generator. Prevents PMS alert notifications from being sent more than once per calendar day.

| Field Name | Data Type | Constraints | Description |
|---|---|---|---|
| `generatedAt` | Timestamp | Server-set | Server timestamp written immediately when alerts are generated for that day |

---

## 14. Collection: `archive`

**Structure:** Subcollections under fixed document IDs
**Purpose:** Soft-deleted records preserved for historical reference.

| Path | Contents |
|---|---|
| `archive/vehicles/vehicles/{docId}` | Archived vehicle documents (same fields as `vehicles` collection) |
| `archive/users/users/{uid}` | Archived user documents (same fields as `users` collection) |
| `archive/item_master/items/{docId}` | Archived item documents (same fields as `item_master` collection) |

All archived documents carry the same fields as their source collection plus:

| Field Name | Data Type | Description |
|---|---|---|
| `archived` | Boolean | Always `true` |
| `archivedAt` | Timestamp | Server timestamp when the record was archived |

---

## Foreign Key Relationships

| Source Collection | Field | Target | Relationship |
|---|---|---|---|
| `vehicles` | `ownerId` | `users` (doc ID) | Many-to-one |
| `maintenance` | `vehicleId` | `vehicles` (doc ID) | Many-to-one |
| `maintenance` | `ownerId` | `users` (doc ID) | Many-to-one |
| `maintenance` | `plate` / `plateNumber` | `vehicles.plate` / `plateNumber` | Legacy join by plate value |
| `maintenance` | `bookingId` | `service_bookings` (doc ID) | Optional one-to-one |
| `service_bookings` | `customerId` | `users` (doc ID) | Many-to-one |
| `service_bookings` | `vehicleId` | `vehicles` (doc ID) | Many-to-one |
| `issuances` | `maintenanceId` | `maintenance.id` (human-readable ID) | Many-to-one |
| `issuances` | `plate` / `plateNumber` | `vehicles.plate` / `plateNumber` | Join by plate value |
| `issuances` | `itemNum` | `item_master.num` | Many-to-one |
| `stock_inventory` | `num` | `item_master.num` | One-to-one |
| `transactions` | `item` | `item_master.name` | Informal join by name |
| `deliveries.items[].itemNum` | | `item_master.num` | Many-to-one (embedded) |

---

## Design Notes

1. **Dual-field pattern on `vehicles` and `maintenance`:** Both collections write field values under a canonical long name (e.g., `plateNumber`, `description`, `lastServiceDate`) AND a legacy short name (e.g., `plate`, `desc`, `lastSvcDate`). All queries and lookups must check both fields.

2. **`service_bookings` status lifecycle:** `Pending` → `Approved` → `Under Maintenance` → `Completed`. Bookings with an `Approved` status whose `preferredDate` has passed without service being started are auto-cancelled by the system with `cancelledBy = "system"`.

3. **Notifications targeting:** A document in `notifications` targets either all users of a `targetRole` (e.g., all admins) or a single `targetUid`. The `readBy` map tracks per-user read status (`readBy.{uid} = true`). Both must be queried and merged in the client.

4. **`stock_inventory` and `item_master` sync:** When an `item_master` record is updated, synced fields (`num`, `supplierCode`, `name`, `group`, `uom`) are propagated to matching `stock_inventory` documents. When an item is archived, its `stock_inventory` document is deleted.

5. **Auto-issuance on maintenance completion:** When a maintenance job is marked `Completed`, the app automatically creates `issuances` records for every entry in `matRows` and `svcRows`, decrements `stock_inventory.stock` for material items, and appends `transactions` OUT records.

6. **`_pmsAlertLog` race-condition prevention:** The dedup marker document is written to Firestore immediately before any alerts are generated. If the write fails, the process aborts to avoid duplicate alerts.
