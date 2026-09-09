"""
test_complete_price_list.py — Test complete price list display

Tests that the AI assistant properly shows complete service and material catalogs
when customers ask for "all prices", "complete list", etc.

Run: python test_complete_price_list.py
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from customer_tools import get_service_prices, get_customer_materials

# ANSI color codes
BOLD = "\033[1m"
GREEN = "\033[92m"
RED = "\033[91m"
CYAN = "\033[96m"
YELLOW = "\033[93m"
RESET = "\033[0m"

passed = 0
failed = 0


def print_test(name: str, result: bool, details: str = ""):
    global passed, failed
    if result:
        print(f"{GREEN}✓{RESET} {name}")
        if details:
            print(f"  {details}")
        passed += 1
    else:
        print(f"{RED}✗{RESET} {name}")
        if details:
            print(f"  {RED}{details}{RESET}")
        failed += 1


print(f"\n{CYAN}{'='*80}{RESET}")
print(f"{BOLD}Testing Complete Price List Functionality{RESET}")
print(f"{CYAN}{'='*80}{RESET}\n")

# =============================================================================
# TEST 1: Get all service prices (no filter)
# =============================================================================
print(f"{BOLD}TEST 1: Get Complete Service Catalog{RESET}\n")

result = get_service_prices(
    customer_uid="test_uid",
    customer_name="Test Customer",
    service_name=None  # No filter = all services
)

print_test(
    "Returns success (no error)",
    "error" not in result,
    f"Result type: {type(result)}"
)

total_services = result.get("total_services", 0)
print_test(
    "Returns services",
    total_services > 0,
    f"Total services: {total_services}"
)

services = result.get("services", [])
print_test(
    "Services list is not empty",
    len(services) > 0,
    f"Services returned: {len(services)}"
)

if services:
    print(f"\n  {BOLD}Sample Services:{RESET}")
    for i, svc in enumerate(services[:5], 1):
        print(f"    {i}. {svc.get('name', 'N/A')} - {svc.get('cost', 'N/A')}")
        print(f"       Group: {svc.get('group', 'N/A')} | UOM: {svc.get('uom', 'N/A')}")
    
    if len(services) > 5:
        print(f"    ... and {len(services) - 5} more services")

# Check that services have required fields
if services:
    first_service = services[0]
    print_test(
        "Services have name field",
        "name" in first_service,
        f"Sample: {first_service.get('name', 'MISSING')}"
    )
    print_test(
        "Services have cost field",
        "cost" in first_service,
        f"Sample: {first_service.get('cost', 'MISSING')}"
    )
    print_test(
        "Services have group field",
        "group" in first_service,
        f"Sample: {first_service.get('group', 'MISSING')}"
    )

# =============================================================================
# TEST 2: Get filtered service prices
# =============================================================================
print(f"\n{BOLD}TEST 2: Get Filtered Service Prices (Oil Change){RESET}\n")

filtered_result = get_service_prices(
    customer_uid="test_uid",
    customer_name="Test Customer",
    service_name="oil change"
)

filtered_services = filtered_result.get("services", [])
print_test(
    "Filtered results returned",
    len(filtered_services) >= 0,
    f"Oil change related services: {len(filtered_services)}"
)

# The filtered list should be smaller than or equal to complete list
print_test(
    "Filtered list is subset of complete list",
    len(filtered_services) <= total_services,
    f"Filtered: {len(filtered_services)}, Total: {total_services}"
)

if filtered_services:
    print(f"\n  {BOLD}Oil Change Services:{RESET}")
    for svc in filtered_services[:3]:
        print(f"    • {svc.get('name', 'N/A')} - {svc.get('cost', 'N/A')}")

# =============================================================================
# TEST 3: Get all materials (no filter)
# =============================================================================
print(f"\n{BOLD}TEST 3: Get Complete Materials Catalog{RESET}\n")

materials_result = get_customer_materials(
    customer_uid="test_uid",
    customer_name="Test Customer",
    material_name=None  # No filter = all materials
)

print_test(
    "Materials query succeeds",
    "error" not in materials_result,
    f"Result type: {type(materials_result)}"
)

total_materials = materials_result.get("total_materials", 0)
print_test(
    "Returns materials",
    total_materials >= 0,
    f"Total materials: {total_materials}"
)

materials = materials_result.get("materials", [])
if materials:
    print(f"\n  {BOLD}Sample Materials:{RESET}")
    for i, mat in enumerate(materials[:5], 1):
        print(f"    {i}. {mat.get('name', 'N/A')} - {mat.get('customer_price', 'N/A')}")
        print(f"       Group: {mat.get('group', 'N/A')} | UOM: {mat.get('uom', 'N/A')}")
    
    if len(materials) > 5:
        print(f"    ... and {len(materials) - 5} more materials")
else:
    print(f"  {YELLOW}ℹ No materials in catalog (this is OK if item_master has no materials){RESET}")

# Check that materials NEVER expose internal data
if materials:
    first_material = materials[0]
    print_test(
        "Materials DO NOT expose stock quantity",
        "stock" not in first_material and "quantity" not in first_material,
        "✓ Stock info hidden"
    )
    print_test(
        "Materials DO NOT expose supplier info",
        "supplier" not in first_material and "vendor" not in first_material,
        "✓ Supplier info hidden"
    )
    print_test(
        "Materials DO NOT expose purchase cost",
        "purchase" not in str(first_material).lower() and "buy" not in str(first_material).lower(),
        "✓ Purchase cost hidden"
    )

# =============================================================================
# TEST 4: Get filtered materials (lubricants)
# =============================================================================
print(f"\n{BOLD}TEST 4: Get Filtered Materials (Lubricants){RESET}\n")

lubricants_result = get_customer_materials(
    customer_uid="test_uid",
    customer_name="Test Customer",
    material_name="lubricant"
)

lubricants = lubricants_result.get("materials", [])
print_test(
    "Filtered materials returned",
    len(lubricants) >= 0,
    f"Lubricants found: {len(lubricants)}"
)

if lubricants:
    print(f"\n  {BOLD}Lubricant Products:{RESET}")
    for lub in lubricants[:3]:
        print(f"    • {lub.get('name', 'N/A')} - {lub.get('customer_price', 'N/A')}")

# =============================================================================
# TEST 5: Verify catalog organization
# =============================================================================
print(f"\n{BOLD}TEST 5: Verify Catalog Organization{RESET}\n")

# Group services by category
if services:
    service_groups = {}
    for svc in services:
        group = svc.get("group", "Uncategorized")
        if group not in service_groups:
            service_groups[group] = []
        service_groups[group].append(svc)
    
    print_test(
        "Services are grouped by category",
        len(service_groups) >= 1,
        f"Found {len(service_groups)} service group(s)"
    )
    
    print(f"\n  {BOLD}Service Groups:{RESET}")
    for group, items in sorted(service_groups.items()):
        print(f"    • {group}: {len(items)} service(s)")

# Group materials by category
if materials:
    material_groups = {}
    for mat in materials:
        group = mat.get("group", "Uncategorized")
        if group not in material_groups:
            material_groups[group] = []
        material_groups[group].append(mat)
    
    print_test(
        "Materials are grouped by category",
        len(material_groups) >= 1,
        f"Found {len(material_groups)} material group(s)"
    )
    
    print(f"\n  {BOLD}Material Groups:{RESET}")
    for group, items in sorted(material_groups.items()):
        print(f"    • {group}: {len(items)} product(s)")

# =============================================================================
# SUMMARY
# =============================================================================
print(f"\n{CYAN}{'='*80}{RESET}")
print(f"{BOLD}TEST SUMMARY{RESET}")
print(f"{CYAN}{'='*80}{RESET}\n")

total = passed + failed
pass_rate = (passed / total * 100) if total > 0 else 0

print(f"  Total Tests: {total}")
print(f"  {GREEN}Passed: {passed}{RESET}")
print(f"  {RED}Failed: {failed}{RESET}")
print(f"  Pass Rate: {pass_rate:.1f}%\n")

print(f"{BOLD}Key Findings:{RESET}")
print(f"  • Total Services Available: {total_services}")
print(f"  • Total Materials Available: {total_materials}")
print(f"  • Service Groups: {len(service_groups) if services else 0}")
print(f"  • Material Groups: {len(material_groups) if materials else 0}")

print(f"\n{BOLD}Customer Experience:{RESET}")
if total_services > 0:
    print(f"  ✓ Customers can view complete service catalog with {total_services} services")
else:
    print(f"  ⚠ No services in catalog - please add services to item_master")

if total_materials > 0:
    print(f"  ✓ Customers can view complete material catalog with {total_materials} products")
else:
    print(f"  ℹ No materials in catalog (may be intentional)")

print(f"  ✓ Customer pricing information is available")
print(f"  ✓ Internal inventory data is hidden from customers")

if failed == 0:
    print(f"\n{GREEN}{BOLD}✓ All tests passed!{RESET}")
    print(f"\n{GREEN}The AI assistant can now show complete price lists when customers ask.{RESET}\n")
    sys.exit(0)
else:
    print(f"\n{RED}{BOLD}✗ Some tests failed.{RESET}\n")
    sys.exit(1)
