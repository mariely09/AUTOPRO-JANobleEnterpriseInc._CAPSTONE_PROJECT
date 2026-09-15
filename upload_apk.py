"""
Upload APK to Firebase Storage with chunked upload
"""
import os
import sys
from dotenv import load_dotenv
import firebase_admin
from firebase_admin import credentials, storage
from google.cloud.storage import transfer_manager

# Load environment
load_dotenv()

# Initialize Firebase
cred_path = os.getenv('FIREBASE_CREDENTIALS_PATH')
if not cred_path or not os.path.exists(cred_path):
    print("❌ ERROR: FIREBASE_CREDENTIALS_PATH not found in .env")
    sys.exit(1)

if not firebase_admin._apps:
    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred, {
        'storageBucket': 'caltex-autopro-1e664.firebasestorage.app'
    })

# Upload APK
apk_path = 'automotive_mobile/build/app/outputs/flutter-apk/app-release.apk'
if not os.path.exists(apk_path):
    print(f"❌ APK not found: {apk_path}")
    sys.exit(1)

# Get file size
file_size_mb = os.path.getsize(apk_path) / (1024 * 1024)
print(f"📦 APK size: {file_size_mb:.2f} MB")

# Upload with chunked upload (faster for large files)
print(f"⬆️  Uploading to Firebase Storage...")
print(f"   Using chunked upload for better reliability...")

bucket = storage.bucket()
blob = bucket.blob('autopro.apk')

# Use chunked upload with 8MB chunks
blob.chunk_size = 8 * 1024 * 1024  # 8MB chunks

try:
    blob.upload_from_filename(
        apk_path, 
        content_type='application/vnd.android.package-archive',
        timeout=600  # 10 minutes timeout
    )
    
    # Make public
    print(f"🔓 Making file public...")
    blob.make_public()
    
    print(f"\n✅ Upload complete!")
    print(f"📱 Download URL: {blob.public_url}")
    print(f"🔗 Direct link: https://storage.googleapis.com/caltex-autopro-1e664.firebasestorage.app/autopro.apk")
    print(f"\n📊 File info:")
    print(f"   - Size: {file_size_mb:.2f} MB")
    print(f"   - Name: autopro.apk")
    print(f"   - Type: Android APK")
    
except Exception as e:
    print(f"\n❌ Upload failed: {e}")
    print(f"\nPlease try manual upload via Firebase Console:")
    print(f"https://console.firebase.google.com/project/caltex-autopro-1e664/storage")
    sys.exit(1)
