"""
Test push notification speed - measure end-to-end timing
"""
import firebase_admin
from firebase_admin import credentials, firestore
from datetime import datetime
import os
import time

# Initialize Firebase
service_key_path = os.path.join(os.path.dirname(__file__), 'ai_assistant', 'serviceAccountKey.json')
cred = credentials.Certificate(service_key_path)

try:
    app = firebase_admin.get_app()
except ValueError:
    app = firebase_admin.initialize_app(cred)

db = firestore.client()

print("\n" + "="*60)
print("PUSH NOTIFICATION SPEED TEST")
print("="*60)

# Get a customer
customers = db.collection('users').where('role', '==', 'customer').limit(1).get()
if not customers:
    print("No customers found")
    exit(1)

customer = customers[0]
customer_id = customer.id
customer_data = customer.to_dict()
customer_name = f"{customer_data.get('firstName', '')} {customer_data.get('lastName', '')}"

print(f"\nTarget: {customer_name} ({customer_id})")
print(f"Current time: {datetime.now().strftime('%H:%M:%S.%f')[:-3]}")

# Create notification with timestamp
start_time = time.time()
print(f"\nCreating notification at: {datetime.now().strftime('%H:%M:%S.%f')[:-3]}")

notification_data = {
    'title': 'SPEED TEST - Check Time',
    'message': f'Sent at {datetime.now().strftime("%H:%M:%S")} - Check how long to receive!',
    'type': 'info',
    'targetRole': '',
    'targetUid': customer_id,
    'createdAt': firestore.SERVER_TIMESTAMP,
    'readBy': {},
    'isRead': False,
}

doc_ref = db.collection('notifications').add(notification_data)
notification_id = doc_ref[1].id
firestore_time = time.time() - start_time

print(f"Firestore write completed: {firestore_time:.2f}s")
print(f"Notification ID: {notification_id}")

print("\n" + "="*60)
print("TIMING BREAKDOWN:")
print("="*60)
print(f"1. Firestore write: {firestore_time:.2f}s")
print(f"2. Cloud Function trigger: ~1-2s (estimated)")
print(f"3. OneSignal send: ~1-2s (estimated)")
print(f"4. Device receive: Instant")
print(f"\nEXPECTED TOTAL: ~2-5 seconds")

print("\n" + "="*60)
print("ACTION REQUIRED:")
print("="*60)
print("1. Note current time on YOUR device")
print("2. Wait for notification to arrive")
print("3. Check time shown in notification")
print("4. Calculate: (Arrival time - Sent time) = Delay")
print()
print("EXPECTED: 2-5 seconds delay")
print("IF LONGER: Check internet, battery settings, or OneSignal dashboard")
print()
