"""
Test Push Notification System
This script creates a test notification in Firestore which will trigger
the Cloud Function to send a push notification via OneSignal.
"""

import firebase_admin
from firebase_admin import credentials, firestore
from datetime import datetime
import sys
import os

# Add ai_assistant to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'ai_assistant'))

# Initialize Firebase
try:
    # Try to get existing app
    app = firebase_admin.get_app()
    print("✅ Using existing Firebase app")
except ValueError:
    # Initialize new app
    service_key_path = os.path.join(os.path.dirname(__file__), 'ai_assistant', 'serviceAccountKey.json')
    cred = credentials.Certificate(service_key_path)
    app = firebase_admin.initialize_app(cred)
    print("✅ Initialized new Firebase app")

db = firestore.client()

print("\n" + "="*60)
print("🧪 PUSH NOTIFICATION TEST")
print("="*60)

# Get first customer user for testing
print("\n1️⃣ Finding a customer user to send test notification...")
users_ref = db.collection('users')
customers = users_ref.where('role', '==', 'customer').limit(5).get()

if not customers:
    print("❌ No customer users found in database")
    print("   Please create a customer account first")
    sys.exit(1)

print(f"\n✅ Found {len(customers)} customer(s):")
for idx, customer in enumerate(customers, 1):
    data = customer.to_dict()
    print(f"   {idx}. {data.get('firstName', '')} {data.get('lastName', '')} ({customer.id})")

# Use first customer
test_customer = customers[0]
customer_data = test_customer.to_dict()
customer_id = test_customer.id
customer_name = f"{customer_data.get('firstName', '')} {customer_data.get('lastName', '')}"

print(f"\n2️⃣ Using customer: {customer_name}")
print(f"   Customer ID: {customer_id}")

# Get one of their vehicles if available
print("\n3️⃣ Looking for customer's vehicle...")
vehicles_ref = db.collection('vehicles')
vehicles = vehicles_ref.where('ownerId', '==', customer_id).limit(1).get()

if vehicles:
    vehicle_data = vehicles[0].to_dict()
    plate = vehicle_data.get('plate', 'TEST-123')
    print(f"   ✅ Found vehicle: {plate}")
else:
    plate = "TEST-123"
    print(f"   ⚠️ No vehicle found, using placeholder: {plate}")

# Create test notification
print("\n4️⃣ Creating test notification in Firestore...")
print("   This will trigger the Cloud Function to send push notification")

notification_data = {
    'title': '🧪 TEST: Service Completed',
    'message': f'Your vehicle {plate} has been serviced and is ready for pickup. This is a test notification.',
    'type': 'success',
    'targetRole': '',
    'targetUid': customer_id,
    'createdAt': firestore.SERVER_TIMESTAMP,
    'readBy': {},
    'isRead': False,
}

try:
    doc_ref = db.collection('notifications').add(notification_data)
    notification_id = doc_ref[1].id
    print(f"   ✅ Notification created with ID: {notification_id}")
except Exception as e:
    print(f"   ❌ Failed to create notification: {e}")
    sys.exit(1)

# Wait a moment for Cloud Function to process
print("\n5️⃣ Waiting for Cloud Function to process...")
import time
time.sleep(3)

print("\n" + "="*60)
print("✅ TEST COMPLETED!")
print("="*60)
print("\n📱 CHECK THE FOLLOWING:")
print(f"   1. Customer's device: {customer_name}")
print(f"      Should receive: '🧪 TEST: Service Completed'")
print(f"\n   2. Firebase Console → Firestore → notifications")
print(f"      Document ID: {notification_id}")
print(f"\n   3. Firebase Console → Functions → Logs")
print(f"      Look for: 'Notifications sent to X users via OneSignal'")
print(f"\n   4. OneSignal Dashboard → Delivery")
print(f"      Look for message with title: '🧪 TEST: Service Completed'")

print("\n" + "="*60)
print("🎯 WHAT TO DO NEXT:")
print("="*60)
print("   • If push received: ✅ System is working!")
print("   • If NOT received:")
print("     - Check if customer granted notification permission")
print("     - Check OneSignal 'Subscribed' status (must be green)")
print("     - Check Cloud Functions logs for errors")
print("     - Check device notification settings")
print("\n")

# Also create a notification for ALL subscribed users
print("="*60)
print("🔔 BONUS: Sending to ALL users (testing broadcast)")
print("="*60)

broadcast_data = {
    'title': '🧪 TEST: System Announcement',
    'message': 'This is a test broadcast notification to all users. Please ignore.',
    'type': 'info',
    'targetRole': '',  # Empty = all users
    'targetUid': '',   # Empty = all users
    'createdAt': firestore.SERVER_TIMESTAMP,
    'readBy': {},
    'isRead': False,
}

try:
    doc_ref = db.collection('notifications').add(broadcast_data)
    broadcast_id = doc_ref[1].id
    print(f"✅ Broadcast notification created with ID: {broadcast_id}")
    print(f"   This will be sent to ALL subscribed users")
except Exception as e:
    print(f"❌ Failed to create broadcast: {e}")

print("\n✅ All tests completed!\n")
