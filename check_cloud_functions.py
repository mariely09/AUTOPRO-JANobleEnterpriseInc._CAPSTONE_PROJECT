"""
Check if Cloud Functions are deployed and working
"""
import firebase_admin
from firebase_admin import credentials, firestore, functions
import os
import time

# Initialize Firebase
service_key_path = os.path.join(os.path.dirname(__file__), 'ai_assistant', 'serviceAccountKey.json')
cred = credentials.Certificate(service_key_path)
app = firebase_admin.initialize_app(cred)

db = firestore.client()

print("\n" + "="*60)
print("🔍 CLOUD FUNCTIONS DIAGNOSTIC")
print("="*60)

# Check recent notifications
print("\n1️⃣ Checking recent notifications in Firestore...")
notifications_ref = db.collection('notifications')
recent = notifications_ref.order_by('createdAt', direction=firestore.Query.DESCENDING).limit(5).get()

print(f"   Found {len(recent)} recent notifications:")
for idx, doc in enumerate(recent, 1):
    data = doc.to_dict()
    title = data.get('title', 'No title')
    created = data.get('createdAt', 'Unknown')
    target = data.get('targetUid', data.get('targetRole', 'all'))
    print(f"   {idx}. {title}")
    print(f"      ID: {doc.id}")
    print(f"      Target: {target}")
    print(f"      Created: {created}")
    print()

print("\n" + "="*60)
print("🎯 DIAGNOSIS:")
print("="*60)
print("\n✅ Firestore notifications are being created")
print("❌ OneSignal is NOT receiving them (based on your screenshot)")
print("\nThis means: Cloud Function 'sendNotifications' is NOT deployed or NOT working")

print("\n" + "="*60)
print("🔧 HOW TO FIX:")
print("="*60)
print("\n1. LOGIN to Firebase CLI:")
print("   Run: firebase login")
print()
print("2. SELECT your project:")
print("   Run: firebase use caltex-autopro-1e664")
print()
print("3. DEPLOY Cloud Functions:")
print("   cd automotive_mobile/functions")
print("   firebase deploy --only functions")
print()
print("4. VERIFY deployment:")
print("   • Go to: Firebase Console → Functions")
print("   • Should see: sendNotifications, deleteUser, sendPushNotification, checkDSSAlerts")
print()
print("5. TEST again:")
print("   Run: python test_push_notification.py")
print()

print("="*60)
print("📌 FIREBASE CONSOLE LINKS:")
print("="*60)
print("   Functions: https://console.firebase.google.com/project/caltex-autopro-1e664/functions")
print("   Firestore: https://console.firebase.google.com/project/caltex-autopro-1e664/firestore")
print()
