"""
Check Firebase Cloud Functions logs to verify sendNotifications is working
"""
import subprocess
import sys

print("\n" + "="*60)
print("🔍 CHECKING CLOUD FUNCTIONS LOGS")
print("="*60)

print("\n📋 Fetching recent logs from sendNotifications function...")
print("   This will show if the function triggered and sent push notifications")

try:
    result = subprocess.run(
        ['firebase', 'functions:log', '--only', 'sendNotifications', '--limit', '10'],
        cwd=r'c:\Project\AUTOMOTIVE_SERVICE\automotive_mobile',
        capture_output=True,
        text=True,
        timeout=30
    )
    
    if result.returncode == 0:
        print("\n" + "="*60)
        print("📄 RECENT LOGS:")
        print("="*60)
        print(result.stdout)
        
        # Check for success indicators
        if "Notifications sent to" in result.stdout:
            print("\n✅ SUCCESS! Push notifications are being sent via OneSignal!")
        elif "Error" in result.stdout or "error" in result.stdout:
            print("\n❌ ERRORS FOUND in logs - check details above")
        else:
            print("\n⚠️ No clear success/error messages - function may not have triggered yet")
            print("   Wait 1-2 minutes and check again")
    else:
        print(f"\n❌ Failed to fetch logs: {result.stderr}")
        print("\n💡 ALTERNATIVE: Check logs in Firebase Console:")
        print("   https://console.firebase.google.com/project/caltex-autopro-1e664/functions/logs")
        
except subprocess.TimeoutExpired:
    print("\n⏱️ Command timed out")
except FileNotFoundError:
    print("\n❌ Firebase CLI not found in PATH")
except Exception as e:
    print(f"\n❌ Error: {e}")

print("\n" + "="*60)
print("🔗 VIEW LOGS IN FIREBASE CONSOLE:")
print("="*60)
print("   https://console.firebase.google.com/project/caltex-autopro-1e664/functions/logs")
print("\n   Filter by: sendNotifications")
print("   Look for: 'Notifications sent to X users via OneSignal'")
print()
