"""
DSS Push Notifications Test Script
Tests Stock Replenishment and PMS Scheduling alerts

Prerequisites:
1. Firebase Admin SDK credentials (.env file with FIREBASE_CREDENTIALS_PATH)
2. Mobile app installed with OneSignal configured
3. Admin account logged in on mobile device

Usage:
    python test_dss_notifications.py --test stock
    python test_dss_notifications.py --test pms
    python test_dss_notifications.py --test all
    python test_dss_notifications.py --cleanup
"""

import os
import sys
import json
import argparse
from datetime import datetime, timedelta
from dotenv import load_dotenv
import firebase_admin
from firebase_admin import credentials, firestore

# Load environment variables
load_dotenv()

# Initialize Firebase
cred_path = os.getenv('FIREBASE_CREDENTIALS_PATH')
if not cred_path or not os.path.exists(cred_path):
    print("❌ ERROR: FIREBASE_CREDENTIALS_PATH not found in .env")
    print("   Add: FIREBASE_CREDENTIALS_PATH=path/to/serviceAccountKey.json")
    sys.exit(1)

if not firebase_admin._apps:
    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)

db = firestore.client()

# Test data configuration
TEST_ITEM_NUM = "TEST-STOCK-001"
TEST_VEHICLE_PLATE = "TEST-ABC-123"
TEST_DATA_MARKER = "_DSS_TEST_DATA_"

class Colors:
    """ANSI color codes for terminal output"""
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'

def print_header(text):
    print(f"\n{Colors.HEADER}{Colors.BOLD}{'='*60}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{text.center(60)}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{'='*60}{Colors.ENDC}\n")

def print_success(text):
    print(f"{Colors.GREEN}✅ {text}{Colors.ENDC}")

def print_error(text):
    print(f"{Colors.RED}❌ {text}{Colors.ENDC}")

def print_info(text):
    print(f"{Colors.CYAN}ℹ️  {text}{Colors.ENDC}")

def print_warning(text):
    print(f"{Colors.YELLOW}⚠️  {text}{Colors.ENDC}")

def print_step(num, text):
    print(f"{Colors.BLUE}{Colors.BOLD}STEP {num}:{Colors.ENDC} {text}")


def setup_stock_test_data():
    """Create test data for stock replenishment alerts"""
    print_step(1, "Setting up Stock Replenishment test data...")
    
    try:
        # Create a test item with zero stock
        test_item = {
            'num': TEST_ITEM_NUM,
            'name': f'Test Item {TEST_DATA_MARKER}',
            'description': 'Test item for DSS notification testing',
            'stock': 0,  # Out of stock - triggers critical alert
            'min': 10,
            'max': 50,
            'reorder': 20,
            'uom': 'pcs',
            'category': 'Test',
            'price': 100.00,
            'supplier': 'Test Supplier',
            'createdAt': firestore.SERVER_TIMESTAMP,
            'updatedAt': firestore.SERVER_TIMESTAMP,
            '_test_marker': TEST_DATA_MARKER
        }
        
        db.collection('stock_inventory').document(TEST_ITEM_NUM).set(test_item)
        print_success(f"Created test item: {TEST_ITEM_NUM}")
        print_info(f"   Name: {test_item['name']}")
        print_info(f"   Stock: {test_item['stock']} (OUT OF STOCK)")
        print_info(f"   Min: {test_item['min']}, Max: {test_item['max']}, Reorder: {test_item['reorder']}")
        
        return True
    except Exception as e:
        print_error(f"Failed to create test data: {e}")
        return False


