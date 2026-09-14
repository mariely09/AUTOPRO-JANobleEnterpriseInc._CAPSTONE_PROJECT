"""
Upload AutoPro logo to Firebase Storage for push notifications
"""
import firebase_admin
from firebase_admin import credentials, storage
import os

print("\n" + "="*60)
print("📤 UPLOADING AUTOPRO LOGO TO FIREBASE STORAGE")
print("="*60)

# Initialize Firebase
service_key_path = os.path.join(os.path.dirname(__file__), 'ai_assistant', 'serviceAccountKey.json')
cred = credentials.Certificate(service_key_path)

try:
    app = firebase_admin.get_app()
    print("✅ Using existing Firebase app")
except ValueError:
    app = firebase_admin.initialize_app(cred, {
        'storageBucket': 'caltex-autopro-1e664.firebasestorage.app'
    })
    print("✅ Initialized Firebase app with Storage")

# Get Storage bucket
bucket = storage.bucket()

# Logo file path
logo_path = r'c:\Project\AUTOMOTIVE_SERVICE\automotive_website\static\img\LOGO_AUTOPRO.png'

if not os.path.exists(logo_path):
    print(f"❌ Logo file not found at: {logo_path}")
    exit(1)

print(f"\n📁 Found logo file:")
print(f"   Path: {logo_path}")
print(f"   Size: {os.path.getsize(logo_path) / 1024:.2f} KB")

# Upload to Firebase Storage
print("\n📤 Uploading to Firebase Storage...")
blob = bucket.blob('autopro_logo.png')

# Upload file
blob.upload_from_filename(logo_path, content_type='image/png')

# Make it publicly accessible
blob.make_public()

# Get public URL
public_url = blob.public_url

print("\n✅ UPLOAD SUCCESSFUL!")
print("="*60)
print(f"📍 File Location: gs://caltex-autopro-1e664.firebasestorage.app/autopro_logo.png")
print(f"🌐 Public URL: {public_url}")
print("="*60)

print("\n🔗 Alternative URL (with token):")
# Get download URL with token
blob.reload()
if blob.metadata and 'firebaseStorageDownloadTokens' in blob.metadata:
    token = blob.metadata['firebaseStorageDownloadTokens']
    alt_url = f"https://firebasestorage.googleapis.com/v0/b/caltex-autopro-1e664.firebasestorage.app/o/autopro_logo.png?alt=media&token={token}"
    print(f"   {alt_url}")
else:
    print(f"   {public_url}")

print("\n✅ Logo is now ready for push notifications!")
print("\n📋 Next Steps:")
print("   1. ✅ Logo uploaded to Firebase Storage")
print("   2. ⏳ Rebuild APK: flutter build apk --release")
print("   3. ⏳ Deploy Cloud Functions: firebase deploy --only functions")
print("   4. ⏳ Test push notification")
print()
