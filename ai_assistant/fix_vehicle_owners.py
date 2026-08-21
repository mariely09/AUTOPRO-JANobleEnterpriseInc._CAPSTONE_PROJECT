"""
fix_vehicle_owners.py — Safely fix mismatched `owner` fields on vehicle documents.

What it does:
  1. Loads every customer from the `users` collection (name + companyName).
  2. Scans every vehicle doc.
  3. If the vehicle's `owner` field matches a user's companyName (but NOT their name),
     it updates owner → user's name so the AI lookup works correctly.
  4. If the vehicle's `owner` field matches with different casing,
     it normalises it to the canonical name from the users collection.

DRY RUN by default — prints what WOULD change without touching Firestore.
Pass --apply to actually write the changes.

Usage:
    cd ai_assistant
    python fix_vehicle_owners.py            # dry run — safe, read-only
    python fix_vehicle_owners.py --apply    # write the fixes to Firestore
"""
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from firestore_client import get_db

DRY_RUN = "--apply" not in sys.argv

def main():
    db = get_db()

    print(f"\n{'='*60}")
    print(f"fix_vehicle_owners — {'DRY RUN (no writes)' if DRY_RUN else '⚠️  APPLYING CHANGES'}")
    print(f"{'='*60}\n")

    # ── Build a lookup of all customer names + companyNames ───────────────────
    # Maps every known name variant (lowercase) → canonical name (from users.name)
    name_map: dict[str, str] = {}   # lower_variant → canonical_name
    uid_map:  dict[str, str] = {}   # lower_variant → uid (for logging)

    print("Loading users...")
    for doc in db.collection("users").stream():
        d    = doc.to_dict()
        role = (d.get("role") or "").lower()
        if role not in ("customer",):
            continue  # only fix customer-owned vehicles

        canonical = (d.get("name") or "").strip()
        company   = (d.get("companyName") or "").strip()

        if canonical:
            name_map[canonical.lower()] = canonical
            uid_map[canonical.lower()]  = doc.id
        if company and company.lower() != canonical.lower():
            # companyName is an alias — map it to the canonical personal name
            name_map[company.lower()] = canonical
            uid_map[company.lower()]  = doc.id

    print(f"  Found {len(uid_map)} name variants across customers.\n")

    # ── Scan vehicles ─────────────────────────────────────────────────────────
    fixes:    list[tuple] = []   # (doc_id, plate, old_owner, new_owner)
    no_match: list[tuple] = []   # (doc_id, plate, stored_owner) — unknown owner

    print("Scanning vehicles...")
    for doc in db.collection("vehicles").stream():
        d      = doc.to_dict()
        plate  = d.get("plate", "—")
        stored = (d.get("owner") or "").strip()

        if not stored:
            print(f"  ⚠️  plate={plate!r} — owner field is EMPTY, skipping.")
            continue

        canonical = name_map.get(stored.lower())

        if canonical is None:
            no_match.append((doc.id, plate, stored))
            print(f"  ?  plate={plate!r}  owner={stored!r}  — no matching customer found")
        elif canonical == stored:
            print(f"  ✅ plate={plate!r}  owner={stored!r}  — already correct")
        else:
            fixes.append((doc.id, plate, stored, canonical))
            print(f"  🔧 plate={plate!r}  owner={stored!r}  → WILL FIX to {canonical!r}")

    # ── Summary ───────────────────────────────────────────────────────────────
    print(f"\n{'─'*60}")
    print(f"Summary:")
    print(f"  Vehicles to fix : {len(fixes)}")
    print(f"  Unknown owners  : {len(no_match)}")

    if no_match:
        print("\n  Vehicles with unknown owner (not touched):")
        for doc_id, plate, owner in no_match:
            print(f"    plate={plate!r}  owner={owner!r}  (doc={doc_id})")

    if not fixes:
        print("\n  Nothing to fix — all matched vehicles already have correct owner names.")
        return

    # ── Apply fixes ───────────────────────────────────────────────────────────
    if DRY_RUN:
        print(f"\n  ℹ️  DRY RUN — no changes written.")
        print(f"  Run with --apply to apply the {len(fixes)} fix(es) above.\n")
    else:
        print(f"\n  Applying {len(fixes)} fix(es)...")
        batch     = db.batch()
        batch_n   = 0
        committed = 0
        for doc_id, plate, old_owner, new_owner in fixes:
            ref = db.collection("vehicles").document(doc_id)
            batch.update(ref, {"owner": new_owner})
            batch_n += 1
            if batch_n >= 400:          # Firestore batch limit is 500 — stay safe
                batch.commit()
                committed += batch_n
                batch   = db.batch()
                batch_n = 0
        if batch_n:
            batch.commit()
            committed += batch_n

        print(f"  ✅ Done — {committed} vehicle document(s) updated.\n")
        print("  Changes applied:")
        for _, plate, old_owner, new_owner in fixes:
            print(f"    plate={plate!r}  '{old_owner}' → '{new_owner}'")

    print(f"\n{'='*60}\n")


if __name__ == "__main__":
    main()