def setup_pms_test_data():
    """Create test data for PMS scheduling alerts"""
    print_step(1, "Setting up PMS Scheduling test data...")
    
    try:
        # Create a test vehicle with overdue maintenance
        today = datetime.now()
        overdue_date = (today - timedelta(days=30)).strftime('%Y-%m-%d')
        
        test_vehicle = {
            'plate': TEST_VEHICLE_PLATE,
            'brand': 'Test Brand',
            'model': 'Test Model',
            'year': 2020,
            'ownerId': 'test_owner',
            'ownerName': f'Test Owner {TEST_DATA_MARKER}',
            'serviceFrequency': 3,  # 3 months
            'nextPMS': overdue_date,  # 30 days overdue
            'lastService': (today - timedelta(days=120)).strftime('%Y-%m-%d'),
            'status': 'Active',
            'createdAt': firestore.SERVER_TIMESTAMP,
            'updatedAt': firestore.SERVER_TIMESTAMP,
            '_test_marker': TEST_DATA_MARKER
        }
        
        db.collection('vehicles').document(TEST_VEHICLE_PLATE).set(test_vehicle)
        print_success(f"Created test vehicle: {TEST_VEHICLE_PLATE}")
        print_info(f"   Owner: {test_vehicle['ownerName']}")
        print_info(f"   Next PMS: {overdue_date} (OVERDUE by 30 days)")
        print_info(f"   Service Frequency: {test_vehicle['serviceFrequency']} months")
        
        return True
    except Exception as e:
        print_error(f"Failed to create test data: {e}")
        return False


def delete_dedup_guard():
    """Delete today's dedup guard to allow re-sending alerts"""
    print_step(2, "Deleting deduplication guard...")
    
    try:
        today = datetime.now()
        today_key = today.strftime('%Y-%m-%d')
        
        doc_ref = db.collection('dss_alert_log').document(today_key)
        doc = doc_ref.get()
        
        if doc.exists:
            doc_ref.delete()
            print_success(f"Deleted dedup guard for {today_key}")
        else:
            print_info(f"No dedup guard found for {today_key} (already clear)")
        
        return True
    except Exception as e:
        print_error(f"Failed to delete dedup guard: {e}")
        return False


def trigger_dss_alerts():
    """Instructions for triggering DSS alerts"""
    print_step(3, "Triggering DSS alerts...")
    print()
    print_info("To trigger the alerts, you have TWO options:")
    print()
    print(f"{Colors.BOLD}OPTION A: Mobile App (Manual - RECOMMENDED){Colors.ENDC}")
    print("   1. Open AutoPro mobile app")
    print("   2. Login as Admin")
    print("   3. Go to: Menu → Decision Support System")
    print("   4. The alerts will trigger automatically when screen opens")
    print("   5. OR tap 'Generate Daily Alerts' button")
    print()
    print(f"{Colors.BOLD}OPTION B: Wait for Automatic (Cloud Function){Colors.ENDC}")
    print("   1. Wait for next hour (Cloud Function runs every hour)")
    print("   2. Example: If now is 2:30 PM, wait until 3:00 PM")
    print("   3. Alerts will automatically trigger")
    print()
    print(f"{Colors.BOLD}OPTION C: Web App{Colors.ENDC}")
    print("   1. Open web app: http://localhost:5000 (or your domain)")
    print("   2. Login as Admin")
    print("   3. Go to: Decision Support System")
    print("   4. Click 'Generate Daily Alerts' button")
    print()


def verify_notifications():
    """Check if notifications were sent"""
    print_step(4, "Verifying notifications...")
    print()
    
    try:
        # Check dss_alert_log
        today_key = datetime.now().strftime('%Y-%m-%d')
        doc = db.collection('dss_alert_log').document(today_key).get()
        
        if doc.exists:
            print_success("DSS alerts were triggered today")
            print_info(f"   Timestamp: {doc.to_dict().get('sentAt')}")
        else:
            print_warning("No alert log found for today - alerts not triggered yet")
        
        print()
        print(f"{Colors.BOLD}Expected Notifications on Mobile Device:{Colors.ENDC}")
        print()
        print(f"{Colors.RED}📱 Stock Alert:{Colors.ENDC}")
        print(f"   Title: 🚨 URGENT: Out of Stock")
        print(f"   Message: Test Item {TEST_DATA_MARKER} is out of stock. Immediate reorder needed.")
        print(f"   Action: Tap → Opens Stock Replenishment tab")
        print()
        print(f"{Colors.BLUE}📱 PMS Alert:{Colors.ENDC}")
        print(f"   Title: 🚗 PMS Overdue")
        print(f"   Message: {TEST_VEHICLE_PLATE} is overdue for maintenance")
        print(f"   Action: Tap → Opens PMS Scheduling tab")
        print()
        
    except Exception as e:
        print_error(f"Error checking notifications: {e}")


