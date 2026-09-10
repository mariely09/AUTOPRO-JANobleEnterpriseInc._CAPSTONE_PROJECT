# Caltex AutoPro — User Manual

## System Overview

Caltex AutoPro is an automotive service management system developed for **JA Noble Enterprise INC** in partnership with Caltex Philippines. The system provides a comprehensive platform for managing vehicle maintenance, inventory, and fleet operations through both a **web application** and a **mobile application (Android/iOS)**.

The system supports three user roles:
- **Admin** — Full system control (inventory, vehicles, maintenance, users, reports, DSS)
- **Staff** — Day-to-day operations (services, inventory receiving, vehicle management)
- **Customer** — Vehicle monitoring and PMS (Preventive Maintenance Schedule) tracking

---

## Table of Contents

1. [Getting Started](#1-getting-started)
2. [Admin User Guide](#2-admin-user-guide)
   - Managing Inventory
   - Managing Vehicles
   - Managing Maintenance Services
   - Managing Users
   - Decision Support System (DSS)
   - Smart Reports (AI Assistant)
   - Domain Management
   - Service Bookings Management
   - Archive Management
3. [Staff User Guide](#3-staff-user-guide)
4. [Customer User Guide](#4-customer-user-guide)
   - Booking Service Appointments
   - Viewing My Bookings
5. [Mobile App Guide](#5-mobile-app-guide)
6. [Notifications & Alerts](#6-notifications--alerts)
7. [Profile & Account Settings](#7-profile--account-settings)
8. [Troubleshooting & FAQ](#8-troubleshooting--faq)

---

## 1. Getting Started

### 1.1 Accessing the Website

Open your browser and navigate to the Caltex AutoPro web application URL. The system supports modern browsers (Chrome, Firefox, Edge, Safari).

### 1.2 Logging In

1. Enter your **email address** and **password**.
2. Click **Sign In**.
3. Alternatively, click **Sign in with Google** to use your Google account.

The system will redirect you to the appropriate dashboard based on your role (Admin, Staff, or Customer).

### 1.3 Creating an Account (Customer Registration)

1. Click **Sign Up** on the login page.
2. Fill in your **Full Name**, **Email**, and **Password**.
3. Confirm your password.
4. Click **Create Account**.
5. Your account will be created and you can log in immediately.

> **Note:** Admin and Staff accounts are created by the system administrator. You will receive a welcome email with your temporary login credentials.

### 1.4 Forgot Password

1. Click **Forgot Password?** on the login page.
2. Enter your registered email address.
3. A password reset link will be sent to your email.
4. Follow the link to set a new password.

### 1.5 First-Time Login (Admin/Staff)

If your account was created by an administrator, you will be required to change your temporary password on first login. Enter a new password and confirm it to proceed.

---

## 2. Admin User Guide

As an Admin, you have complete control over the Caltex AutoPro system. This section provides step-by-step instructions for all admin tasks.

### 2.1 Getting Started as Admin

**Step 1: First Login**
1. Open your browser and navigate to the Caltex AutoPro website
2. Enter your email and password provided by the system administrator
3. Click **Sign In**
4. If this is your first login, you'll be prompted to change your temporary password
5. Enter a new secure password and confirm it
6. You'll be redirected to the Admin Dashboard

**Step 2: Understanding Your Dashboard**

The Admin Dashboard shows:
- **Stat Cards** at the top showing key metrics (Total Vehicles, Due for PMS, Low Stock, Services Today, Total Users)
- **Interactive PMS Calendar** — A monthly calendar view with color-coded dots showing:
  - 🔴 Red dots = Vehicles overdue for PMS
  - 🟠 Orange dots = Due this week
  - 🟡 Yellow dots = Due within 30 days
  - 🔵 Blue dots = Today's due date
  - Click any date with dots to see which vehicles are due
- **Charts** showing operational insights:
  - Services by Type (pie chart)
  - Vehicle Status Distribution
  - Stock Health Overview
  - Top Consumed Parts
- **Today's Service Schedule** with color-coded status indicators
- **Recent Issuances** showing material and service usage
- **Inventory Transactions** displaying recent stock movements

---

### 2.2 Managing Inventory

#### **Task 1: Adding a New Item to the Item Master**

The Item Master is your catalog of all materials and services.

**Step-by-Step:**
1. Click **Inventory** in the sidebar menu
2. Select **Item Master**
3. Click the **+ Add Item** button (top right)
4. Fill in the form:
   - **Item Number:** Enter a unique identifier (e.g., "OIL-001")
   - **Item Name:** Enter descriptive name (e.g., "Engine Oil 5W-30")
   - **Commodity Group:** Select category (e.g., "Lubricants")
   - **UOM (Unit of Measure):** Select unit (e.g., "Liter", "Piece", "Set")
   - **Cost:** Enter unit cost (e.g., 450.00)
   - **Type:** Select either "Material" or "Service"
5. Optionally enter **Barcode** and **QR Code** (or let system auto-generate)
6. Click **Save**
7. Confirmation message appears: "Item added successfully"

**Tips:**
- Use consistent naming conventions for easy searching
- Material items can be stocked; Service items are non-inventory
- Barcode/QR codes enable quick scanning during service operations

---

#### **Task 2: Adding an Item to Stock Inventory**

After creating an item in Item Master, add it to stock with initial quantities.

**Step-by-Step:**
1. Click **Inventory** → **Stock**
2. Click **+ Add Stock Item**
3. Select the **Item** from dropdown (only Material-type items appear)
4. Enter quantities:
   - **Current Stock:** Initial quantity on hand
   - **Min Level:** Minimum quantity threshold (triggers low stock alert)
   - **Max Level:** Maximum quantity capacity
5. Click **Save**
6. The item now appears in your Stock Inventory list

**Example:**
- Item: Engine Oil 5W-30
- Current Stock: 50 liters
- Min Level: 10 liters
- Max Level: 100 liters

---

#### **Task 3: Receiving Stock (Recording Deliveries)**

When new stock arrives from suppliers, record it to update quantities.

**Step-by-Step:**
1. Go to **Inventory** → **Stock**
2. Find the item you're receiving (use search if needed)
3. Click the **Receive** button next to the item
4. Enter the **Quantity Received** (e.g., 30 liters)
5. Click **Confirm**
6. The system automatically updates:
   - Current stock increases
   - Stock status recalculates (OK/Low/Over)
   - Transaction recorded with timestamp

**Stock Status Indicators:**
- 🟢 **OK** — Stock is between min and max levels
- 🟡 **Low** — Stock is below minimum level (order soon)
- 🔴 **Over** — Stock exceeds maximum level (storage issue)

---

#### **Task 4: Editing or Deleting Items**

**To Edit an Item:**
1. Go to **Inventory** → **Item Master**
2. Find the item in the list
3. Click the **Edit** (pencil icon) button
4. Update the fields you need to change
5. Click **Save**

**To Delete an Item:**
1. Go to **Inventory** → **Item Master**
2. Find the item in the list
3. Click the **Delete** (trash icon) button
4. Confirm deletion in the popup
5. Item is removed from the system

⚠️ **Warning:** Deleting items with service history may affect reports. Consider deactivating instead.

---

### 2.3 Managing Vehicles

#### **Task 5: Registering a New Vehicle**

**Step-by-Step:**
1. Click **Vehicle List** in the sidebar
2. Click **+ Add Vehicle**
3. Fill in the vehicle information:
   - **Plate Number:** Enter in format AAA-1234 (system auto-formats)
   - **Description:** Enter make/model (e.g., "Toyota Hilux 2020")
   - **Vehicle Type:** Select from dropdown (Car, Truck, Van, etc.)
   - **Owner:** Start typing customer name (autocomplete will suggest)
   - **Odometer:** Enter current mileage (e.g., 15000)
   - **Service Frequency:** Enter months between PMS (e.g., 3 for quarterly)
4. Click **Save**
5. Vehicle is now registered and appears in the fleet list

**Important Notes:**
- System prevents duplicate plate numbers
- Owner must be an existing customer (create customer account first if needed)
- Service frequency is used to calculate next PMS due date automatically

---

#### **Task 6: Editing Vehicle Information**

**Step-by-Step:**
1. Go to **Vehicle List**
2. Find the vehicle (use search box if needed)
3. Click the **Edit** button next to the vehicle
4. Update any fields (plate, description, type, owner, odometer, frequency)
5. Click **Save Changes**

**When to Edit:**
- Owner sells vehicle to new customer
- Odometer needs updating after service
- Service frequency needs adjustment
- Vehicle description/type correction

---

#### **Task 7: Viewing Vehicle Details and PMS Status**

**Step-by-Step:**
1. Go to **Vehicle List**
2. Click on any vehicle row or click **View Details**
3. You'll see complete vehicle profile:
   - Basic info (plate, description, type, owner)
   - Current odometer reading
   - Service frequency setting
   - **Last Service Date**
   - **Next PMS Due** (auto-calculated)
   - **Days Until/Overdue**
   - PMS status indicator (Active/Due Soon/Overdue)

**Status Meanings:**
- 🟢 **Active** — Vehicle is current on maintenance
- 🟡 **Due Soon** — PMS due within 7 days
- 🔴 **Overdue** — Vehicle past due date

---

### 2.4 Managing Maintenance Services

#### **Task 8: Creating a New Service Record**

This is the core transaction in the system. Follow carefully.

**Step-by-Step:**
1. Click **Vehicle Maintenance** in the sidebar
2. Click **+ New Service** button
3. **Select Vehicle:**
   - Option A: Type plate number (autocomplete suggests matching vehicles)
   - Option B: Click **Scan** icon and scan vehicle barcode
   - Once selected, vehicle details auto-populate (description, owner, last service)
4. Enter **Mechanic Name** (person performing the service)
5. Select **Service Date** using the date picker
6. **Tag Vehicle Issues:**
   - Click preset issue tags (Battery, Brakes, Engine, Transmission, etc.)
   - Or type custom issues and press Enter
   - Multiple issues can be selected
7. **Add Services Rendered:**
   - Click **+ Add Service**
   - Select service from dropdown (e.g., "Oil Change", "Brake Repair")
   - Enter quantity (usually 1 for services)
   - Service cost auto-fills from Item Master
   - Repeat for multiple services
8. **Add Materials Used:**
   - Click **+ Add Material**
   - Search or scan material barcode
   - Enter quantity used
   - System validates against available stock (shows error if insufficient)
   - Material cost auto-fills
   - Repeat for all materials
9. Review **Total Cost** (auto-calculated at bottom)
10. Click **Save Service**
11. Service is created with status **Pending**

**Important Notes:**
- Service is not approved yet (stays as Pending until you approve it)
- Stock is NOT deducted until service is marked Completed
- You can edit or delete Pending services

---

#### **Task 9: Approving a Service (Changing Status to Ongoing)**

Staff create services that start as Pending. You approve them to begin work.

**Step-by-Step:**
1. Go to **Vehicle Maintenance**
2. Find the Pending service (yellow badge)
3. Click **Edit** button
4. Change **Status** dropdown from "Pending" to "Ongoing"
5. Click **Save Changes**
6. Service status updates to Ongoing (blue badge)
7. Staff can now proceed with the physical work

---

#### **Task 10: Completing a Service**

When service work is finished, mark it complete. This triggers critical system actions.

**Step-by-Step:**
1. Go to **Vehicle Maintenance**
2. Find the Ongoing service
3. Click **Edit** button
4. Change **Status** dropdown to "Completed"
5. Click **Save Changes**
6. System automatically:
   - ✅ Deducts materials from stock
   - ✅ Creates issuance records
   - ✅ Updates vehicle's Last Service Date
   - ✅ Recalculates Next PMS Due
   - ✅ Creates transaction history
   - ✅ Updates stock status indicators
7. Service now shows green "Completed" badge

**Critical:** Stock is only deducted at completion, not during creation or ongoing status.

---

#### **Task 11: Viewing Issuances and Transactions**

**Issuances:**
Issuances are automatic records created when services are completed, showing which materials were used.

**Step-by-Step to View Issuances:**
1. Click **Issuances** in the sidebar (may be under Inventory section)
2. See list of all material issuances with:
   - Service ID linked to the issuance
   - Date issued
   - Items used
   - Quantities
   - Vehicle serviced
3. Use filters to view:
   - By date range
   - By material type
   - By vehicle
   - By service
4. This helps track material consumption patterns

**Transactions:**
Transactions show all inventory movements (receives and issues).

**Step-by-Step to View Transactions:**
1. Click **Transactions** in the sidebar (under Inventory)
2. See complete transaction history:
   - Transaction type (Receive/Issue)
   - Date and time
   - Item name and number
   - Quantity change
   - New stock level after transaction
   - Reference (Service ID for issues, Receive ID for receives)
3. Use search and filters to track specific items
4. Export transaction history for audit purposes

**Use Cases:**
- Monthly inventory reconciliation
- Tracking material usage trends
- Auditing stock movements
- Identifying fast-moving items
- Verifying delivery receipts

---

#### **Task 12: Editing or Deleting Services**

**To Edit a Service:**
1. Go to **Vehicle Maintenance**
2. Click **Edit** on the service (Pending or Ongoing only)
3. Modify any fields (services, materials, issues, mechanic, date)
4. Click **Save Changes**

**To Delete a Service:**
1. Find the service in the list
2. Click **Delete** button
3. Confirm deletion
4. Service is permanently removed

⚠️ **Warning:** You can only edit/delete Pending and Ongoing services. Completed services are locked to maintain audit trail.

---

### 2.5 Managing Users

#### **Task 13: Creating a New User Account**

**Step-by-Step:**
1. Click **User Management** in the sidebar
2. Click **+ Add User**
3. Fill in the form:
   - **Full Name:** Enter user's complete name
   - **Email:** Enter valid email address
   - **Role:** Select Admin, Staff, or Customer
4. Click **Create User**
5. System automatically:
   - Generates temporary password
   - Creates Firebase authentication account
   - Sends welcome email with login credentials
6. New user appears in the user list

**User Roles Explained:**
- **Admin:** Full system access (you)
- **Staff:** Inventory, vehicles, maintenance operations
- **Customer:** View own vehicles and PMS history only

---

#### **Task 14: Approving Pending Customer Registrations**

When customers register themselves, they may need approval.

**Step-by-Step:**
1. Go to **User Management**
2. Look for users with "Pending" status
3. Click **Approve** button next to the user
4. User status changes to "Active"
5. Customer can now log in and access the system

---

#### **Task 15: Activating or Deactivating Users**

**To Deactivate a User:**
1. Go to **User Management**
2. Find the active user
3. Click **Deactivate** button
4. User status changes to "Inactive"
5. User can no longer log in (but data is preserved)

**To Reactivate a User:**
1. Find the inactive user
2. Click **Activate** button
3. User can log in again

**Use Cases:**
- Deactivate staff who leave the company
- Deactivate customers who no longer use your service
- Temporarily suspend access for security reasons

---

#### **Task 16: Editing or Deleting Users**

**To Edit a User:**
1. Go to **User Management**
2. Click **Edit** next to the user
3. Update name, email, or role
4. Click **Save**

**To Delete a User:**
1. Click **Delete** next to the user
2. Confirm deletion
3. User is removed from both database and Firebase Auth

⚠️ **Warning:** Deleting users removes their account permanently. Consider deactivating instead.

---

### 2.6 Using Decision Support System (DSS)

#### **Task 17: Checking Stock Replenishment Recommendations**

The DSS analyzes your inventory and tells you what to order.

**Step-by-Step:**
1. Click **Decision Support System** in the sidebar
2. Click the **Stock Replenishment** tab
3. Review the recommendations table with columns:
   - **Item:** Material name and number
   - **Stock Status:** Current, Min, Max levels
   - **Consumption Rate:** Average daily usage
   - **Days of Stock Left:** Estimated days before stockout
   - **Recommended Order:** Suggested quantity to purchase
   - **Priority:** Critical (red) / High (orange) / Medium (yellow) / Low (green)
   - **Decision:** Specific action to take

4. **Filter Results:**
   - Click **All** to see everything
   - Click **Out of Stock** for immediate attention
   - Click **Low Stock** for items needing orders soon
   - Click **Adequate** for items that are OK

5. **Take Action:**
   - Note items with Critical/High priority
   - Use Recommended Order quantity when purchasing
   - Contact suppliers to order materials
   - Record received stock when delivered (see Task 3)

**Example Reading:**
- Item: Engine Oil 5W-30
- Current Stock: 8 liters
- Min Level: 10 liters
- Consumption Rate: 2 liters/day
- Days Left: 4 days
- Recommended Order: 52 liters
- Priority: High
- Decision: "Order 52 units. Stock will run out in 4 days."

---

#### **Task 18: Checking PMS Scheduling Recommendations**

The DSS shows which vehicles need maintenance attention.

**Step-by-Step:**
1. Go to **Decision Support System**
2. Click the **PMS Scheduling** tab
3. Review the table showing:
   - **Plate Number**
   - **Vehicle Description**
   - **Last Service Date**
   - **Next PMS Due**
   - **Days Until/Overdue**
   - **Priority**
   - **Recommendation**

4. **Filter Results:**
   - **Overdue:** Vehicles past their due date (address immediately)
   - **Due Today:** Vehicles due for service today
   - **Due This Week:** Vehicles due within 7 days
   - **Due Soon:** Vehicles due within 30 days
   - **Active:** All vehicles current on maintenance

5. **Take Action:**
   - Contact vehicle owners for overdue PMS
   - Schedule appointments for vehicles due soon
   - Create service records for vehicles being serviced

**Priority Levels:**
- 🔴 **Critical:** Overdue by more than 7 days
- 🟠 **High:** Overdue or due within 3 days
- 🟡 **Medium:** Due within 7 days
- 🟢 **Low:** Due within 30 days

---

#### **Task 19: Generating Daily DSS Alerts**

You can trigger automated analysis and send notifications.

**Step-by-Step:**
1. Go to **Decision Support System**
2. Click **Generate Daily Alerts** button
3. System analyzes:
   - All stock levels vs. consumption rates
   - All vehicle PMS schedules vs. current date
4. Creates notifications for:
   - Low stock and out-of-stock items
   - Overdue and due-soon vehicles
5. Sends push notifications to:
   - Admins (stock alerts)
   - Customers (their vehicle PMS alerts)
6. Confirmation message appears
7. Alerts are visible in the notification bell icon

**Best Practice:** Run this once daily, preferably in the morning.

---

### 2.7 Using Smart Reports (AI Assistant)

#### **Task 20: Asking Questions and Getting Data-Driven Answers**

The Smart Reports AI (also called RAG AI in the system) can query your live data in natural language.

**Step-by-Step:**
1. Click **Smart Reports** or **RAG AI** in the sidebar
2. You'll see a chat-like interface
3. Type your question in the text box at the bottom
4. Click **Send** or press Enter
5. AI processes your request and responds with data from your database
6. Responses may include:
   - Tables with data
   - Summaries and statistics
   - Lists and counts
   - Specific records matching your query

**Example Questions You Can Ask:**
- "What are the top 5 most consumed items this month?"
- "Show me all vehicles overdue for PMS"
- "How many services were completed last week?"
- "List all low stock items"
- "What is the total maintenance cost for vehicle ABC-123?"
- "Show me services performed by mechanic Juan dela Cruz"
- "Which vehicles belong to customer John Smith?"
- "Give me a summary of stock transactions in March"
- "What services are scheduled for today?"
- "Show me all pending bookings"

**Tips:**
- Be specific in your questions
- Include date ranges when asking about time periods
- Use vehicle plate numbers or owner names for precise results
- Ask follow-up questions to drill down into details
- The AI can search across all database collections (vehicles, services, inventory, bookings, users)

---

#### **Task 21: Exporting Reports**

After getting AI results, export them for external use.

**Step-by-Step:**
1. Ask your question in Smart Reports
2. Review the AI response
3. Look for export options (may vary by implementation):
   - Export as PDF to get a formatted document
   - Export as Excel/CSV to get a spreadsheet
   - Print using browser print function
4. File downloads to your computer
5. Open with appropriate program (PDF reader or Excel)

**Use Cases:**
- Monthly management reports
- Customer invoices
- Inventory audit reports
- Service history for vehicles
- Financial summaries

**Note:** Export functionality may be available depending on the query type and data returned.

---

### 2.8 Domain Management

#### **Task 22: Managing Vehicle Types and Other Settings**

Configure system-wide dropdown options.

**Step-by-Step:**
1. Click **Domain Management** in the sidebar
2. You'll see configurable domains like:
   - Vehicle Types (Car, Truck, Van, SUV, etc.)
   - Commodity Groups (Lubricants, Filters, Parts, etc.)
   - Issue Tags (Battery, Brakes, Engine, etc.)
3. **To Add a New Option:**
   - Click **+ Add** in the relevant section
   - Enter the name (e.g., "Motorcycle")
   - Click **Save**
4. **To Edit an Option:**
   - Click **Edit** next to the item
   - Change the name
   - Click **Save**
5. **To Delete an Option:**
   - Click **Delete**
   - Confirm deletion

**Important:** These options appear in dropdowns throughout the system (vehicle registration, service creation, etc.).

---

### 2.9 Managing Service Bookings

#### **Task 21: Viewing Service Bookings**

Customers can book service appointments online. As admin, you review and manage these bookings.

**Step-by-Step:**
1. Click **Service Bookings** in the sidebar
2. You'll see the bookings dashboard with stat cards:
   - **Total Bookings** — All bookings in the system
   - **Approved** — Confirmed bookings
   - **Rescheduled** — Changed appointments
   - **Cancelled** — Cancelled bookings
3. Use filter pills to view by status:
   - All
   - Approved
   - Rescheduled
   - Cancelled
4. Use search bar to find specific bookings (by plate, customer name)
5. Use sort dropdown to order by:
   - Date (Newest/Oldest)
   - Plate Number (A→Z / Z→A)
   - Customer Name (A→Z / Z→A)

---

#### **Task 22: Approving or Managing Bookings**

**Step-by-Step:**
1. Go to **Service Bookings**
2. Find the booking you want to manage
3. Each booking card shows:
   - Booking date and time
   - Customer name
   - Vehicle (plate and description)
   - Services requested
   - Status badge
   - Customer notes
4. Click on a booking to view full details
5. **To Approve a Booking:**
   - Click **Approve** button
   - Status changes to "Approved"
   - Customer receives notification
6. **To Reschedule:**
   - Click **Reschedule** button
   - Select new date and time
   - Save changes
   - Customer receives notification
7. **To Cancel:**
   - Click **Cancel** button
   - Confirm cancellation
   - Customer receives notification

**Best Practice:**
- Review new bookings daily
- Approve bookings promptly (within 24 hours)
- Contact customer if rescheduling is needed
- Keep cancellation notes for records

---

### 2.10 Admin Daily Workflow (Recommended)

**Morning Routine:**
1. Log in and check Dashboard stat cards
2. Review Today's Service Schedule
3. Run **Generate Daily Alerts** in DSS
4. Check Stock Replenishment recommendations
5. Approve any Pending services
6. Review and approve Pending user registrations
7. **Review and approve Service Bookings**

**Throughout the Day:**
1. Monitor service progress (Pending → Ongoing → Completed)
2. Approve services as staff creates them
3. Receive stock deliveries as they arrive
4. Respond to low stock alerts
5. Create user accounts as needed
6. **Manage customer bookings and reschedule if needed**

**End of Day:**
1. Complete any Ongoing services that finished
2. Check that all deliveries were recorded
3. Review notification bell for any alerts
4. Export daily reports if needed

---

### 2.11 Archive Management

#### **Task 23: Viewing Archived Records**

The system allows archiving old or completed records to keep your active views clean while preserving historical data.

**Step-by-Step:**
1. Click **Archive** in the sidebar menu
2. You can view archived:
   - Vehicles (old/sold vehicles)
   - Services (old completed services)
   - Bookings (old cancelled/completed bookings)
3. Use filters and search to find specific archived items
4. Archived items don't appear in regular lists but remain in the database

**When to Archive:**
- Vehicles that have been sold or are no longer serviced
- Very old service records (older than 2-3 years)
- Cancelled or old completed bookings

**Note:** Archived records can still be accessed for reporting and history but won't clutter your daily operational views.

---

## 3. Staff User Guide

As Staff, you handle day-to-day operations: receiving inventory, registering vehicles, performing maintenance services. This section guides you through your daily tasks.

### 3.1 Getting Started as Staff

**Step 1: First Login**
1. Open the Caltex AutoPro website
2. Check your email for login credentials from the admin
3. Enter your email and temporary password
4. You'll be prompted to change your password
5. Set a new secure password
6. You'll be redirected to the Staff Dashboard

**Step 2: Understanding Your Dashboard**

The Staff Dashboard shows:
- **Stat Cards:**
  - Total Services (all service records)
  - Ongoing (services in progress)
  - Completed (finished services)
  - Low Stock (items needing replenishment)
- **Today's Service Schedule** — Your work queue showing:
  - Each service with plate number
  - Vehicle description
  - Status badge (Pending/Ongoing/Completed)
  - Mechanic assigned
  - Service date
- Color-coded badges:
  - 🟡 Yellow = Pending (awaiting approval)
  - 🔵 Blue = Ongoing (you can work on these)
  - 🟢 Green = Completed (finished)
- Click any service card to view full details or take action

---

### 3.2 Staff Inventory Tasks

#### **Task 1: Viewing Stock Levels**

**Step-by-Step:**
1. Click **Inventory** in the sidebar
2. Browse the list of all stocked materials
3. Each item shows:
   - Item name and number
   - Current stock quantity
   - Min/Max levels
   - Status indicator (OK/Low/Over)
4. Use the search box to find specific items quickly
5. Note any items marked "Low" — report to admin if urgent

---

#### **Task 2: Receiving Stock Deliveries**

When suppliers deliver materials, you record them in the system.

**Step-by-Step:**
1. Go to **Inventory**
2. Find the item being delivered (use search)
3. Click the **Receive** button
4. Enter the **Quantity Received** from the delivery receipt
5. Click **Confirm**
6. System updates stock immediately
7. Verify the new quantity is correct

**Example:**
- Delivery: 25 liters of Engine Oil 5W-30
- Find "Engine Oil 5W-30" in inventory
- Click Receive
- Enter "25"
- Confirm
- Stock increases from 8 to 33 liters

**Best Practice:** Always verify the physical count matches what you enter.

---

### 3.3 Staff Vehicle Tasks

#### **Task 3: Registering a New Vehicle**

When a new customer brings their vehicle for service, register it.

**Step-by-Step:**
1. Click **Vehicle List** in the sidebar
2. Click **+ Add Vehicle**
3. Fill in the form:
   - **Plate Number:** Ask customer and enter (e.g., ABC-1234)
   - **Description:** Ask make, model, year (e.g., "Honda Civic 2019")
   - **Vehicle Type:** Select from dropdown (Car, Truck, etc.)
   - **Owner:** Type customer name (system suggests from customer list)
     - If customer is new, tell them to register first or ask admin to create account
   - **Odometer:** Check vehicle dashboard, enter current mileage
   - **Service Frequency:** Ask customer or use standard (e.g., 3 months)
4. Click **Save**
5. Vehicle is registered and ready for service

**Important:** System prevents duplicate plate numbers. If you get an error, vehicle may already exist.

---

#### **Task 4: Updating Vehicle Odometer**

After each service, update the vehicle's mileage.

**Step-by-Step:**
1. Go to **Vehicle List**
2. Find the vehicle (search by plate number)
3. Click **Edit**
4. Update the **Odometer** field with current reading
5. Click **Save Changes**

---

#### **Task 5: Viewing Vehicle Details**

To see full vehicle information before servicing:

**Step-by-Step:**
1. Go to **Vehicle List**
2. Click on the vehicle row or click **View Details**
3. Review:
   - Plate, description, type, owner
   - Current odometer
   - Last service date
   - Next PMS due
   - Days until/overdue
4. Use this info when talking to customer about their vehicle status

---

### 3.4 Staff Maintenance Tasks (Most Important)

#### **Task 6: Creating a Service Record**

This is your most common task. When a vehicle arrives for service, create the service record.

**Step-by-Step:**
1. Click **Vehicle Maintenance** in the sidebar
2. Click **+ New Service**
3. **Select the Vehicle:**
   - Start typing the plate number in the "Plate Number" field
   - System shows matching vehicles
   - Select the correct one
   - Vehicle details auto-fill (description, owner, last service)
4. **Enter Your Name:**
   - Type your name in the "Mechanic Name" field (this is you!)
5. **Select Today's Date:**
   - Click the date picker
   - Select the service date (usually today)
6. **Tag Vehicle Issues:**
   - Ask the customer what problems they're experiencing
   - Click the preset tags that match (Battery, Brakes, Engine, Oil Leak, etc.)
   - For issues not in the list, type custom tags and press Enter
   - You can select multiple issues
7. **Add Services You'll Perform:**
   - Click **+ Add Service**
   - Select from dropdown (e.g., "Oil Change")
   - Set quantity (usually 1)
   - Cost auto-fills
   - Click **+ Add Service** again for additional services
8. **Add Materials You'll Use:**
   - Click **+ Add Material**
   - Search or scan barcode of material (e.g., "Engine Oil")
   - Enter quantity you'll use (e.g., 4 liters)
   - System checks if stock is available:
     - ✅ Green check = sufficient stock
     - ❌ Red X = insufficient stock (cannot save)
   - Add all materials needed for the job
9. **Review Total Cost:**
   - System calculates automatically
   - Show customer if needed
10. **Save:**
    - Click **Save Service**
    - Service is created with status "Pending"
    - Wait for admin approval before starting work

**Important Notes:**
- Service stays "Pending" until admin approves it
- You cannot use more materials than available in stock
- If stock is insufficient, ask admin to receive stock first

---

#### **Task 7: Starting Work on an Approved Service**

After admin approves and changes status to "Ongoing", you can start.

**Step-by-Step:**
1. Go to **Vehicle Maintenance**
2. Look for services with blue "Ongoing" badge
3. These are approved — you can begin physical work
4. Perform the services and use the materials as listed
5. If you need to change anything:
   - Click **Edit**
   - Add/remove services or materials
   - Click **Save Changes**

---

#### **Task 8: Completing a Service**

When you finish the work, mark the service as complete.

**Step-by-Step:**
1. Go to **Vehicle Maintenance**
2. Find your completed service (should be "Ongoing")
3. Click **Edit**
4. Change **Status** to "Completed"
5. Double-check all materials and services are correct
6. Click **Save Changes**
7. System automatically:
   - Deducts materials from stock
   - Updates vehicle's last service date
   - Creates issuance records
   - Calculates next PMS due

**Critical:** Once marked Completed, the service is locked. Make sure everything is correct before completing.

---

#### **Task 9: Viewing Service History**

To see past services for reference:

**Step-by-Step:**
1. Go to **Vehicle Maintenance**
2. Use the search box to find services by:
   - Plate number
   - Mechanic name
   - Service ID
3. Filter by status if needed:
   - All
   - Pending (awaiting approval)
   - Ongoing (in progress)
   - Completed (finished)

---

### 3.5 Staff Daily Workflow (Recommended)

**Start of Shift:**
1. Log in and check Dashboard
2. Review **Today's Service Schedule**
3. Note which services are Pending (need admin approval)
4. Note which services are Ongoing (you can start work)
5. Check Low Stock count — report urgent needs to admin

**During Service:**
1. Create service record for each vehicle arrival
2. Wait for admin approval (status changes to Ongoing)
3. Perform the physical work
4. Update odometer reading
5. Mark service as Completed when done

**End of Shift:**
1. Ensure all finished services are marked Completed
2. Report any stock shortages to admin
3. Note any Pending services for tomorrow

**Best Practices:**
- Always verify stock before promising service to customers
- Update odometer readings promptly
- Double-check materials used before completing services
- Communicate with admin about urgent stock needs

---

## 4. Customer User Guide

As a Customer, you can monitor your vehicles and track their maintenance history. This section shows you how to use your customer portal.

### 4.1 Getting Started as Customer

**Option 1: Register Yourself**
1. Go to the Caltex AutoPro website
2. Click **Sign Up**
3. Fill in:
   - Full Name
   - Email Address
   - Password
   - Confirm Password
4. Click **Create Account**
5. Log in with your new credentials
6. (You may need admin approval before accessing the system)

**Option 2: Admin Creates Your Account**
1. Admin will create your account
2. Check your email for login credentials
3. Log in with provided email and password
4. Change your temporary password when prompted

---

### 4.2 Understanding Your Dashboard

**Step 1: First Look**

After logging in, you'll see:
- **Stat Cards** showing:
  - Total Vehicles (your vehicles registered in the system)
  - Active (vehicles current on maintenance)
  - Maintenance (vehicles currently being serviced)
  - PMS Overdue (vehicles past due)
  - Due This Week (vehicles needing service soon)
  - Due Soon (vehicles approaching service date)

**Step 2: Your Dashboard Layout**

The Customer Dashboard has several sections:

**Top Banner (Welcome Section):**
- Time-based greeting (Good Morning/Afternoon/Evening) with your name
- Current date display (day, month, year, weekday)
- Status message about today's schedule
- Four stat cards showing:
  - **Active** — Vehicles current on maintenance (🟢 green)
  - **Under Maintenance** — Vehicles currently being serviced (🔧 wrench)
  - **Due This Week** — Service needed within 7 days (📅 calendar)
  - **Due Today** — Immediate attention needed (⏰ clock)

**Our Services Showcase:**
- Horizontal scrolling carousel
- Displays all available services offered by the shop
- Service cards show service type and icon
- Visual reference of what services you can book

**My Calendar Section:**
- Interactive monthly calendar
- Color-coded dots show PMS schedules:
  - 🔴 Red = Overdue vehicles
  - 🟠 Orange = Due this week
  - 🟡 Yellow = Due within 30 days (upcoming)
  - 🔵 Blue = Due today
  - 🟣 Purple = Booked appointments
- Click any date to see details for that day
- Navigation arrows to browse months
- Legend at bottom explains dot colors

**My Vehicles Section:**
- Cards displaying each of your registered vehicles
- Each card shows:
  - Plate number and description
  - Status badge with color indicator
  - Last service date
  - Next PMS due date
  - Days count (until due or overdue)
- Tap/click any vehicle to see full details and service history

**Recent Services:**
- Shows your last few maintenance records
- Quick access to service history
- "See all →" link to view complete PMS history

---

### 4.3 Viewing Vehicle Details

**Step-by-Step:**
1. From your Dashboard, click on any vehicle card
2. You'll see the vehicle detail page with:
   - Full vehicle information
   - Current odometer reading
   - Service frequency setting
   - Last service date
   - Next PMS due
   - Detailed service history
3. Review the **Service History Table:**
   - Service date
   - Mechanic who performed the service
   - Services rendered
   - Materials used
   - Total cost
4. Click **Back** to return to Dashboard

---

### 4.4 Using the Smart AI Assistant

**Step 1: Opening the Assistant**

The Smart AI Assistant appears as:
- **On Website:** A floating chat widget/button at the bottom right corner with the Caltex logo
- **On Mobile:** Access through a floating action button or dedicated chat icon

**Step 2: Asking Questions**
1. Click/tap the chat widget to open the assistant
2. Type your question in natural language in the message box
3. Press Enter or tap Send
4. The AI responds with information about your vehicles and services drawn from the database

**Example Questions:**
- "What's the status of my vehicles?"
- "When is my next PMS due?"
- "Show me the maintenance history for ABC-1234"
- "How much did I spend on maintenance last month?"
- "Which of my vehicles are overdue?"
- "Give me a fleet summary"
- "What services were done on my truck?"
- "When was my last oil change?"
- "Do I have any vehicles due this week?"

**Step 3: Reviewing Responses**

The AI will provide:
- Direct answers to your questions
- Data from your vehicle and service history
- PMS status information for your vehicles only
- Cost summaries and breakdowns
- Lists of services performed with dates

**Step 4: Closing the Assistant**

Click/tap the X button or click outside the chat window to minimize it. The widget remains available for quick access.

---

### 4.5 Viewing PMS History

**Step-by-Step:**
1. Click **PMS History** in the menu (if available)
2. Or click any vehicle to see its service history
3. Review the table showing:
   - Date of service
   - Vehicle serviced
   - Services performed (Oil Change, Brake Repair, etc.)
   - Materials used (Engine Oil, Brake Pads, etc.)
   - Quantities
   - Total cost
4. Use search to find specific services
5. See cumulative costs over time

**What to Look For:**
- Regular service intervals (every 3 months typically)
- Types of services performed
- Parts that may need replacement soon
- Total maintenance investment

---

### 4.6 Booking a Service Appointment

**Step-by-Step:**
1. Click **Book Service** in the sidebar menu or from the customer dashboard
2. **Select Your Vehicle:**
   - Browse your registered vehicles shown as cards
   - Click on the vehicle that needs service
   - Selected vehicle will be highlighted with a red border
3. **Select Service Type:**
   - Scroll through the available services list
   - Click on the service(s) you need (Oil Change, Brake Repair, etc.)
   - You can select multiple services
   - Selected services will be highlighted
4. **Choose Date:**
   - View the calendar showing available dates
   - Legend indicates:
     - 🟢 Green = Available slots
     - 🟡 Yellow = Fully booked
     - ⚪ Gray = Shop closed
   - Click on an available date (green)
   - Selected date will turn red
5. **Choose Time Slot:**
   - After selecting a date, available time slots appear
   - Click your preferred time slot
   - Taken slots appear grayed out with strikethrough
6. **Add Notes (Optional):**
   - Enter any additional information or special requests
   - Describe specific issues or concerns
7. **Submit Booking:**
   - Review all your selections
   - Click **Submit Booking** button
   - Confirmation message appears
   - Your booking appears in "My Bookings" section
8. **Track Your Booking:**
   - Go to **My Bookings** to view status
   - Booking status can be: Pending, Approved, Rescheduled, or Cancelled
   - You'll receive notifications when status changes

---

### 4.7 Viewing My Bookings

**Step-by-Step:**
1. Click **My Bookings** in the sidebar menu
2. View all your service bookings in a list
3. Each booking shows:
   - Booking date and time
   - Vehicle (plate number and description)
   - Services requested
   - Status badge (Pending/Approved/Rescheduled/Cancelled)
   - Notes you provided
4. **Status Meanings:**
   - 🟡 **Pending** — Awaiting admin approval
   - 🟢 **Approved** — Confirmed by staff
   - 🔵 **Rescheduled** — Date/time changed
   - 🔴 **Cancelled** — Booking cancelled
5. Use search bar to find specific bookings
6. You can view booking details by clicking on any booking

### 4.8 Checking Notifications

**Step-by-Step:**
1. Look for the bell icon (🔔) at the top of the page
2. Red badge shows number of unread notifications
3. Click the bell to open notifications
4. You'll see alerts like:
   - "Vehicle ABC-1234 is overdue for PMS"
   - "Your vehicle service is completed"
   - "PMS due this week for DEF-5678"
   - "Your booking has been approved"
5. Click a notification to view details
6. Notifications mark as read automatically

---

### 4.9 Updating Your Profile

**Step-by-Step:**
1. Click your avatar or name at the top right
2. Select **Profile**
3. View your account information
4. Click **Edit Profile** to update:
   - Your name
   - Profile photo
5. Click **Save Changes**

---

### 4.10 Changing Your Password

**Step-by-Step:**
1. Go to **Profile**
2. Click **Change Password**
3. Enter your **Current Password**
4. Enter your **New Password**
5. **Confirm New Password**
6. Click **Update Password**
7. Success message appears

---

### 4.11 Customer Best Practices

**Stay Informed:**
- Check Dashboard weekly to monitor vehicle status
- Pay attention to overdue warnings
- Book service as soon as you see "Due Soon"

**Use the AI Assistant:**
- Ask questions anytime you're unsure
- Get quick summaries without navigating menus
- Review costs and history easily

**Respond to Notifications:**
- Enable push notifications on mobile app
- Act on overdue alerts promptly
- Preventive maintenance saves money long-term

**Keep Contact Info Updated:**
- Ensure your email and phone are current
- This ensures you receive important alerts
- Makes booking appointments easier

---

## 5. Mobile App Guide

The Caltex AutoPro mobile app (Android/iOS) provides on-the-go access for all user roles.

### 5.1 Getting Started with Mobile App

**Step 1: Installation**
1. Go to Google Play Store (Android) or App Store (iOS)
2. Search for "Caltex AutoPro"
3. Tap **Install** or **Get**
4. Wait for download and installation
5. Tap **Open**

**Step 2: Welcome Screen**

On first launch:
- See JA Noble Enterprise / Caltex branding
- Two buttons appear:
  - **Sign In** (existing users)
  - **Create Account** (new customers)

**Step 3: Signing In**
1. Tap **Sign In**
2. Enter your email address
3. Enter your password
4. Tap **Sign In** button
5. Or tap **Sign in with Google** for Google account
6. App redirects to your role-specific dashboard

**Step 4: Creating an Account (Customers Only)**
1. Tap **Create Account**
2. Fill in the form:
   - Full Name
   - Email Address
   - Password
   - Confirm Password
3. Tap **Register**
4. Account created — you can now sign in
5. (May require admin approval)

---

### 5.2 Mobile App Navigation (All Users)

**Bottom Navigation Bar:**

The app uses a bottom navigation bar with 5 tabs:

| Icon | Tab | Function |
|------|-----|----------|
| 🏠 | Dashboard | Main home screen (role-specific) |
| 📦 | Inventory | Stock management (Admin/Staff) |
| 🔴 | Scan | Opens camera for barcode/QR scanning |
| 🔧 | Maintenance | Service records (Admin/Staff) |
| 🚗 | Vehicle | Fleet management (Admin/Staff) |

**Note:** Customer app has simplified navigation focusing on vehicle monitoring.

**Top Bar:**
- Caltex AutoPro logo
- Notification bell 🔔 with badge
- Profile avatar (tap for profile/logout)

---

### 5.3 Admin Mobile App

#### **Dashboard Screen**

Shows overview cards:
- Total Vehicles
- Due for PMS
- Low Stock
- Services Today
- Total Users

Below the stat cards:
- **PMS Calendar** — Visual calendar showing vehicles due for maintenance
- **Today's Services** — List of scheduled services

Tap any card to navigate to relevant section.

#### **Using Bottom Navigation**

The mobile app uses a bottom navigation bar with 5 main sections:
- **Dashboard** (Home icon) — Overview and statistics
- **Inventory** (Box icon) — Stock management
- **Scan** (Center button with camera icon) — Barcode/QR scanner
- **Maintenance** (Wrench icon) — Service records
- **Vehicles** (Truck icon) — Fleet management

#### **Managing Service Bookings**
1. From Dashboard or main menu, navigate to **Service Bookings**
2. View all customer bookings with status indicators
3. **To Approve a Booking:**
   - Tap the booking
   - Tap **Approve** button
   - Customer receives notification
4. **To Reschedule:**
   - Tap the booking
   - Tap **Reschedule**
   - Select new date and time
   - Save changes
5. Filter bookings by status (All/Approved/Rescheduled/Cancelled)

#### **Managing Services**
1. Tap **Maintenance** tab
2. View all service records
3. Tap any service to view details
4. **To Approve:**
   - Tap service
   - Tap **Edit**
   - Change Status to "Ongoing"
   - Tap **Save**
5. **To Complete:**
   - Tap service
   - Change Status to "Completed"
   - Tap **Save**
   - Stock deducts automatically

#### **Managing Users**
1. Swipe menu or navigate to **Users**
2. View all system users
3. Tap user to see details
4. **To Approve Pending User:**
   - Tap user
   - Tap **Approve** button
5. **To Activate/Deactivate:**
   - Tap user
   - Tap **Activate** or **Deactivate**

#### **Generating DSS Alerts**
1. Navigate to **Notifications** or **DSS**
2. Tap **Generate Daily Alerts**
3. System analyzes stock and PMS
4. Creates and sends notifications
5. Confirmation message appears

---

### 5.4 Staff Mobile App

#### **Dashboard Screen**

Shows:
- Today's Services (count)
- Ongoing
- Pending
- Low Stock

Below cards:
- **Today's Service Schedule**
- Each service card shows plate, description, status, mechanic
- Tap any card to view full details

#### **Using the Barcode Scanner**

This is a key mobile feature for staff.

**Step-by-Step:**
1. Tap the large **center button** (🔴 Scan icon) on bottom navigation
2. Camera opens
3. Point camera at barcode or QR code
4. System auto-detects and scans
5. Item details appear:
   - Item name and number
   - Commodity group
   - UOM
   - Cost
   - Type (Material/Service)
   - Current stock (if available)
6. **If item is in stock:**
   - See current quantity
   - Option to **Receive Stock** (add incoming quantity)
7. **If item not in stock:**
   - Message: "Item not in stock inventory. Contact admin."

**Use Cases:**
- Quick item lookup during service
- Receiving stock deliveries (scan and receive)
- Verifying materials before use
- Adding materials to service records

---

#### **Receiving Stock on Mobile**

**Step-by-Step:**
1. When supplier delivers materials:
2. Tap **center Scan button**
3. Scan each item's barcode
4. Tap **Receive Stock** button
5. Enter quantity received
6. Tap **Confirm**
7. Stock updates immediately
8. Repeat for all delivered items

**Alternative (without scanning):**
1. Tap **Inventory** tab
2. Tap the **Receive Items** button (floating action button or top button)
3. Search for the item manually by typing
4. Tap the item from results
5. Enter **quantity received**
6. Tap **Confirm** or **Save**
7. Stock updates immediately

**Note:** The Receive Items feature is available in both Staff and Admin mobile apps for quickly updating stock as deliveries arrive.

---

#### **Creating a Service on Mobile**

**Step-by-Step:**
1. Tap **Maintenance** tab
2. Tap **+ New Service** button (floating action button)
3. **Select Vehicle:**
   - Start typing plate number (autocomplete)
   - Or tap barcode icon and scan vehicle barcode
   - Details auto-populate
4. **Enter mechanic name** (pre-filled with your name)
5. **Select date** (defaults to today)
6. **Tag issues:**
   - Tap preset tags (Battery, Brakes, Engine, etc.)
   - Or type custom issues
7. **Add services:**
   - Tap **+ Add Service**
   - Select from dropdown
   - Set quantity
8. **Add materials:**
   - Tap **+ Add Material**
   - Search or tap scan icon
   - Enter quantity
   - System validates stock
9. Review total cost
10. Tap **Save** button
11. Service created as Pending

---

#### **Completing a Service on Mobile**

**Step-by-Step:**
1. From Dashboard, tap the service card
2. Or go to Maintenance tab and find service
3. Tap the service
4. Tap **Edit** button
5. Change **Status** to "Completed"
6. Verify all details are correct
7. Tap **Save**
8. Confirmation appears
9. Stock deducts automatically

---

#### **Viewing and Managing Vehicles on Mobile**

**Step-by-Step:**
1. Tap **Vehicle** tab
2. See stat cards: Total, Cars, Trucks
3. Scroll through vehicle list
4. Use search box to find vehicles
5. Tap any vehicle to see details
6. **To Add Vehicle:**
   - Tap **+ Add Vehicle** button
   - Fill form (plate, description, type, owner, odometer, frequency)
   - Tap **Save**
7. **To Edit Vehicle:**
   - Tap vehicle
   - Tap **Edit**
   - Update fields
   - Tap **Save**

---

### 5.5 Customer Mobile App

#### **Dashboard Screen**

Shows your vehicles with status indicators:
- **Top Banner** — Personalized greeting with time-based message (Good Morning/Afternoon/Evening)
- Date display showing current day, month, and year
- **Stat Cards:**
  - Total Vehicles
  - Active (vehicles current on maintenance)
  - Under Maintenance (currently being serviced)
  - Due This Week (vehicles needing service within 7 days)
  - Due Today (immediate attention needed)

**Bottom Sections:**
- **My Calendar** — Interactive calendar showing PMS due dates with color-coded indicators
- **My Vehicles** — Card view of all your registered vehicles
- **Recent Services** — Latest maintenance history

Each vehicle card shows:
- Plate number
- Vehicle description (make/model)
- Status badge (🟢 Active / 🟡 Due Soon / 🔴 Overdue)
- Last service date
- Next PMS due date
- Days until service (or days overdue)

#### **Using Bottom Navigation**

The customer mobile app has a simpler navigation:
- **Dashboard** (Home icon) — Main overview screen
- **Book Service** (Calendar icon) — Schedule appointments
- **My Bookings** (List icon) — View booking history
- **PMS History** (Document icon) — Maintenance records
- **Profile** (User icon) — Account settings

#### **Booking Service from Mobile**

**Step-by-Step:**
1. Tap **Book Service** icon in bottom navigation
2. **Select Vehicle:**
   - View your vehicles as cards
   - Tap the vehicle needing service
   - Selected vehicle highlights with red border
3. **Choose Services:**
   - Scroll through available service types
   - Tap each service you need
   - Can select multiple services
   - Selected services show checkmarks
4. **Pick Date:**
   - Calendar shows available, fully booked, and closed dates
   - Legend:
     - 🟢 Green dots = Slots available
     - 🟡 Yellow = Fully booked
     - ⚪ Gray = Closed
   - Tap an available date (green)
5. **Pick Time:**
   - Available time slots appear as chips
   - Taken slots shown grayed out
   - Tap your preferred time
6. **Add Notes:**
   - Type additional details or special requests
   - Describe specific issues
7. **Submit:**
   - Review selections
   - Tap **Submit Booking** button
   - Confirmation appears
8. **Track Booking:**
   - Go to **My Bookings** tab
   - View status (Pending/Approved/Rescheduled/Cancelled)
   - Receive push notifications for status updates

#### **Viewing Vehicle Details**

**Step-by-Step:**
1. From Dashboard, tap any vehicle card
2. See complete vehicle information:
   - Plate, description, type
   - Current odometer
   - Last service date
   - Next PMS due
   - Days until/overdue
3. Scroll down to see **Service History:**
   - All past services with dates
   - Services performed
   - Materials used
   - Costs per service
4. Tap **Back** arrow to return to Dashboard

#### **Viewing My Bookings on Mobile**

**Step-by-Step:**
1. Tap **My Bookings** icon in bottom navigation
2. See all your booking requests listed
3. Each booking shows:
   - Scheduled date and time
   - Vehicle information
   - Services requested
   - Status badge with color
   - Your notes
4. Tap any booking to view full details
5. Filter by status if needed
6. Receive push notifications when status changes

#### **Using the Mobile AI Assistant**

**Step-by-Step:**
1. Look for floating chat button (bottom right)
2. Tap to open chat interface
3. Type your question
4. Tap Send
5. AI responds with vehicle information
6. Ask follow-up questions
7. Swipe down or tap X to close

**Example Mobile Questions:**
- "Status of all my vehicles?"
- "When is next PMS?"
- "Maintenance history"
- "Total costs last month"

---

### 5.6 Mobile Push Notifications

#### **Enabling Notifications**

**First Time Setup:**
1. When you first open the app, you'll see a permission request
2. Tap **Allow** to enable push notifications
3. App uses OneSignal for real-time alerts

**If You Missed It:**
1. Go to your phone Settings
2. Find Caltex AutoPro app
3. Tap Notifications
4. Enable notifications

**In-App Notification Preferences:**
1. Tap profile avatar
2. Go to **Notification Settings**
3. Toggle preferences:
   - Low Stock Alerts (Admin)
   - PMS Overdue (Admin/Customer)
   - PMS Due This Week (Admin/Customer)
   - PMS Due Soon (Admin/Customer)
   - Service Updates (Staff/Customer)

#### **Receiving and Viewing Notifications**

**When Notification Arrives:**
- Phone shows banner notification
- App icon shows badge number
- Tap notification to open app

**Viewing in App:**
1. Tap bell icon 🔔 at top
2. See list of all notifications
3. Unread show in bold with blue dot
4. Tap any notification to view details
5. Automatically marks as read

---

### 5.7 Mobile App Tips

**For Staff:**
- Use barcode scanner whenever possible (faster than typing)
- Keep app open during service operations for quick access
- Update services immediately when work is done
- Check Dashboard at start of shift

**For Customers:**
- Enable push notifications for PMS reminders
- Check app weekly to monitor vehicle status
- Use AI assistant for quick questions
- Book appointments directly from app

**General:**
- Keep app updated (check store for updates)
- Ensure stable internet connection
- Log out when using shared devices
- Contact admin if you encounter issues

---

## 6. Notifications & Alerts

### 6.1 Understanding the Notification System

Caltex AutoPro uses a comprehensive notification system to keep all users informed.

**Notification Types:**
1. **In-App Notifications** (Bell icon in web and mobile)
2. **Push Notifications** (Mobile only - via OneSignal)
3. **Email Notifications** (For account creation and password resets)

---

### 6.2 Notification Categories

**For Admin:**
- 🔴 **Low Stock Alert** — Items below minimum level
- 🔴 **Out of Stock Alert** — Items completely depleted
- 🟡 **PMS Overdue** — Vehicles past maintenance date
- 🟡 **PMS Due This Week** — Upcoming maintenance reminders
- 🟠 **PMS Due Soon** — Vehicles approaching service date
- ℹ️ **Pending User Registration** — New customers awaiting approval
- ℹ️ **Service Status Changes** — When services move between statuses

**For Staff:**
- ✅ **Service Approved** — Admin changed status to Ongoing
- ℹ️ **Low Stock Alert** — Warning about depleting materials
- ℹ️ **Service Assignments** — New services assigned to you

**For Customer:**
- 🔴 **PMS Overdue** — Your vehicle is past due
- 🟡 **PMS Due This Week** — Service needed this week
- 🟠 **PMS Due Soon** — Maintenance approaching in 30 days
- ✅ **Service Completed** — Your vehicle service is done
- ℹ️ **Service Updates** — Status changes on your services

---

### 6.3 Viewing Notifications (Web)

**Step-by-Step:**
1. Look for bell icon 🔔 in top navigation bar
2. Red badge shows unread notification count
3. Click bell icon
4. Dropdown or panel opens showing:
   - Notification title
   - Description
   - Timestamp
   - Read/unread status
5. Click any notification to:
   - View full details
   - Navigate to related item (vehicle, service, stock item)
   - Mark as read
6. Click **Mark All as Read** to clear all unread

---

### 6.4 Viewing Notifications (Mobile)

**Step-by-Step:**
1. Tap bell icon 🔔 at top of screen
2. Badge shows unread count
3. Notification list opens
4. Each notification shows:
   - Icon indicating type
   - Title and message
   - Time ago (e.g., "2 hours ago")
   - Blue dot for unread
5. Tap notification to:
   - View details
   - Navigate to related screen
   - Auto-marks as read
6. Swipe down to refresh

---

### 6.5 Managing Push Notifications (Mobile)

#### **In-App Notification Preferences**

**Step-by-Step:**
1. Tap profile avatar
2. Tap **Notification Settings** or **Preferences**
3. You'll see toggle switches for each alert type
4. Toggle ON (green) to receive alerts
5. Toggle OFF (gray) to stop receiving
6. Changes save automatically

**Recommended Settings:**

**Admin:**
- ✅ Low Stock — ON
- ✅ PMS Overdue — ON
- ✅ PMS Due This Week — ON
- ✅ PMS Due Soon — ON

**Staff:**
- ✅ Low Stock — ON
- ✅ Service Updates — ON

**Customer:**
- ✅ PMS Overdue — ON
- ✅ PMS Due This Week — ON
- ✅ PMS Due Soon — ON
- ✅ Service Updates — ON

#### **Device-Level Settings**

If you're not receiving notifications:

**Android:**
1. Open Settings
2. Go to Apps
3. Find Caltex AutoPro
4. Tap Notifications
5. Enable "Allow Notifications"
6. Check that sound, vibration, and banner are enabled

**iOS:**
1. Open Settings
2. Scroll to Caltex AutoPro
3. Tap Notifications
4. Enable "Allow Notifications"
5. Choose alert style (Banner or Alert)
6. Enable Sounds and Badges

---

### 6.6 DSS Alert Generation (Admin)

**What It Does:**
- Analyzes all stock levels vs consumption rates
- Identifies items needing replenishment
- Checks all vehicle PMS schedules
- Creates targeted notifications for admins and affected customers

**How to Trigger:**

**Web:**
1. Go to **Decision Support System**
2. Click **Generate Daily Alerts** button
3. Wait for processing (usually 5-10 seconds)
4. Confirmation message appears
5. Notifications sent to bell icon and mobile push

**Mobile:**
1. Navigate to DSS or Notifications section
2. Tap **Generate Daily Alerts**
3. Confirmation appears
4. Check notification bell for new alerts

**Best Practice:**
- Run once daily, preferably in the morning
- System prevents duplicate daily alerts
- Review DSS recommendations after generating

---

### 6.7 Notification Best Practices

**For All Users:**
- Check notification bell daily
- Don't ignore overdue alerts
- Act on critical notifications promptly
- Mark notifications as read to stay organized

**For Admin:**
- Generate DSS alerts every morning
- Review stock alerts before ordering
- Approve pending users regularly
- Monitor PMS overdue vehicles

**For Staff:**
- Keep push notifications enabled
- Check for service approvals throughout the day
- Report critical stock alerts to admin
- Update services promptly to trigger customer notifications

**For Customers:**
- Enable all PMS notifications
- Respond to overdue alerts immediately
- Book service when you see "Due Soon"
- Preventive maintenance avoids costly repairs

---

## 7. Profile & Account Settings

### 7.1 Accessing Your Profile

**Web:**
1. Click your avatar or name in top right corner
2. Click **Profile** from dropdown
3. Profile page opens

**Mobile:**
1. Tap profile avatar icon (top right)
2. Profile screen opens

---

### 7.2 Viewing Profile Information

Your profile displays:
- Full Name
- Email Address
- Role (Admin/Staff/Customer)
- Account Status (Active/Inactive/Pending)
- Profile Photo (if uploaded)
- Account creation date

---

### 7.3 Editing Your Profile

**Step-by-Step (Web):**
1. Go to Profile page
2. Click **Edit Profile** button
3. Update editable fields:
   - Full Name
   - Profile Photo (click to upload image)
4. Click **Save Changes**
5. Success message appears
6. Profile updates across the system

**Step-by-Step (Mobile):**
1. Tap profile avatar
2. Tap **Edit Profile**
3. Tap fields to edit:
   - Full Name
   - Tap photo circle to change picture
4. Tap **Save** or checkmark icon
5. Profile updated

**Note:** You cannot change your email or role yourself. Contact admin for these changes.

---

### 7.4 Changing Your Password

**Step-by-Step (Web):**
1. Go to Profile page
2. Click **Change Password** or **Security**
3. Form appears with fields:
   - Current Password
   - New Password
   - Confirm New Password
4. Fill in all fields
5. Click **Update Password** or **Save**
6. Success message confirms change
7. You can continue using the app (no need to re-login)

**Step-by-Step (Mobile):**
1. Tap profile avatar
2. Tap **Change Password** or **Security**
3. Enter:
   - Current Password
   - New Password
   - Confirm New Password
4. Tap **Update** or **Save**
5. Success message appears

**Password Requirements:**
- Minimum 8 characters
- Mix of letters and numbers recommended
- Should be unique to this account

**If You Forgot Your Current Password:**
1. Log out
2. Click **Forgot Password?** on login screen
3. Enter your email
4. Check email for reset link
5. Follow link to set new password

---

### 7.5 Managing Notification Preferences

**Step-by-Step:**
1. Go to Profile or Settings
2. Click/Tap **Notification Settings** or **Notifications**
3. See list of notification types with toggle switches
4. Toggle each preference ON or OFF:

**Admin Preferences:**
   - Low Stock Alerts
   - PMS Overdue
   - PMS Due This Week
   - PMS Due Soon
   - Pending User Registrations

**Staff Preferences:**
   - Low Stock Alerts
   - Service Status Changes
   - Service Assignments

**Customer Preferences:**
   - PMS Overdue (for your vehicles)
   - PMS Due This Week
   - PMS Due Soon
   - Service Completion Updates

5. Changes save automatically
6. Exit settings

---

### 7.6 Viewing Account Activity (If Available)

Some systems show recent account activity:
- Last login date and time
- Recent actions (services created, vehicles added, etc.)
- Login history
- Device information

Check your profile page for an **Activity** or **History** tab.

---

### 7.7 Logging Out

**Web:**
1. Click your avatar or name (top right)
2. Click **Logout** or **Sign Out**
3. You're returned to login page
4. Session ends securely

**Mobile:**
1. Tap profile avatar
2. Scroll to bottom
3. Tap **Logout** or **Sign Out**
4. Confirmation dialog may appear
5. Tap **Yes** or **Confirm**
6. App returns to welcome screen

**Best Practice:**
- Always log out on shared devices
- Mobile app can stay logged in on personal devices
- Log out if you suspect unauthorized access

---

### 7.8 Deleting Your Account (Customer Only)

If you wish to delete your customer account:
1. Contact the system administrator
2. Send email to: caltexautopro2026@gmail.com
3. Request account deletion
4. Admin will process your request
5. Your data will be removed per privacy policy

**Note:** Admin and Staff accounts can only be deleted by administrators through User Management.

---

## 8. Troubleshooting & FAQ

## 8. Troubleshooting & FAQ

### 8.1 Login Issues

**Problem: I can't log in / "Invalid credentials" error**

**Solutions:**
1. **Verify your email and password:**
   - Check for typos
   - Email is case-insensitive, password is case-sensitive
   - Watch out for extra spaces

2. **Check if CAPS LOCK is on**

3. **Try Forgot Password:**
   - Click "Forgot Password?" on login page
   - Enter your email
   - Check email inbox (and spam folder)
   - Follow reset link
   - Set new password

4. **Check account status:**
   - New accounts may need admin approval
   - Account might be deactivated
   - Contact admin: caltexautopro2026@gmail.com

5. **Clear browser cache:**
   - Press Ctrl+Shift+Delete (Windows) or Cmd+Shift+Delete (Mac)
   - Clear cookies and cache
   - Try logging in again

6. **Try different browser:**
   - Use Chrome, Firefox, or Edge
   - Ensure JavaScript is enabled

---

**Problem: First-time login not working (Admin/Staff)**

**Solution:**
1. Check your email for welcome message with credentials
2. Check spam/junk folder
3. Use exact password provided (watch for spaces, case)
4. System will prompt password change after first login
5. If still failing, ask admin to resend credentials

---

**Problem: "Account is pending approval"**

**Solution:**
- Your customer account needs admin approval
- Contact admin or wait for approval
- Usually processed within 24 hours

---

### 8.2 Inventory Issues

**Problem: "Insufficient stock" error when creating service**

**What it means:**
- You're trying to use more materials than available in inventory

**Solutions:**
1. Check current stock level:
   - Go to Inventory → Stock
   - Find the item
   - View current quantity
2. If stock is low:
   - Reduce quantity in service record, OR
   - Receive new stock first (if delivery arrived), OR
   - Contact admin to order more stock
3. Never bypass stock validation — it prevents errors

---

**Problem: Item not showing in stock inventory**

**Solutions:**
1. Check if item exists in **Item Master**:
   - Go to Inventory → Item Master
   - Search for the item
2. If it exists but not in Stock:
   - Item may be Service type (not Material)
   - Only Material items can be stocked
   - Add it to Stock using **+ Add Stock Item**
3. If it doesn't exist at all:
   - Admin needs to create it in Item Master first
   - Then add to Stock

---

**Problem: Barcode scanner not working (Mobile)**

**Solutions:**
1. **Grant camera permission:**
   - Go to phone Settings
   - Find Caltex AutoPro
   - Enable Camera permission
2. **Improve scanning conditions:**
   - Ensure good lighting
   - Hold phone steady
   - Keep barcode flat and clean
   - Try different distance (6-12 inches usually works)
3. **Check barcode format:**
   - System supports standard barcodes and QR codes
   - If custom codes, verify they're registered in system
4. **Manual entry alternative:**
   - Use search instead
   - Type item name or number

---

**Problem: Stock count doesn't match physical inventory**

**Solutions:**
1. **Review recent transactions:**
   - Check Inventory Transactions list
   - Look for duplicate receives or missing records
2. **Check completed services:**
   - When services complete, materials deduct automatically
   - Verify service records match actual usage
3. **Perform physical count:**
   - Count actual stock
   - Admin can adjust if needed (use Receive with negative for deductions)
4. **Prevent future mismatches:**
   - Always receive stock immediately when delivered
   - Complete services promptly
   - Don't take materials without recording

---

### 8.3 Vehicle & PMS Issues

**Problem: Can't add vehicle — "Plate number already exists"**

**Solution:**
- Vehicle is already registered
- Go to Vehicle List
- Search for the plate number
- If it's correct: Use existing vehicle
- If it's an error: Admin can delete duplicate

---

**Problem: Vehicle shows "Overdue" but was recently serviced**

**Diagnosis:**
This happens when service wasn't marked Completed properly.

**Solutions:**
1. **Check service status:**
   - Go to Vehicle Maintenance
   - Search for recent service for that vehicle
   - If status is Pending or Ongoing (not Completed), complete it
2. **Verify service completion:**
   - Only Completed services update Last Service Date
   - Edit service and change status to Completed
3. **Check Service Frequency setting:**
   - Go to Vehicle List → Edit vehicle
   - Verify Service Frequency is correct (e.g., 3 months)
   - Next PMS auto-calculates from this
4. **Manual check:**
   - View vehicle details
   - Verify Last Service Date is correct
   - If wrong, a service wasn't properly completed

---

**Problem: Next PMS Due date seems wrong**

**Explanation:**
Next PMS Due = Last Service Date + Service Frequency

**Solutions:**
1. Check vehicle details:
   - Last Service Date correct?
   - Service Frequency correct?
2. If Service Frequency is wrong:
   - Edit vehicle
   - Update Service Frequency (months)
   - System recalculates Next PMS
3. If Last Service Date is wrong:
   - Find the most recent completed service
   - Verify it's marked Completed
   - System should have updated date automatically

---

### 8.4 Service & Maintenance Issues

**Problem: Can't edit or delete a completed service**

**Explanation:**
- Completed services are locked to maintain audit trail
- Stock has already been deducted
- Transaction records created

**Solutions:**
- Completed services cannot be modified
- If there's an error, create a correcting service
- Contact admin if critical correction needed

---

**Problem: Service is stuck in "Pending" status (Staff)**

**Solution:**
- Pending services need admin approval
- Contact admin to change status to Ongoing
- Admin must manually approve before you can proceed

---

**Problem: Service total cost seems wrong**

**Diagnosis:**
Total = Sum of (Service costs + Material costs)

**Solutions:**
1. Review services rendered:
   - Check quantity of each service
   - Verify cost per service in Item Master
2. Review materials used:
   - Check quantity of each material
   - Verify cost per material in Item Master
3. If costs in Item Master are wrong:
   - Admin updates in Item Master
   - Doesn't automatically update existing services
   - Future services will use new costs

---

**Problem: Can't find a service record**

**Solutions:**
1. Use search function:
   - Try plate number
   - Try mechanic name
   - Try service ID
2. Check filter settings:
   - Might be filtered to only Pending or Ongoing
   - Select "All" status filter
3. Check date range (if applicable):
   - Service might be older than displayed range
4. Verify service was saved:
   - Check with person who created it
   - May have closed form without saving

---

### 8.5 User Management Issues

**Problem: Can't create new user (Admin)**

**Solutions:**
1. Check email format:
   - Must be valid email (has @ and domain)
2. Check for duplicate email:
   - Email must be unique in system
   - Search user list first
3. Check internet connection:
   - Firebase account creation requires connectivity
4. Try again:
   - If error persists, check error message
   - May be Firebase service issue

---

**Problem: User didn't receive welcome email**

**Solutions:**
1. Check spam/junk folder
2. Verify email address is correct in User Management
3. Check email service status
4. Admin can provide credentials manually
5. User can use Forgot Password to set password

---

**Problem: Can't deactivate or delete a user**

**Solutions:**
1. Check your own permissions:
   - Only admins can manage users
2. Can't delete yourself:
   - Must use different admin account
3. Check for related records:
   - User may have vehicles or services
   - System may prevent deletion
   - Use Deactivate instead

---

### 8.6 Notification Issues

**Problem: Not receiving push notifications (Mobile)**

**Solutions:**
1. **Check app permissions:**
   - Go to phone Settings
   - Find Caltex AutoPro
   - Enable Notifications
2. **Check in-app preferences:**
   - Open app → Profile
   - Go to Notification Settings
   - Ensure relevant toggles are ON
3. **Check Do Not Disturb:**
   - Phone might be in DND mode
   - Check phone settings
4. **Reinstall app:**
   - Uninstall app
   - Reinstall from store
   - Log in again
   - Grant permissions when prompted
5. **Check internet connection:**
   - Push notifications require connectivity
   - Verify WiFi or mobile data is active

---

**Problem: Too many notifications**

**Solution:**
1. Go to Notification Settings in Profile
2. Disable specific notification types:
   - Turn OFF alerts you don't need
   - Keep critical alerts ON (e.g., PMS Overdue)
3. Mute non-critical notifications

---

**Problem: Notification says vehicle overdue but it's not**

**Solution:**
- See section 8.3 "Vehicle shows Overdue but was recently serviced"
- Usually caused by service not marked Completed

---

### 8.7 Mobile App Issues

**Problem: App won't open / crashes on startup**

**Solutions:**
1. **Force close and reopen:**
   - Swipe app away from recent apps
   - Reopen from app drawer
2. **Check for updates:**
   - Go to app store
   - Update to latest version
3. **Clear app cache (Android):**
   - Settings → Apps → Caltex AutoPro
   - Clear Cache (NOT Clear Data)
4. **Reinstall app:**
   - Uninstall
   - Reinstall from store
   - Log in again
5. **Check device compatibility:**
   - Android 6.0+ or iOS 13.0+ required
6. **Free up storage:**
   - Ensure device has available storage

---

**Problem: App is slow or freezing**

**Solutions:**
1. Close background apps
2. Check internet connection speed
3. Update app to latest version
4. Restart device
5. Reinstall app if problem persists

---

**Problem: Can't scan barcodes (Mobile)**

**Solutions:**
- See section 8.2 "Barcode scanner not working"

---

**Problem: Changes not syncing between web and mobile**

**Solutions:**
1. Check internet connection on both devices
2. Refresh/pull down to refresh on mobile
3. Log out and log back in
4. Check that you're using same account
5. Wait a few seconds for sync
6. Contact admin if data inconsistency persists

---

### 8.8 Report & DSS Issues

**Problem: Smart Reports AI gives inaccurate answers**

**Solutions:**
1. **Rephrase your question:**
   - Be more specific
   - Include date ranges
   - Use exact plate numbers or names
2. **Verify underlying data:**
   - Check if source data is correct
   - AI pulls from live database
3. **Try simpler questions:**
   - Break complex queries into parts
4. **Report issue:**
   - Contact admin with specific question and wrong answer

---

**Problem: DSS shows wrong recommendations**

**Diagnosis:**
DSS recommendations based on:
- Stock levels and consumption history
- PMS schedules and service frequency

**Solutions:**
1. **For stock recommendations:**
   - Verify stock levels are correct
   - Check issuance history
   - Ensure services are marked Completed (to record consumption)
2. **For PMS recommendations:**
   - Verify Last Service dates are updated
   - Check Service Frequency settings
   - Ensure services are Completed
3. **Regenerate alerts:**
   - Click "Generate Daily Alerts" again
   - System recalculates from current data

---

**Problem: Can't export report to PDF/Excel**

**Solutions:**
1. Check browser popup settings:
   - Browser may be blocking download
   - Allow popups for Caltex AutoPro
2. Check download folder:
   - File may have downloaded automatically
3. Try different browser
4. Check internet connection
5. Try again (may be temporary issue)

---

### 8.9 Common Error Messages

**"Session expired. Please log in again."**
- Your login session timed out (usually after several hours of inactivity)
- Solution: Log in again

**"Insufficient permissions."**
- You're trying to access a feature not available to your role
- Solution: Contact admin if you need access

**"Network error. Please try again."**
- Internet connection problem
- Solution: Check WiFi/data connection and retry

**"Database error."**
- Server-side issue
- Solution: Wait a moment and try again. If persists, contact admin.

**"Invalid data format."**
- Input doesn't match expected format (e.g., wrong plate format)
- Solution: Check input format and try again

---

### 8.10 FAQ

**Q: How often should vehicles get PMS?**

A: Typically every 3 months or per manufacturer recommendation. This is set in the vehicle's Service Frequency field. Commercial vehicles may need more frequent service (every 1-2 months).

---

**Q: What happens to stock when I delete a completed service?**

A: You cannot delete completed services — they're locked. This prevents stock discrepancies. Completed services have already deducted stock and created irreversible transaction records.

---

**Q: Can customers create their own services?**

A: No. Only Admin and Staff can create service records. Customers can view their service history and book appointments.

---

**Q: How does the system calculate "Days of Stock Left"?**

A: Days Left = Current Stock ÷ Consumption Rate

Consumption Rate = Average daily usage based on issuance history from completed services.

---

**Q: Why can't I add a service-type item to stock?**

A: Service items (like "Oil Change" or "Brake Repair") are non-inventory items. Only Material items (like "Engine Oil" or "Brake Pads") can be stocked. Services represent labor, not physical goods.

---

**Q: Can I use the system offline?**

A: No. Caltex AutoPro requires an internet connection to access real-time data and sync across devices. Mobile app caches some data but needs connectivity for most operations.

---

**Q: How do I print reports?**

A: Use the Smart Reports AI feature to generate reports, then export as PDF. You can print the PDF using your printer. Alternatively, use browser print function (Ctrl+P) on DSS pages.

---

**Q: What's the difference between Item Master and Stock?**

A:
- **Item Master:** Catalog of ALL items (materials and services) with base information
- **Stock:** Inventory of MATERIAL items only, with quantities and min/max levels

Think of Item Master as the "menu" and Stock as "what's in the warehouse."

---

**Q: Can I change a vehicle's owner?**

A: Yes. Admin or Staff can edit the vehicle and select a different owner from the customer list. This is common when vehicles are sold.

---

**Q: Why am I getting duplicate DSS alerts?**

A: System prevents duplicate daily alerts. If you're getting repeats:
- Check if multiple admins are generating alerts
- Best practice: One admin runs it once per day in the morning

---

**Q: How do I add a new vehicle type or commodity group?**

A: Admin only:
1. Go to Domain Management
2. Find the relevant section (Vehicle Types, Commodity Groups, etc.)
3. Click + Add
4. Enter name and save

---

**Q: What's the recommended way to handle emergency/unplanned services?**

A:
1. Create service record immediately when vehicle arrives
2. Tag issues appropriately
3. Admin can approve quickly
4. Change status to Ongoing to start work
5. Add services/materials as you go (can edit while Ongoing)
6. Complete when done

---

**Q: Can I undo completing a service?**

A: No. Once Completed, services are final because:
- Stock has been deducted
- Transaction records created
- Vehicle dates updated

If there's an error, create a correcting service or contact admin.

---

**Q: How do I handle warranty parts (no cost)?**

A: When adding materials to service:
- Add the item normally
- If admin wants to track warranty separately, create a special "Warranty" item in Item Master with cost = 0
- Or note in service comments/issues

---

**Q: What information do customers see about costs?**

A: Customers can see in their PMS History:
- Total service cost
- Services performed (with costs)
- Materials used (with costs)
- Historical cost tracking

This provides transparency for maintenance expenses.

---

### 8.11 Getting Additional Help

**For Technical Issues:**
- Email: caltexautopro2026@gmail.com
- Include:
  - Your name and role
  - Description of the problem
  - Screenshots if possible
  - What you were trying to do
  - Error messages you received

**For Account Issues:**
- Contact system administrator
- Provide your email and describe issue

**For Training:**
- Request training session from admin
- Refer to this user manual
- Practice in test environment if available

---

## System Requirements

### Website
- **Browser:** Chrome 90+, Firefox 88+, Edge 90+, Safari 14+
- **Connection:** Stable broadband internet (minimum 1 Mbps)
- **Display:** 1024x768 minimum resolution (1920x1080 recommended)
- **JavaScript:** Must be enabled
- **Cookies:** Must be enabled for login

### Mobile App
- **Android:** Version 6.0 (Marshmallow) or higher
- **iOS:** Version 13.0 or higher
- **Storage:** Minimum 50 MB available
- **Permissions Required:**
  - Camera (for barcode scanning)
  - Notifications (for push alerts)
  - Internet (WiFi or mobile data)

### Recommended Hardware
- **Desktop/Laptop:** 4GB RAM, modern processor
- **Mobile:** Mid-range smartphone (2018 or newer)
- **Network:** 4G/LTE or WiFi for mobile, broadband for desktop

---

## Best Practices Summary

### For Admin:
✅ Review dashboard every morning
✅ Generate DSS alerts daily
✅ Approve services promptly
✅ Monitor low stock and order proactively
✅ Keep user accounts current (deactivate leavers)
✅ Review PMS overdue list weekly
✅ Export reports monthly for records

### For Staff:
✅ Create service records immediately when vehicles arrive
✅ Use barcode scanner for speed and accuracy
✅ Verify stock before promising services to customers
✅ Update odometer readings after every service
✅ Mark services Completed promptly
✅ Report urgent stock needs to admin immediately
✅ Double-check materials before completing services

### For Customers:
✅ Check dashboard weekly
✅ Enable push notifications
✅ Respond to PMS due alerts promptly
✅ Book appointments in advance
✅ Keep contact information current
✅ Review maintenance history before service
✅ Budget for regular preventive maintenance

### For All Users:
✅ Keep passwords secure and unique
✅ Log out on shared devices
✅ Report suspicious activity immediately
✅ Keep app updated to latest version
✅ Verify data before submitting
✅ Use search functions to save time
✅ Read notifications regularly

---

## Glossary

**PMS (Preventive Maintenance Schedule):** Regular maintenance performed at scheduled intervals to prevent breakdowns.

**Item Master:** Central catalog of all items (materials and services) in the system.

**Stock Inventory:** List of physical materials with quantities on hand.

**UOM (Unit of Measure):** How items are counted (Liter, Piece, Set, Kilogram, etc.).

**Commodity Group:** Category classification for items (Lubricants, Filters, Parts, etc.).

**Service Rendered:** Labor or service performed on a vehicle (Oil Change, Brake Repair, etc.).

**Material Used:** Physical parts or supplies consumed during service.

**Issuance:** Record of materials issued/consumed during a service.

**Consumption Rate:** Average daily usage of an item based on service history.

**DSS (Decision Support System):** Analytical tool providing data-driven recommendations.

**Odometer:** Mileage reading on vehicle dashboard.

**Service Frequency:** How often vehicle should receive PMS (usually measured in months).

**Pending Status:** Service awaiting admin approval.

**Ongoing Status:** Service approved and in progress.

**Completed Status:** Service finished; stock deducted and records finalized.

**Low Stock:** Item quantity below minimum threshold.

**Overdue:** Vehicle past its PMS due date.

**Push Notification:** Real-time mobile alert.

**Barcode/QR Code:** Scannable code for quick item identification.

---

## Contact & Support

**System Support:**
- Email: caltexautopro2026@gmail.com
- Response Time: Within 24 hours (business days)

**For Emergencies:**
- Contact your system administrator directly
- Critical issues will be prioritized

**Feedback & Suggestions:**
- We welcome your feedback to improve the system
- Email suggestions to: caltexautopro2026@gmail.com

**Training Requests:**
- Request additional training sessions from admin
- Group training available for new staff
- One-on-one sessions for specific features

---

## Version History

**Version 1.0** — Initial release
- Core inventory, vehicle, and maintenance features
- User management
- Decision Support System
- Smart Reports AI
- Mobile app for Android and iOS
- Push notifications

---

## Acknowledgments

**Developed By:** JA Noble Enterprise INC
**In Partnership With:** Caltex Philippines
**Development Year:** 2026

This system was designed to streamline automotive service operations and provide transparency to customers through modern technology.

---

*© 2026 JA Noble Enterprise INC. All rights reserved.*

**End of User Manual**

---

**Quick Reference Card**

| Task | Admin | Staff | Customer |
|------|-------|-------|----------|
| View Dashboard | ✅ | ✅ | ✅ |
| Add Items to Item Master | ✅ | ❌ | ❌ |
| Add Items to Stock | ✅ | ❌ | ❌ |
| Receive Stock | ✅ | ✅ | ❌ |
| Register Vehicles | ✅ | ✅ | ❌ |
| Create Services | ✅ | ✅ | ❌ |
| Approve Services | ✅ | ❌ | ❌ |
| Complete Services | ✅ | ✅ | ❌ |
| Manage Users | ✅ | ❌ | ❌ |
| View DSS | ✅ | ❌ | ❌ |
| Generate Alerts | ✅ | ❌ | ❌ |
| Use Smart Reports/AI | ✅ | ✅ | ✅ |
| View Issuances | ✅ | ✅ | ❌ |
| View Transactions | ✅ | ✅ | ❌ |
| View Own PMS History | ✅ | ✅ | ✅ |
| Book Service Appointment | ❌ | ❌ | ✅ |
| View My Bookings | ❌ | ❌ | ✅ |
| Manage Service Bookings | ✅ | ❌ | ❌ |
| Scan Barcodes (Mobile) | ✅ | ✅ | ❌ |
| Access Archive | ✅ | ❌ | ❌ |
| Domain Management | ✅ | ❌ | ❌ |

---

**For quick help, press Ctrl+F and search for your question or topic.**
