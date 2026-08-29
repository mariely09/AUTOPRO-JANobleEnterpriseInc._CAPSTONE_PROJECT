# SQL Command Table Reference — Automotive Service

> **Note:** The actual database is **Google Cloud Firestore** (NoSQL). The SQL statements below are **logical equivalents** written for documentation, reporting, and reference purposes — useful when migrating to a relational database, generating reports via SQL-based tools, or understanding the data structure in familiar terms.
>
> **SQL Dialect:** Standard SQL (compatible with PostgreSQL / MySQL)
> **Source:** Based on `dataDictionary.md` — Caltex AutoPro Automotive Service Management System

---

## Table of Contents

1. [users](#1-users)
2. [user_alert_settings](#2-user_alert_settings)
3. [vehicles](#3-vehicles)
4. [maintenance](#4-maintenance)
5. [maintenance_service_rows](#5-maintenance_service_rows)
6. [maintenance_material_rows](#6-maintenance_material_rows)
7. [service_bookings](#7-service_bookings)
8. [stock_inventory](#8-stock_inventory)
9. [item_master](#9-item_master)
10. [issuances](#10-issuances)
11. [deliveries](#11-deliveries)
12. [delivery_items](#12-delivery_items)
13. [transactions](#13-transactions)
14. [notifications](#14-notifications)
15. [otp_requests](#15-otp_requests)
16. [domains](#16-domains)
17. [pms_alert_log](#17-pms_alert_log)
18. [archive_vehicles](#18-archive_vehicles)
19. [archive_users](#19-archive_users)
20. [archive_item_master](#20-archive_item_master)
21. [Common Queries](#21-common-queries)
22. [Recommended Indexes](#22-recommended-indexes)

---

## 1. `users`

Stores all registered user accounts — admins, staff, and customers.

```sql
CREATE TABLE users (
    id                  VARCHAR(128)    PRIMARY KEY,        -- Firebase Auth UID (document ID)
    uid                 VARCHAR(128)    NOT NULL UNIQUE,    -- Mirrors the document ID
    first_name          VARCHAR(100)    NOT NULL,
    last_name           VARCHAR(100)    NOT NULL,
    name                VARCHAR(200)    NOT NULL,           -- Full name: first_name + ' ' + last_name
    email               VARCHAR(255)    NOT NULL UNIQUE,
    role                VARCHAR(20)     NOT NULL            -- CHECK (role IN ('admin', 'staff', 'customer'))
                            CHECK (role IN ('admin', 'staff', 'customer')),
    status              VARCHAR(20)     NOT NULL DEFAULT 'Active'
                            CHECK (status IN ('Active', 'Inactive', 'Pending')),
    phone_number        VARCHAR(20),                        -- Format: +63XXXXXXXXXX
    company_name        VARCHAR(200),                       -- Customers only
    photo_url           TEXT,                               -- Base64 data URI: data:image/jpeg;base64,...
    must_change_password BOOLEAN        NOT NULL DEFAULT FALSE,
    one_signal_id       VARCHAR(255),                       -- Push notification subscription ID
    created_at          TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

**INSERT**
```sql
INSERT INTO users (
    id, uid, first_name, last_name, name, email, role, status,
    phone_number, company_name, photo_url, must_change_password,
    one_signal_id, created_at
)
VALUES (
    'UID123', 'UID123', 'Juan', 'Dela Cruz', 'Juan Dela Cruz',
    'juan@example.com', 'customer', 'Active',
    '+639171234567', 'Dela Cruz Logistics', NULL, FALSE,
    NULL, CURRENT_TIMESTAMP
);
```

**SELECT — Get all active customers**
```sql
SELECT id, name, email, phone_number, company_name
FROM users
WHERE role = 'customer'
  AND status = 'Active'
ORDER BY name;
```

**SELECT — Get all staff and admins**
```sql
SELECT id, name, email, role, status
FROM users
WHERE role IN ('admin', 'staff')
ORDER BY role, name;
```

**UPDATE — Deactivate a user**
```sql
UPDATE users
SET status = 'Inactive'
WHERE id = 'UID123';
```

**UPDATE — Assign a new role**
```sql
UPDATE users
SET role = 'staff'
WHERE id = 'UID123';
```

**DELETE — Remove a user**
```sql
DELETE FROM users
WHERE id = 'UID123';
```

---

## 2. `user_alert_settings`

Per-user notification and alert preferences. Maps to the Firestore subcollection `users/{uid}/settings/alerts`.

```sql
CREATE TABLE user_alert_settings (
    user_id                 VARCHAR(128)    PRIMARY KEY
                                REFERENCES users(id) ON DELETE CASCADE,
    in_app_enabled          BOOLEAN         NOT NULL DEFAULT TRUE,
    email_enabled           BOOLEAN         NOT NULL DEFAULT TRUE,
    -- Vehicle alerts (all roles)
    pms_overdue             BOOLEAN         NOT NULL DEFAULT TRUE,
    pms_due_today           BOOLEAN         NOT NULL DEFAULT TRUE,
    pms_due_this_week       BOOLEAN         NOT NULL DEFAULT TRUE,
    pms_due_soon            BOOLEAN         NOT NULL DEFAULT TRUE,
    -- Service alerts (staff & admin only)
    service_update          BOOLEAN         NOT NULL DEFAULT TRUE,
    new_assignment          BOOLEAN         NOT NULL DEFAULT TRUE,
    -- Inventory alerts (admin only)
    low_stock               BOOLEAN         NOT NULL DEFAULT TRUE,
    -- Booking alerts (customer only)
    booking_reminder        BOOLEAN         NOT NULL DEFAULT TRUE,
    vehicle_under_maint     BOOLEAN         NOT NULL DEFAULT TRUE,
    -- Booking alerts (staff & admin only)
    new_booking_request     BOOLEAN         NOT NULL DEFAULT TRUE,
    booking_cancellation    BOOLEAN         NOT NULL DEFAULT TRUE,
    updated_at              TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

**INSERT — Create default alert settings for a new user**
```sql
INSERT INTO user_alert_settings (user_id)
VALUES ('UID123');
```

**SELECT — Get alert settings for a user**
```sql
SELECT *
FROM user_alert_settings
WHERE user_id = 'UID123';
```

**UPDATE — Disable email notifications**
```sql
UPDATE user_alert_settings
SET email_enabled = FALSE,
    updated_at = CURRENT_TIMESTAMP
WHERE user_id = 'UID123';
```

**SELECT — Find all admin users with low stock alerts enabled**
```sql
SELECT u.id, u.name, u.email
FROM users u
JOIN user_alert_settings uas ON u.id = uas.user_id
WHERE u.role = 'admin'
  AND uas.low_stock = TRUE;
```

---

## 3. `vehicles`

Registry of all fleet and customer vehicles.

```sql
CREATE TABLE vehicles (
    id                      VARCHAR(128)    PRIMARY KEY,        -- Firestore auto-generated doc ID
    plate_number            VARCHAR(20)     NOT NULL UNIQUE,    -- Canonical; uppercase
    plate                   VARCHAR(20),                        -- Legacy alias for plate_number
    description             VARCHAR(300),                       -- Canonical: make/model/year
    desc                    VARCHAR(300),                       -- Legacy alias for description
    asset_description       VARCHAR(300),                       -- Older import alias
    type                    VARCHAR(50),                        -- FK → domains (vehicle_types)
    owner                   VARCHAR(200)    NOT NULL,           -- Customer full name or company name
    owner_id                VARCHAR(128)    REFERENCES users(id),  -- FK → users (authoritative)
    odometer                NUMERIC(10,2),                      -- Canonical; in km
    odo                     VARCHAR(50),                        -- Legacy: "12345 km"
    last_service_date       DATE,                               -- Canonical; YYYY-MM-DD
    last_svc_date           VARCHAR(20),                        -- Legacy alias
    last_service_odometer   NUMERIC(10,2),                      -- Canonical
    last_svc_odo            VARCHAR(50),                        -- Legacy alias
    service_frequency       INTEGER,                            -- Canonical; months between PMS
    svc_freq                VARCHAR(20),                        -- Legacy alias
    status                  VARCHAR(30)     NOT NULL DEFAULT 'Active'
                                CHECK (status IN ('Active', 'Under Maintenance', 'Overdue', 'PMS Due Soon', 'Completed')),
    next_pms_due            DATE,                               -- Calculated on service completion
    completed_at            TIMESTAMP,
    archived                BOOLEAN         NOT NULL DEFAULT FALSE,
    archived_at             TIMESTAMP,
    created_at              TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

**INSERT**
```sql
INSERT INTO vehicles (
    id, plate_number, plate, description, type, owner, owner_id,
    odometer, service_frequency, status, created_at
)
VALUES (
    'VEH001', 'ABC 1234', 'ABC 1234', 'Toyota Hilux 2022',
    'Truck', 'Juan Dela Cruz', 'UID123',
    12500, 6, 'Active', CURRENT_TIMESTAMP
);
```

**SELECT — All active vehicles for a customer**
```sql
SELECT v.plate_number, v.description, v.type, v.status,
       v.odometer, v.last_service_date, v.next_pms_due
FROM vehicles v
WHERE v.owner_id = 'UID123'
  AND v.archived = FALSE
ORDER BY v.plate_number;
```

**SELECT — Vehicles with overdue or due-soon PMS**
```sql
SELECT plate_number, description, owner, status, next_pms_due
FROM vehicles
WHERE status IN ('Overdue', 'PMS Due Soon')
  AND archived = FALSE
ORDER BY next_pms_due;
```

**SELECT — Vehicles currently under maintenance**
```sql
SELECT v.plate_number, v.description, v.owner, v.status
FROM vehicles v
WHERE v.status = 'Under Maintenance'
  AND v.archived = FALSE;
```

**UPDATE — Mark vehicle as Under Maintenance**
```sql
UPDATE vehicles
SET status = 'Under Maintenance'
WHERE id = 'VEH001';
```

**UPDATE — Complete maintenance and update service dates**
```sql
UPDATE vehicles
SET status = 'Active',
    last_service_date = CURRENT_DATE,
    last_service_odometer = 13000,
    next_pms_due = CURRENT_DATE + INTERVAL '6 months',
    completed_at = CURRENT_TIMESTAMP
WHERE id = 'VEH001';
```

**UPDATE — Soft-delete (archive) a vehicle**
```sql
UPDATE vehicles
SET archived = TRUE,
    archived_at = CURRENT_TIMESTAMP
WHERE id = 'VEH001';
```

---

## 4. `maintenance`

Individual vehicle service and repair job records.

```sql
CREATE TABLE maintenance (
    id              VARCHAR(128)    PRIMARY KEY,    -- Firestore auto-generated doc ID
    job_id          VARCHAR(50)     NOT NULL UNIQUE,-- Human-readable: SVC-YYYYMMDD-HHmmss
    plate_number    VARCHAR(20),                    -- Canonical plate (FK → vehicles.plate_number)
    plate           VARCHAR(20),                    -- Legacy alias
    vehicle_id      VARCHAR(128)    REFERENCES vehicles(id),
    owner_id        VARCHAR(128)    REFERENCES users(id),
    description     VARCHAR(300),                   -- Vehicle description snapshot
    mechanic        VARCHAR(200)    NOT NULL,        -- Assigned mechanic name
    service_date    VARCHAR(30),                    -- Display date: "Jan 5, 2026"
    odometer        NUMERIC(10,2),                  -- Odometer at time of service (km)
    cost            VARCHAR(30),                    -- Formatted: "₱1,234.50"
    status          VARCHAR(20)     NOT NULL DEFAULT 'Ongoing'
                        CHECK (status IN ('Ongoing', 'Completed')),
    booking_id      VARCHAR(128),                   -- FK → service_bookings (optional)
    archived        BOOLEAN         NOT NULL DEFAULT FALSE,
    archived_at     TIMESTAMP,
    created_at      TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

> **Note:** The `issues`, `svcRows`, and `matRows` arrays are normalized into separate tables below (`maintenance_issues`, `maintenance_service_rows`, `maintenance_material_rows`).

**INSERT**
```sql
INSERT INTO maintenance (
    id, job_id, plate_number, vehicle_id, owner_id,
    description, mechanic, service_date, odometer, cost, status, created_at
)
VALUES (
    'MAINT001', 'SVC-20260105-083000', 'ABC 1234', 'VEH001', 'UID123',
    'Toyota Hilux 2022', 'Pedro Santos',
    'Jan 5, 2026', 13000, '₱2,500.00', 'Ongoing', CURRENT_TIMESTAMP
);
```

**SELECT — All jobs for a vehicle**
```sql
SELECT m.job_id, m.service_date, m.mechanic, m.cost, m.status
FROM maintenance m
WHERE m.plate_number = 'ABC 1234'
ORDER BY m.created_at DESC;
```

**SELECT — All completed jobs for a customer (with vehicle info)**
```sql
SELECT m.job_id, v.plate_number, v.description,
       m.service_date, m.mechanic, m.cost
FROM maintenance m
JOIN vehicles v ON m.vehicle_id = v.id
WHERE m.owner_id = 'UID123'
  AND m.status = 'Completed'
ORDER BY m.created_at DESC;
```

**SELECT — All ongoing jobs**
```sql
SELECT m.job_id, m.plate_number, m.description,
       m.mechanic, m.service_date, m.cost
FROM maintenance m
WHERE m.status = 'Ongoing'
  AND m.archived = FALSE
ORDER BY m.created_at DESC;
```

**UPDATE — Mark job as Completed**
```sql
UPDATE maintenance
SET status = 'Completed'
WHERE id = 'MAINT001';
```

---

## 5. `maintenance_service_rows`

Normalized table for the `svcRows` embedded array in `maintenance`. Each row is one service performed.

```sql
CREATE TABLE maintenance_service_rows (
    id              SERIAL          PRIMARY KEY,
    maintenance_id  VARCHAR(128)    NOT NULL REFERENCES maintenance(id) ON DELETE CASCADE,
    item_name       VARCHAR(200)    NOT NULL,           -- FK → item_master.name
    qty             VARCHAR(20),
    uom             VARCHAR(30),
    cost            VARCHAR(30)                         -- Unit cost as numeric string
);
```

**INSERT**
```sql
INSERT INTO maintenance_service_rows (maintenance_id, item_name, qty, uom, cost)
VALUES ('MAINT001', 'Oil Change', '1', 'job', '500.00'),
       ('MAINT001', 'Brake Check', '1', 'job', '300.00');
```

**SELECT — Services for a job**
```sql
SELECT item_name, qty, uom, cost
FROM maintenance_service_rows
WHERE maintenance_id = 'MAINT001';
```

---

## 6. `maintenance_material_rows`

Normalized table for the `matRows` embedded array in `maintenance`. Each row is one material used.

```sql
CREATE TABLE maintenance_material_rows (
    id              SERIAL          PRIMARY KEY,
    maintenance_id  VARCHAR(128)    NOT NULL REFERENCES maintenance(id) ON DELETE CASCADE,
    item_name       VARCHAR(200)    NOT NULL,           -- FK → item_master.name
    qty             VARCHAR(20),
    uom             VARCHAR(30),
    cost            VARCHAR(30)                         -- Unit cost as numeric string
);
```

**INSERT**
```sql
INSERT INTO maintenance_material_rows (maintenance_id, item_name, qty, uom, cost)
VALUES ('MAINT001', 'Engine Oil 10W40', '4', 'L', '250.00'),
       ('MAINT001', 'Oil Filter', '1', 'pcs', '120.00');
```

**SELECT — Materials used in a job**
```sql
SELECT item_name, qty, uom, cost,
       (CAST(qty AS NUMERIC) * CAST(cost AS NUMERIC)) AS subtotal
FROM maintenance_material_rows
WHERE maintenance_id = 'MAINT001';
```

---

## 7. `service_bookings`

Customer-submitted service appointment requests and their lifecycle states.

```sql
CREATE TABLE service_bookings (
    id                  VARCHAR(128)    PRIMARY KEY,    -- Firestore auto-generated doc ID
    customer_id         VARCHAR(128)    NOT NULL REFERENCES users(id),
    customer_name       VARCHAR(200)    NOT NULL,       -- Name snapshot at booking time
    vehicle_id          VARCHAR(128)    REFERENCES vehicles(id),
    plate               VARCHAR(20),                    -- Plate snapshot
    vehicle_desc        VARCHAR(300),                   -- Description snapshot
    services            TEXT,                           -- Comma-separated service names (or use booking_services table)
    preferred_date      DATE            NOT NULL,
    preferred_time      VARCHAR(20),                    -- e.g., "8:00 AM"
    notes               TEXT,
    status              VARCHAR(30)     NOT NULL DEFAULT 'Approved'
                            CHECK (status IN ('Pending', 'Approved', 'Under Maintenance', 'Completed', 'Cancelled')),
    auto_approved       BOOLEAN         NOT NULL DEFAULT FALSE,
    used_ai_suggestion  BOOLEAN         NOT NULL DEFAULT FALSE,
    previous_date       DATE,                           -- Set on reschedule
    previous_time       VARCHAR(20),
    rescheduled_by      VARCHAR(50),                    -- e.g., 'admin'
    rescheduled_at      TIMESTAMP,
    cancelled_at        TIMESTAMP,
    cancelled_by        VARCHAR(50),                    -- 'admin', 'system', 'customer'
    cancellation_reason TEXT,
    created_at          TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

**INSERT**
```sql
INSERT INTO service_bookings (
    id, customer_id, customer_name, vehicle_id, plate, vehicle_desc,
    services, preferred_date, preferred_time, notes, status,
    auto_approved, used_ai_suggestion, created_at
)
VALUES (
    'BOOK001', 'UID123', 'Juan Dela Cruz', 'VEH001', 'ABC 1234',
    'Toyota Hilux 2022', 'Oil Change, Brake Check',
    '2026-08-30', '8:00 AM', 'Please check tire pressure too.',
    'Approved', TRUE, FALSE, CURRENT_TIMESTAMP
);
```

**SELECT — All pending and approved bookings**
```sql
SELECT b.id, b.customer_name, b.plate, b.vehicle_desc,
       b.preferred_date, b.preferred_time, b.services, b.status
FROM service_bookings b
WHERE b.status IN ('Pending', 'Approved')
ORDER BY b.preferred_date, b.preferred_time;
```

**SELECT — Booking history for a customer**
```sql
SELECT b.id, b.plate, b.vehicle_desc, b.services,
       b.preferred_date, b.preferred_time, b.status
FROM service_bookings b
WHERE b.customer_id = 'UID123'
ORDER BY b.created_at DESC;
```

**SELECT — Count bookings by status**
```sql
SELECT status, COUNT(*) AS total
FROM service_bookings
GROUP BY status
ORDER BY total DESC;
```

**SELECT — Bookings on a specific date**
```sql
SELECT customer_name, plate, vehicle_desc, preferred_time, services, status
FROM service_bookings
WHERE preferred_date = '2026-08-30'
  AND status NOT IN ('Cancelled')
ORDER BY preferred_time;
```

**UPDATE — Start service (set to Under Maintenance)**
```sql
UPDATE service_bookings
SET status = 'Under Maintenance'
WHERE id = 'BOOK001';
```

**UPDATE — Complete a booking**
```sql
UPDATE service_bookings
SET status = 'Completed'
WHERE id = 'BOOK001';
```

**UPDATE — Cancel a booking**
```sql
UPDATE service_bookings
SET status = 'Cancelled',
    cancelled_at = CURRENT_TIMESTAMP,
    cancelled_by = 'admin',
    cancellation_reason = 'No-show'
WHERE id = 'BOOK001';
```

**UPDATE — Reschedule a booking**
```sql
UPDATE service_bookings
SET previous_date = preferred_date,
    previous_time = preferred_time,
    preferred_date = '2026-09-05',
    preferred_time = '10:00 AM',
    rescheduled_by = 'admin',
    rescheduled_at = CURRENT_TIMESTAMP
WHERE id = 'BOOK001';
```

---

## 8. `stock_inventory`

Current on-hand quantity for each material item.

```sql
CREATE TABLE stock_inventory (
    id              VARCHAR(128)    PRIMARY KEY,    -- Firestore auto-generated doc ID
    num             VARCHAR(20)     NOT NULL UNIQUE,-- FK → item_master.num; one-to-one
    supplier_code   VARCHAR(100),                   -- Synced from item_master
    name            VARCHAR(200)    NOT NULL,        -- Synced from item_master
    item_group      VARCHAR(100),                   -- Commodity group; synced from item_master
    uom             VARCHAR(30),                    -- Unit of measure
    stock           INTEGER         NOT NULL DEFAULT 0 CHECK (stock >= 0),
    min_level       INTEGER         NOT NULL DEFAULT 0,
    max_level       INTEGER         NOT NULL DEFAULT 0,
    reorder_qty     INTEGER         NOT NULL DEFAULT 0,
    status          VARCHAR(10)     NOT NULL DEFAULT 'OK'
                        CHECK (status IN ('OK', 'Low', 'Over')),
    created_at      TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

**INSERT**
```sql
INSERT INTO stock_inventory (
    id, num, supplier_code, name, item_group, uom,
    stock, min_level, max_level, reorder_qty, status, created_at, updated_at
)
VALUES (
    'STOCK001', '001', 'SUP-OIL-10W40', 'Engine Oil 10W40',
    'Lubricants', 'L', 50, 10, 100, 50, 'OK',
    CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
);
```

**SELECT — All items with current stock levels**
```sql
SELECT num, name, item_group, stock, min_level, max_level, uom, status
FROM stock_inventory
ORDER BY item_group, name;
```

**SELECT — Low stock items**
```sql
SELECT num, name, item_group, stock, min_level, reorder_qty, uom
FROM stock_inventory
WHERE status = 'Low'
   OR (min_level > 0 AND stock <= min_level)
ORDER BY stock ASC;
```

**SELECT — Stock summary by commodity group**
```sql
SELECT item_group,
       COUNT(*) AS item_count,
       SUM(stock) AS total_stock,
       SUM(CASE WHEN status = 'Low' THEN 1 ELSE 0 END) AS low_count
FROM stock_inventory
GROUP BY item_group
ORDER BY item_group;
```

**UPDATE — Decrease stock (issuance / OUT)**
```sql
UPDATE stock_inventory
SET stock = stock - 3,
    updated_at = CURRENT_TIMESTAMP,
    status = CASE
        WHEN (stock - 3) <= min_level THEN 'Low'
        WHEN (stock - 3) > max_level  THEN 'Over'
        ELSE 'OK'
    END
WHERE num = '001';
```

**UPDATE — Increase stock (receiving / IN)**
```sql
UPDATE stock_inventory
SET stock = stock + 20,
    updated_at = CURRENT_TIMESTAMP,
    status = CASE
        WHEN (stock + 20) <= min_level THEN 'Low'
        WHEN (stock + 20) > max_level  THEN 'Over'
        ELSE 'OK'
    END
WHERE num = '001';
```

---

## 9. `item_master`

Master catalog of all materials and services.

```sql
CREATE TABLE item_master (
    id              VARCHAR(128)    PRIMARY KEY,    -- Firestore auto-generated doc ID
    num             VARCHAR(20)     NOT NULL UNIQUE,-- Auto-incremented, zero-padded (e.g., "001")
    supplier_code   VARCHAR(100),
    oem             VARCHAR(100),                   -- OEM part number
    sku             VARCHAR(100),                   -- Internal SKU
    name            VARCHAR(200)    NOT NULL,
    description     TEXT,
    item_group      VARCHAR(100),                   -- FK → domains (commodity_groups)
    uom             VARCHAR(30),                    -- FK → domains (uom)
    cost            VARCHAR(30),                    -- Formatted: "₱123.45"
    item_type       VARCHAR(20)     NOT NULL
                        CHECK (item_type IN ('Material', 'Service')),
    barcode         VARCHAR(50),                    -- EAN-13; auto-generated for Material type
    qr              VARCHAR(100),                   -- Format: QR-{supplierCode}
    archived        BOOLEAN         NOT NULL DEFAULT FALSE,
    archived_at     TIMESTAMP,
    created_at      TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

**INSERT**
```sql
INSERT INTO item_master (
    id, num, supplier_code, name, item_group, uom, cost, item_type, barcode, qr, created_at
)
VALUES (
    'ITEM001', '001', 'SUP-OIL-10W40', 'Engine Oil 10W40',
    'Lubricants', 'L', '₱250.00', 'Material',
    '1234567890123', 'QR-SUP-OIL-10W40', CURRENT_TIMESTAMP
);
```

**SELECT — All active items in catalog**
```sql
SELECT num, name, item_group, uom, cost, item_type
FROM item_master
WHERE archived = FALSE
ORDER BY item_type, item_group, name;
```

**SELECT — All Material items**
```sql
SELECT num, name, item_group, uom, cost, supplier_code, barcode
FROM item_master
WHERE item_type = 'Material'
  AND archived = FALSE
ORDER BY item_group, name;
```

**SELECT — All Service items**
```sql
SELECT num, name, item_group, uom, cost
FROM item_master
WHERE item_type = 'Service'
  AND archived = FALSE
ORDER BY name;
```

**SELECT — Find an item by barcode**
```sql
SELECT num, name, item_group, uom, cost, item_type
FROM item_master
WHERE barcode = '1234567890123'
  AND archived = FALSE;
```

**UPDATE — Update item cost**
```sql
UPDATE item_master
SET cost = '₱280.00'
WHERE num = '001';
```

**UPDATE — Archive an item**
```sql
UPDATE item_master
SET archived = TRUE,
    archived_at = CURRENT_TIMESTAMP
WHERE id = 'ITEM001';
```

---

## 10. `issuances`

Audit trail of materials/services issued per maintenance job. Auto-created on maintenance completion.

```sql
CREATE TABLE issuances (
    id              VARCHAR(128)    PRIMARY KEY,    -- Firestore auto-generated doc ID
    issuance_id     VARCHAR(60)     NOT NULL UNIQUE,-- ISS-AUTO-{timestamp} or ISS-AUTO-{timestamp}-S
    maintenance_id  VARCHAR(50)     NOT NULL,       -- FK → maintenance.job_id (human-readable SVC-...)
    plate           VARCHAR(20),                    -- Vehicle plate
    plate_number    VARCHAR(20),                    -- Canonical alias for plate
    asset_desc      VARCHAR(300),                   -- Vehicle description snapshot
    item_num        VARCHAR(20),                    -- FK → item_master.num
    item_name       VARCHAR(200)    NOT NULL,
    item_type       VARCHAR(20)     NOT NULL
                        CHECK (item_type IN ('Material', 'Service')),
    commodity_group VARCHAR(100),
    uom             VARCHAR(30),
    qty             VARCHAR(20),                    -- Quantity as string
    unit_cost       VARCHAR(30),                    -- Unit cost as numeric string
    subtotal        VARCHAR(30),                    -- qty × unit_cost
    created_by      VARCHAR(200),                   -- Admin/staff name
    issue_date      VARCHAR(30),                    -- Display date: "Jan 5, 2026"
    created_at      TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

**INSERT**
```sql
INSERT INTO issuances (
    id, issuance_id, maintenance_id, plate, plate_number, asset_desc,
    item_num, item_name, item_type, commodity_group, uom,
    qty, unit_cost, subtotal, created_by, issue_date, created_at
)
VALUES (
    'ISS001', 'ISS-AUTO-1750000000000', 'SVC-20260105-083000',
    'ABC 1234', 'ABC 1234', 'Toyota Hilux 2022',
    '001', 'Engine Oil 10W40', 'Material', 'Lubricants', 'L',
    '4', '250.00', '1000.00', 'Admin User',
    'Jan 5, 2026', CURRENT_TIMESTAMP
);
```

**SELECT — All issuances for a maintenance job**
```sql
SELECT item_name, item_type, qty, uom, unit_cost, subtotal
FROM issuances
WHERE maintenance_id = 'SVC-20260105-083000'
ORDER BY item_type, item_name;
```

**SELECT — All issuances for a vehicle**
```sql
SELECT i.issuance_id, i.maintenance_id, i.item_name, i.item_type,
       i.qty, i.uom, i.subtotal, i.issue_date
FROM issuances i
WHERE i.plate_number = 'ABC 1234'
ORDER BY i.created_at DESC;
```

**SELECT — Total material cost per job**
```sql
SELECT maintenance_id,
       SUM(CAST(subtotal AS NUMERIC)) AS total_cost
FROM issuances
WHERE item_type = 'Material'
GROUP BY maintenance_id
ORDER BY total_cost DESC;
```

**SELECT — Most used materials (top 10)**
```sql
SELECT item_name, item_group AS commodity_group,
       COUNT(*) AS times_issued,
       SUM(CAST(qty AS NUMERIC)) AS total_qty_issued
FROM issuances
WHERE item_type = 'Material'
GROUP BY item_name, item_group
ORDER BY total_qty_issued DESC
LIMIT 10;
```

---

## 11. `deliveries`

Supplier purchase orders and delivery records.

```sql
CREATE TABLE deliveries (
    id              VARCHAR(128)    PRIMARY KEY,    -- Firestore auto-generated doc ID
    supplier        VARCHAR(200)    NOT NULL,
    delivery_date   VARCHAR(30),                    -- ISO or display format date string
    status          VARCHAR(30)     NOT NULL DEFAULT 'Pending'
                        CHECK (status IN ('Pending', 'For Admin Review', 'Awaiting Double Check', 'Approved', 'Rejected')),
    received_by     VARCHAR(200),
    checked_by      VARCHAR(200),
    notes           TEXT,
    review_notes    TEXT,
    received_at     TIMESTAMP,
    reviewed_at     TIMESTAMP,
    created_at      TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

**INSERT**
```sql
INSERT INTO deliveries (
    id, supplier, delivery_date, status, received_by, notes, created_at
)
VALUES (
    'DEL001', 'AutoParts Corp', '2026-08-30',
    'Pending', NULL, 'Monthly lubricants delivery', CURRENT_TIMESTAMP
);
```

**SELECT — All deliveries with status filter**
```sql
SELECT id, supplier, delivery_date, status, received_by, notes
FROM deliveries
ORDER BY created_at DESC;
```

**SELECT — Pending deliveries**
```sql
SELECT id, supplier, delivery_date, notes
FROM deliveries
WHERE status = 'Pending'
ORDER BY delivery_date;
```

**SELECT — Count deliveries by status**
```sql
SELECT status, COUNT(*) AS total
FROM deliveries
GROUP BY status
ORDER BY total DESC;
```

**UPDATE — Mark delivery as received**
```sql
UPDATE deliveries
SET status = 'For Admin Review',
    received_by = 'Staff Member',
    received_at = CURRENT_TIMESTAMP
WHERE id = 'DEL001';
```

**UPDATE — Admin approves delivery**
```sql
UPDATE deliveries
SET status = 'Approved',
    checked_by = 'Admin User',
    reviewed_at = CURRENT_TIMESTAMP
WHERE id = 'DEL001';
```

---

## 12. `delivery_items`

Normalized table for the `items` embedded array in `deliveries`. Each row is one line item in a delivery.

```sql
CREATE TABLE delivery_items (
    id                  SERIAL          PRIMARY KEY,
    delivery_id         VARCHAR(128)    NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
    item_num            VARCHAR(20),                    -- FK → item_master.num
    item_name           VARCHAR(200)    NOT NULL,
    uom                 VARCHAR(30),
    supplier_code       VARCHAR(100),
    expected_qty        NUMERIC(10,2)   NOT NULL DEFAULT 0,
    actual_qty          NUMERIC(10,2),                  -- Set during receiving step
    condition           VARCHAR(20)
                            CHECK (condition IN ('OK', 'Defective', 'Shortage')),
    remark              TEXT,
    item_status         VARCHAR(30),                    -- Per-item status; mirrors delivery status enum
    received_by         VARCHAR(200),
    received_at         VARCHAR(50),                    -- ISO datetime string
    checked_by          VARCHAR(200),
    review_notes        TEXT,
    reviewed_at         VARCHAR(50),                    -- ISO datetime string
    stock_at_receive    INTEGER                         -- Stock level frozen at receive time
);
```

**INSERT**
```sql
INSERT INTO delivery_items (
    delivery_id, item_num, item_name, uom, supplier_code,
    expected_qty, actual_qty, condition, item_status
)
VALUES
    ('DEL001', '001', 'Engine Oil 10W40', 'L', 'SUP-OIL-10W40', 20, NULL, NULL, 'Pending'),
    ('DEL001', '002', 'Oil Filter', 'pcs', 'SUP-FILTER-01', 10, NULL, NULL, 'Pending');
```

**SELECT — Items for a delivery**
```sql
SELECT item_name, uom, expected_qty, actual_qty, condition,
       item_status, received_by, received_at
FROM delivery_items
WHERE delivery_id = 'DEL001'
ORDER BY item_name;
```

**SELECT — All defective items across deliveries**
```sql
SELECT d.supplier, d.delivery_date, di.item_name, di.expected_qty,
       di.actual_qty, di.remark
FROM delivery_items di
JOIN deliveries d ON di.delivery_id = d.id
WHERE di.condition = 'Defective'
ORDER BY d.delivery_date DESC;
```

**UPDATE — Record actual received quantity**
```sql
UPDATE delivery_items
SET actual_qty = 18,
    condition = 'Shortage',
    received_by = 'Staff Member',
    received_at = CURRENT_TIMESTAMP::TEXT,
    item_status = 'For Admin Review'
WHERE delivery_id = 'DEL001'
  AND item_num = '001';
```

---

## 13. `transactions`

Immutable inventory movement log (stock IN/OUT).

```sql
CREATE TABLE transactions (
    id              VARCHAR(128)    PRIMARY KEY,    -- Firestore auto-generated doc ID
    item            VARCHAR(200)    NOT NULL,        -- FK → item_master.name (by name)
    description     TEXT,                           -- e.g., "Issued for maintenance SVC-... — ABC 1234"
    txn_type        VARCHAR(5)      NOT NULL
                        CHECK (txn_type IN ('IN', 'OUT')),
    qty             VARCHAR(20)     NOT NULL,        -- Signed string: "-3" or "+5"
    txn_date        VARCHAR(30),                    -- Display date: "Jan 5, 2026"
    performed_by    VARCHAR(200),                   -- Staff/admin name
    commodity_group VARCHAR(100),
    asset_desc      VARCHAR(300),                   -- Vehicle description (OUT transactions only)
    plate           VARCHAR(20),                    -- Vehicle plate (OUT transactions only)
    created_at      TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

**INSERT — Stock OUT (issuance)**
```sql
INSERT INTO transactions (
    id, item, description, txn_type, qty, txn_date,
    performed_by, commodity_group, asset_desc, plate, created_at
)
VALUES (
    'TXN001',
    'Engine Oil 10W40',
    'Issued for maintenance SVC-20260105-083000 — ABC 1234',
    'OUT', '-4', 'Jan 5, 2026',
    'Admin User', 'Lubricants', 'Toyota Hilux 2022', 'ABC 1234',
    CURRENT_TIMESTAMP
);
```

**INSERT — Stock IN (receiving)**
```sql
INSERT INTO transactions (
    id, item, description, txn_type, qty, txn_date,
    performed_by, commodity_group, created_at
)
VALUES (
    'TXN002',
    'Engine Oil 10W40',
    'Stock received — delivery',
    'IN', '+20', 'Aug 30, 2026',
    'Staff Member', 'Lubricants',
    CURRENT_TIMESTAMP
);
```

**SELECT — Full transaction log (most recent first)**
```sql
SELECT item, description, txn_type, qty, txn_date, performed_by
FROM transactions
ORDER BY created_at DESC
LIMIT 100;
```

**SELECT — All OUT transactions for a specific vehicle**
```sql
SELECT t.item, t.description, t.qty, t.txn_date, t.performed_by
FROM transactions t
WHERE t.txn_type = 'OUT'
  AND t.plate = 'ABC 1234'
ORDER BY t.created_at DESC;
```

**SELECT — Monthly stock movement summary**
```sql
SELECT item, commodity_group, txn_type, SUM(ABS(CAST(qty AS INTEGER))) AS total_qty
FROM transactions
WHERE txn_date LIKE 'Jan%2026'
GROUP BY item, commodity_group, txn_type
ORDER BY item, txn_type;
```

---

## 14. `notifications`

In-app notifications for all users.

```sql
CREATE TABLE notifications (
    id              VARCHAR(128)    PRIMARY KEY,    -- Firestore auto-generated doc ID
    title           VARCHAR(300)    NOT NULL,
    message         TEXT            NOT NULL,
    notif_type      VARCHAR(20)     NOT NULL
                        CHECK (notif_type IN ('info', 'warning', 'success', 'danger')),
    target_role     VARCHAR(20)
                        CHECK (target_role IN ('admin', 'staff', 'customer', '')),
    target_uid      VARCHAR(128),                   -- FK → users(id); null if targeting a role
    is_read         BOOLEAN         NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

> **Note:** The Firestore `readBy` map (per-user read tracking) normalizes into a separate junction table below.

```sql
-- Junction table: tracks which users have read which notification
CREATE TABLE notification_reads (
    notification_id VARCHAR(128)    NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
    user_id         VARCHAR(128)    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    read_at         TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (notification_id, user_id)
);
```

**INSERT — Role-targeted notification**
```sql
INSERT INTO notifications (id, title, message, notif_type, target_role, created_at)
VALUES (
    'NOTIF001',
    'Low Stock Alert',
    'Engine Oil 10W40 is below minimum stock level.',
    'warning', 'admin', CURRENT_TIMESTAMP
);
```

**INSERT — User-specific notification**
```sql
INSERT INTO notifications (id, title, message, notif_type, target_uid, created_at)
VALUES (
    'NOTIF002',
    'Booking Confirmed',
    'Your service booking for ABC 1234 on Aug 30, 2026 has been approved.',
    'success', 'UID123', CURRENT_TIMESTAMP
);
```

**SELECT — Unread notifications for an admin user**
```sql
SELECT n.id, n.title, n.message, n.notif_type, n.created_at
FROM notifications n
LEFT JOIN notification_reads nr ON n.id = nr.notification_id AND nr.user_id = 'ADMIN001'
WHERE (n.target_role = 'admin' OR n.target_uid = 'ADMIN001')
  AND nr.notification_id IS NULL
ORDER BY n.created_at DESC;
```

**INSERT — Mark notification as read**
```sql
INSERT INTO notification_reads (notification_id, user_id)
VALUES ('NOTIF001', 'ADMIN001')
ON CONFLICT (notification_id, user_id) DO NOTHING;
```

**SELECT — Count unread notifications per user role**
```sql
SELECT n.target_role, COUNT(*) AS unread_count
FROM notifications n
LEFT JOIN notification_reads nr ON n.id = nr.notification_id
WHERE nr.notification_id IS NULL
GROUP BY n.target_role;
```

---

## 15. `otp_requests`

OTP codes for email verification.

```sql
CREATE TABLE otp_requests (
    email       VARCHAR(255)    PRIMARY KEY,        -- Document ID is the email address
    otp         CHAR(6)         NOT NULL,           -- 6-digit code
    expiry      TIMESTAMP       NOT NULL,           -- Valid for 5 minutes from creation
    created_at  TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

**INSERT / UPSERT — Create or replace OTP**
```sql
INSERT INTO otp_requests (email, otp, expiry, created_at)
VALUES ('juan@example.com', '482917', CURRENT_TIMESTAMP + INTERVAL '5 minutes', CURRENT_TIMESTAMP)
ON CONFLICT (email) DO UPDATE
    SET otp = EXCLUDED.otp,
        expiry = EXCLUDED.expiry,
        created_at = EXCLUDED.created_at;
```

**SELECT — Verify OTP (must not be expired)**
```sql
SELECT email
FROM otp_requests
WHERE email = 'juan@example.com'
  AND otp = '482917'
  AND expiry > CURRENT_TIMESTAMP;
```

**DELETE — Remove OTP after successful verification**
```sql
DELETE FROM otp_requests
WHERE email = 'juan@example.com';
```

**DELETE — Purge all expired OTPs**
```sql
DELETE FROM otp_requests
WHERE expiry < CURRENT_TIMESTAMP;
```

---

## 16. `domains`

Admin-managed lookup lists for dropdowns. Maps to Firestore path `domains/{domainKey}/items/{id}`.

```sql
CREATE TABLE domains (
    id              VARCHAR(128)    PRIMARY KEY,    -- Firestore auto-generated doc ID
    domain_key      VARCHAR(50)     NOT NULL,       -- 'commodity_groups', 'uom', 'vehicle_types'
    name            VARCHAR(100)    NOT NULL,
    created_at      TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (domain_key, name)
);
```

**INSERT — Seed default values**
```sql
INSERT INTO domains (id, domain_key, name) VALUES
    ('DM001', 'commodity_groups', 'Lubricants'),
    ('DM002', 'commodity_groups', 'Filters'),
    ('DM003', 'commodity_groups', 'Brakes'),
    ('DM004', 'commodity_groups', 'Tires'),
    ('DM005', 'commodity_groups', 'Electrical'),
    ('DM006', 'commodity_groups', 'Body Parts'),
    ('DM007', 'commodity_groups', 'Fluids'),
    ('DM008', 'commodity_groups', 'Labor'),
    ('DM009', 'uom', 'pcs'),
    ('DM010', 'uom', 'L'),
    ('DM011', 'uom', 'set'),
    ('DM012', 'uom', 'job'),
    ('DM013', 'uom', 'kg'),
    ('DM014', 'uom', 'box'),
    ('DM015', 'uom', 'pair'),
    ('DM016', 'uom', 'm'),
    ('DM017', 'vehicle_types', 'Truck'),
    ('DM018', 'vehicle_types', 'SUV'),
    ('DM019', 'vehicle_types', 'Sedan'),
    ('DM020', 'vehicle_types', 'Van'),
    ('DM021', 'vehicle_types', 'Motorcycle'),
    ('DM022', 'vehicle_types', 'Bus'),
    ('DM023', 'vehicle_types', 'Pickup');
```

**SELECT — Get all values for a specific domain**
```sql
SELECT name
FROM domains
WHERE domain_key = 'commodity_groups'
ORDER BY name;
```

**SELECT — All domain keys and their values**
```sql
SELECT domain_key, name
FROM domains
ORDER BY domain_key, name;
```

**DELETE — Remove a domain entry**
```sql
DELETE FROM domains
WHERE domain_key = 'uom' AND name = 'box';
```

---

## 17. `pms_alert_log`

DSS alert deduplication guard. Prevents PMS alerts from firing more than once per day.

```sql
CREATE TABLE pms_alert_log (
    log_date        DATE            PRIMARY KEY,    -- Document ID is the date: YYYY-MM-DD
    generated_at    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

**INSERT — Mark today's alerts as generated**
```sql
INSERT INTO pms_alert_log (log_date, generated_at)
VALUES (CURRENT_DATE, CURRENT_TIMESTAMP)
ON CONFLICT (log_date) DO NOTHING;
```

**SELECT — Check if alerts already generated today**
```sql
SELECT log_date
FROM pms_alert_log
WHERE log_date = CURRENT_DATE;
```

**DELETE — Purge old alert logs (keep last 30 days)**
```sql
DELETE FROM pms_alert_log
WHERE log_date < CURRENT_DATE - INTERVAL '30 days';
```

---

## 18. `archive_vehicles`

Soft-deleted vehicle records. Maps to `archive/vehicles/vehicles/{docId}`.

```sql
CREATE TABLE archive_vehicles (
    LIKE vehicles INCLUDING ALL,    -- All columns from vehicles table
    archived        BOOLEAN         NOT NULL DEFAULT TRUE,
    archived_at     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

**INSERT — Move vehicle to archive**
```sql
INSERT INTO archive_vehicles
SELECT *, TRUE, CURRENT_TIMESTAMP
FROM vehicles
WHERE id = 'VEH001';

DELETE FROM vehicles WHERE id = 'VEH001';
```

**SELECT — All archived vehicles**
```sql
SELECT id, plate_number, description, owner, status, archived_at
FROM archive_vehicles
ORDER BY archived_at DESC;
```

---

## 19. `archive_users`

Soft-deleted user records. Maps to `archive/users/users/{uid}`.

```sql
CREATE TABLE archive_users (
    LIKE users INCLUDING ALL,
    archived        BOOLEAN         NOT NULL DEFAULT TRUE,
    archived_at     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

**INSERT — Move user to archive**
```sql
INSERT INTO archive_users
SELECT *, TRUE, CURRENT_TIMESTAMP
FROM users
WHERE id = 'UID123';

DELETE FROM users WHERE id = 'UID123';
```

---

## 20. `archive_item_master`

Soft-deleted item records. Maps to `archive/item_master/items/{docId}`.

```sql
CREATE TABLE archive_item_master (
    LIKE item_master INCLUDING ALL,
    archived        BOOLEAN         NOT NULL DEFAULT TRUE,
    archived_at     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

**INSERT — Move item to archive**
```sql
INSERT INTO archive_item_master
SELECT *, TRUE, CURRENT_TIMESTAMP
FROM item_master
WHERE id = 'ITEM001';

DELETE FROM item_master WHERE id = 'ITEM001';
DELETE FROM stock_inventory WHERE num = '001';
```

---

## 21. Common Queries

These are frequently needed cross-table queries for reports and dashboards.

### Full Maintenance Report (with customer and vehicle info)
```sql
SELECT
    m.job_id,
    v.plate_number,
    v.description     AS vehicle,
    u.name             AS customer,
    m.mechanic,
    m.service_date,
    m.cost,
    m.status
FROM maintenance m
LEFT JOIN vehicles v  ON m.vehicle_id = v.id
LEFT JOIN users u     ON m.owner_id = u.id
WHERE m.archived = FALSE
ORDER BY m.created_at DESC;
```

### Service Booking with Customer and Vehicle Details
```sql
SELECT
    b.id             AS booking_id,
    u.name           AS customer,
    u.email,
    v.plate_number,
    v.description    AS vehicle,
    b.services,
    b.preferred_date,
    b.preferred_time,
    b.status
FROM service_bookings b
LEFT JOIN users u    ON b.customer_id = u.id
LEFT JOIN vehicles v ON b.vehicle_id = v.id
ORDER BY b.preferred_date DESC;
```

### Stock vs. Item Master (inventory status)
```sql
SELECT
    im.num,
    im.name,
    im.item_group,
    im.uom,
    im.cost,
    si.stock,
    si.min_level,
    si.max_level,
    si.status
FROM item_master im
LEFT JOIN stock_inventory si ON im.num = si.num
WHERE im.item_type = 'Material'
  AND im.archived = FALSE
ORDER BY im.item_group, im.name;
```

### Issuances joined with Maintenance and Vehicle
```sql
SELECT
    i.issuance_id,
    i.maintenance_id,
    i.plate_number,
    i.item_name,
    i.item_type,
    i.qty,
    i.uom,
    i.subtotal,
    m.mechanic,
    m.service_date
FROM issuances i
JOIN maintenance m ON i.maintenance_id = m.job_id
ORDER BY i.created_at DESC;
```

### Customer Service History Summary
```sql
SELECT
    u.name             AS customer,
    v.plate_number,
    v.description      AS vehicle,
    COUNT(m.id)        AS total_jobs,
    SUM(CAST(REPLACE(REPLACE(m.cost, '₱', ''), ',', '') AS NUMERIC)) AS total_spent
FROM users u
JOIN vehicles v    ON v.owner_id = u.id
JOIN maintenance m ON m.vehicle_id = v.id
WHERE u.role = 'customer'
  AND m.status = 'Completed'
GROUP BY u.name, v.plate_number, v.description
ORDER BY total_spent DESC;
```

### Monthly Bookings Count by Status
```sql
SELECT
    DATE_TRUNC('month', preferred_date) AS month,
    status,
    COUNT(*) AS count
FROM service_bookings
GROUP BY DATE_TRUNC('month', preferred_date), status
ORDER BY month DESC, count DESC;
```

### Top 10 Most Serviced Vehicles
```sql
SELECT
    m.plate_number,
    v.description,
    v.owner,
    COUNT(m.id) AS service_count
FROM maintenance m
LEFT JOIN vehicles v ON m.vehicle_id = v.id
WHERE m.status = 'Completed'
GROUP BY m.plate_number, v.description, v.owner
ORDER BY service_count DESC
LIMIT 10;
```

---

## 22. Recommended Indexes

```sql
-- users
CREATE INDEX idx_users_role   ON users(role);
CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_users_email  ON users(email);

-- vehicles
CREATE INDEX idx_vehicles_owner_id    ON vehicles(owner_id);
CREATE INDEX idx_vehicles_plate       ON vehicles(plate_number);
CREATE INDEX idx_vehicles_status      ON vehicles(status);
CREATE INDEX idx_vehicles_archived    ON vehicles(archived);

-- maintenance
CREATE INDEX idx_maintenance_vehicle_id  ON maintenance(vehicle_id);
CREATE INDEX idx_maintenance_owner_id    ON maintenance(owner_id);
CREATE INDEX idx_maintenance_plate       ON maintenance(plate_number);
CREATE INDEX idx_maintenance_status      ON maintenance(status);
CREATE INDEX idx_maintenance_booking_id  ON maintenance(booking_id);

-- service_bookings
CREATE INDEX idx_bookings_customer_id    ON service_bookings(customer_id);
CREATE INDEX idx_bookings_vehicle_id     ON service_bookings(vehicle_id);
CREATE INDEX idx_bookings_status         ON service_bookings(status);
CREATE INDEX idx_bookings_preferred_date ON service_bookings(preferred_date);

-- stock_inventory
CREATE INDEX idx_stock_num    ON stock_inventory(num);
CREATE INDEX idx_stock_status ON stock_inventory(status);

-- item_master
CREATE INDEX idx_item_master_num      ON item_master(num);
CREATE INDEX idx_item_master_type     ON item_master(item_type);
CREATE INDEX idx_item_master_group    ON item_master(item_group);
CREATE INDEX idx_item_master_barcode  ON item_master(barcode);
CREATE INDEX idx_item_master_archived ON item_master(archived);

-- issuances
CREATE INDEX idx_issuances_maintenance_id ON issuances(maintenance_id);
CREATE INDEX idx_issuances_plate          ON issuances(plate_number);
CREATE INDEX idx_issuances_item_num       ON issuances(item_num);

-- deliveries
CREATE INDEX idx_deliveries_status ON deliveries(status);

-- delivery_items
CREATE INDEX idx_delivery_items_delivery_id ON delivery_items(delivery_id);
CREATE INDEX idx_delivery_items_item_num    ON delivery_items(item_num);

-- transactions
CREATE INDEX idx_transactions_item    ON transactions(item);
CREATE INDEX idx_transactions_type    ON transactions(txn_type);
CREATE INDEX idx_transactions_plate   ON transactions(plate);
CREATE INDEX idx_transactions_created ON transactions(created_at);

-- notifications
CREATE INDEX idx_notifications_target_role ON notifications(target_role);
CREATE INDEX idx_notifications_target_uid  ON notifications(target_uid);
CREATE INDEX idx_notifications_created_at  ON notifications(created_at);

-- notification_reads
CREATE INDEX idx_notif_reads_user ON notification_reads(user_id);

-- domains
CREATE INDEX idx_domains_key ON domains(domain_key);
```