def cleanup_test_data():
    """Remove all test data"""
    print_header("CLEANUP: Removing Test Data")
    
    removed_count = 0
    
    try:
        # Remove test stock item
        stock_ref = db.collection('stock_inventory').document(TEST_ITEM_NUM)
        if stock_ref.get().exists:
            stock_ref.delete()
            print_success(f"Removed test stock item: {TEST_ITEM_NUM}")
            removed_count += 1
        
        # Remove test vehicle
        vehicle_ref = db.collection('vehicles').document(TEST_VEHICLE_PLATE)
        if vehicle_ref.get().exists:
            vehicle_ref.delete()
            print_success(f"Removed test vehicle: {TEST_VEHICLE_PLATE}")
            removed_count += 1
        
        # Find and remove any other test data with marker
        print_info("Scanning for other test data...")
        
        # Check stock_inventory
        stock_docs = db.collection('stock_inventory').where('_test_marker', '==', TEST_DATA_MARKER).get()
        for doc in stock_docs:
            doc.reference.delete()
            print_success(f"Removed test stock: {doc.id}")
            removed_count += 1
        
        # Check vehicles
        vehicle_docs = db.collection('vehicles').where('_test_marker', '==', TEST_DATA_MARKER).get()
        for doc in vehicle_docs:
            doc.reference.delete()
            print_success(f"Removed test vehicle: {doc.id}")
            removed_count += 1
        
        print()
        if removed_count > 0:
            print_success(f"Cleanup complete! Removed {removed_count} test items")
        else:
            print_info("No test data found to remove")
            
    except Exception as e:
        print_error(f"Cleanup error: {e}")


def test_stock_replenishment():
    """Run stock replenishment notification test"""
    print_header("TEST: Stock Replenishment Alerts")
    
    if not setup_stock_test_data():
        return False
    
    if not delete_dedup_guard():
        return False
    
    trigger_dss_alerts()
    verify_notifications()
    
    print()
    print_warning("Don't forget to run cleanup after testing:")
    print(f"   {Colors.BOLD}python test_dss_notifications.py --cleanup{Colors.ENDC}")
    
    return True


def test_pms_scheduling():
    """Run PMS scheduling notification test"""
    print_header("TEST: PMS Scheduling Alerts")
    
    if not setup_pms_test_data():
        return False
    
    if not delete_dedup_guard():
        return False
    
    trigger_dss_alerts()
    verify_notifications()
    
    print()
    print_warning("Don't forget to run cleanup after testing:")
    print(f"   {Colors.BOLD}python test_dss_notifications.py --cleanup{Colors.ENDC}")
    
    return True


def test_all():
    """Run all tests"""
    print_header("TEST: All DSS Alerts (Stock + PMS)")
    
    success = True
    
    if not setup_stock_test_data():
        success = False
    
    print()
    
    if not setup_pms_test_data():
        success = False
    
    print()
    
    if not delete_dedup_guard():
        success = False
    
    if success:
        print()
        trigger_dss_alerts()
        verify_notifications()
        
        print()
        print_warning("Don't forget to run cleanup after testing:")
        print(f"   {Colors.BOLD}python test_dss_notifications.py --cleanup{Colors.ENDC}")
    
    return success


def main():
    parser = argparse.ArgumentParser(
        description='Test DSS Push Notifications',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python test_dss_notifications.py --test stock    # Test stock alerts only
  python test_dss_notifications.py --test pms      # Test PMS alerts only
  python test_dss_notifications.py --test all      # Test both
  python test_dss_notifications.py --cleanup       # Remove test data
        """
    )
    
    parser.add_argument(
        '--test',
        choices=['stock', 'pms', 'all'],
        help='Type of test to run'
    )
    
    parser.add_argument(
        '--cleanup',
        action='store_true',
        help='Remove all test data'
    )
    
    args = parser.parse_args()
    
    if args.cleanup:
        cleanup_test_data()
    elif args.test == 'stock':
        test_stock_replenishment()
    elif args.test == 'pms':
        test_pms_scheduling()
    elif args.test == 'all':
        test_all()
    else:
        parser.print_help()
        print()
        print_info("Quick start: python test_dss_notifications.py --test all")


if __name__ == '__main__':
    main()
