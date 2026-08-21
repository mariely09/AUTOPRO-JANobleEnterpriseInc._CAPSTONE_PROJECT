"""
diagnose_owner.py — Run this locally to see exactly what's in Firestore.

Usage:
    cd ai_assistant
    python diagnose_owner.py "Exact Name From App"

It prints:
  1. The user's Firestore profile (name, companyName)
  2. Every vehicle doc with its owner field + whether it matches
  3. All maintenance records for each matched plate
"""
import sys
import os

# ── bootstrap path so firestore_client works ─────────────────────────────────
sys.path.insert(0, os.path.dirname(__file__))
from firestore_client import get_db

def diagnose(customer_name: str):
    db = get_db()
    name_lower = customer_name.lower().strip()

    print(f"\n{'='*60}")
    print(f"Diagnosing for customer_name = {customer_name!r}")
    print(f"{'='*60}\n")

    # ── Step 1: find the user document ───────────────────────────────────────
    print("─── USERS collection ───")
    user_matches = []
    for doc in db.collection("users").where("role", "==", "customer").stream():
        d = doc.to_dict()
        n = (d.get("name") or "").strip()
        c = (d.get("companyName") or "").strip()
        if n.lower() == name_lower or c.lower() == name_lower:
            user_matches.append((doc.id, n, c))
            print(f"  ✅ MATCH  uid={doc.id}  name={n!r}  companyName={c!r}")
        else:
            print(f"  ·  uid={doc.id}  name={n!r}  companyName={c!r}")

    if not user_matches:
        print(f"\n  ⚠️  No user found with name or companyName == {customer_name!r}")
        print("     The name you're searching for may not match what's in Firestore.\n")

    # ── Step 2: scan every vehicle ────────────────────────────────────────────
    print("\n─── VEHICLES collection ───")
    matched_plates = []
    for doc in db.collection("vehicles").stream():
        d      = doc.to_dict()
        stored = (d.get("owner") or "").strip()
        plate  = d.get("plate", "—")
        desc   = d.get("desc",  "—")
        match  = stored.lower() == name_lower
        flag   = "✅ MATCH " if match else "·  no match"
        print(f"  {flag}  plate={plate!r}  desc={desc!r}  owner={stored!r}")
        if match:
            matched_plates.append(plate)

    print(f"\n  → Matched plates: {matched_plates}")

    if not matched_plates:
        print("\n  ⚠️  Zero vehicles matched!")
        print("     The owner field on your vehicles does NOT match the customer_name.")
        print("     Check the values above and fix either the vehicle owner field")
        print("     or ensure the name passed from login matches exactly.\n")
        return

    # ── Step 3: check maintenance for each plate ──────────────────────────────
    print("\n─── MAINTENANCE collection (per matched plate) ───")
    for plate in matched_plates:
        print(f"\n  Plate: {plate!r}")
        count = 0
        for doc in db.collection("maintenance").where("plate", "==", plate).stream():
            d      = doc.to_dict()
            status = d.get("status", "—")
            date   = d.get("date",   "—")
            cost   = d.get("cost",   "—")
            print(f"    • date={date}  status={status}  cost={cost}")
            count += 1
        if count == 0:
            print("    (no maintenance records for this plate)")

    print(f"\n{'='*60}")
    print("Done.")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python diagnose_owner.py \"Customer Name\"")
        sys.exit(1)
    diagnose(" ".join(sys.argv[1:]))
