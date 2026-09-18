"""
Upload newly built APK with notification icon update to Firebase Storage
"""
import firebase_admin
from firebase_admin import credentials, storage
import os

print("\n" + "="*60)
print("📤 UPLOADING NEW APK TO FIREBASE STORAGE")
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

# APK file path
apk_path = r'c:\Project\AUTOMOTIVE_SERVICE\automotive_mobile\build\app\outputs\flutter-apk\app-release.apk'

if not os.path.exists(apk_path):
    print(f"❌ APK file not found at: {apk_path}")
    print("   Run: flutter build apk --release")
    exit(1)

apk_size_mb = os.path.getsize(apk_path) / (1024 * 1024)
print(f"\n📁 Found APK file:")
print(f"   Path: {apk_path}")
print(f"   Size: {apk_size_mb:.2f} MB")

# Upload to Firebase Storage
print(f"\n📤 Uploading to Firebase Storage... (this may take a few minutes for {apk_size_mb:.0f}MB file)")
print("   Please wait...")

blob = bucket.blob('autopro.apk')

# Upload file with longer timeout for large APK
import google.api_core.retry as retry_module
retry_strategy = retry_module.Retry(
    initial=1.0,
    maximum=60.0,
    multiplier=2.0,
    deadline=600.0,  # 10 minutes timeout
    predicate=retry_module.if_exception_type(
        Exception,  # Retry on any exception
    )
)

blob.upload_from_filename(
    apk_path, 
    content_type='application/vnd.android.package-archive',
    timeout=600,  # 10 minutes
    retry=retry_strategy
)

print("\n🔓 Making file publicly accessible...")
blob.make_public()

# Get public URL
public_url = blob.public_url

# Get metadata token
blob.reload()
token_url = None
if hasattr(blob, 'metadata') and blob.metadata and 'firebaseStorageDownloadTokens' in blob.metadata:
    token = blob.metadata['firebaseStorageDownloadTokens']
    token_url = f"https://firebasestorage.googleapis.com/v0/b/caltex-autopro-1e664.firebasestorage.app/o/autopro.apk?alt=media&token={token}"

print("\n" + "="*60)
print("✅ UPLOAD SUCCESSFUL!")
print("="*60)
print(f"📍 File Location: gs://caltex-autopro-1e664.firebasestorage.app/autopro.apk")
print(f"📦 Size: {apk_size_mb:.2f} MB")
print(f"\n🌐 Download URLs:")
if token_url:
    print(f"   {token_url}")
else:
    print(f"   {public_url}")
print("="*60)

print("\n📱 WHAT'S NEW IN THIS APK:")
print("   ✅ Notification icon = AutoPro logo")
print("   ✅ Small icon in status bar = AutoPro icon")
print("   ✅ Large icon in notification = AutoPro logo")
print("   ✅ Notification accent color = AutoPro red")

print("\n📋 Next Steps:")
print("   1. ✅ APK uploaded to Firebase Storage")
print("   2. ✅ QR code on website will download this new APK")
print("   3. ⏳ Deploy Cloud Functions: firebase deploy --only functions")
print("   4. ⏳ Test: Scan QR code and install APK")
print("   5. ⏳ Test: Send push notification and check icon")
print()
