"""
migrate_vehicles.py  —  Canonical Firestore data normalisation
==============================================================
Permanently normalises the Firestore data model to the authoritative schema:

  CUSTOMER  (users collection, Firebase Auth UID as doc ID)
      │
      │  ownerId
      ▼
  VEHICLE  (vehicles collection)
      │
      │  vehicleId + ownerId
      ▼
  MAINTENANCE  (maintenance collection)

VEHICLE canonical fields
------------------------
  ownerId              — Firebase Auth UID  (authoritative customer link)
  owner                — human-readable snapshot
  plateNumber          — canonical plate   (was: plate)
  description          — canonical desc    (was: desc / assetDescription)
  type
  odometer             — int km            (was: odo "12345 km")
  lastServiceDate      — YYYY-MM-DD        (was: lastSvcDate)
  lastServiceOdometer  — int               (was: lastSvcOdo)
  serviceFrequency     — int months        (was: svcFreq as string)
  status

MAINTENANCE canonical fields (added by migrate_maintenance.py)
--------------------------------------------------------------
  vehicleId   — vehicles doc ID
  ownerId     — Firebase Auth UID
  plateNumber — snapshot plate

FIELD MAPPING (old  →  canonical)
----------------------------------
  plate                →  plateNumber
  desc / assetDescription → description
  lastSvcDate          →  lastServiceDate
  lastSvcOdo           →  lastServiceOdometer
  svcFreq              →  serviceFrequency
  odo ("12345 km")     →  odometer (int)

CONFLICT DETECTION
------------------
If both an old field and the canonical field exist with *different* values,
the document is flagged as CONFLICT and NOT touched.  Never silently overwrites.

DATA TYPE NORMALISATION
------------------------
  serviceFrequency  →  int
  odometer          →  int
  lastServiceDate   →  YYYY-MM-DD string (no semantic change)

OWNER-ID BACKFILL
------------------
Matches vehicle.owner text against users.name / users.companyName to find the
correct Firebase UID.
  UNRESOLVED  — no customer matched
  AMBIGUOUS   — multiple customers matched

DRY RUN by default:
    python migrate_vehicles.py             # safe preview
    python migrate_vehicles.py --apply     # write to Firestore
    python migrate_vehicles.py --verify    # post-migration integrity report only
"""

import sys
import os
import re

sys.path.insert(0, os.path.dirname(__file__))
from firestore_client import get_db

DRY_RUN  = "--apply"  not in sys.argv
VERIFY   = "--verify" in sys.argv


# ── helpers ───────────────────────────────────────────────────────────────────

def _parse_int(value) -> int | None:
    """Extract an integer from any value (int, float, '12345 km', '12,345', etc.)."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return int(value)
    cleaned = re.sub(r"[^0-9]", "", str(value))
    return int(cleaned) if cleaned else None


def _normalise_date(value) -> str | None:
    """
    Return YYYY-MM-DD string, or None if unparseable.
    Accepts ISO strings, Firestore Timestamps, and datetime objects.
    """
    if value is None:
        return None
    # Firestore Timestamp
    if hasattr(value, "isoformat"):
        return value.isoformat()[:10]
    s = str(value).strip()
    # Already YYYY-MM-DD
    if re.match(r"^\d{4}-\d{2}-\d{2}$", s):
        return s
    # Try datetime parsing for other formats
    from datetime import datetime
    for fmt in ("%Y-%m-%d", "%m/%d/%Y", "%d/%m/%Y"):
        try:
            return datetime.strptime(s, fmt).strftime("%Y-%m-%d")
        except ValueError:
            pass
    return None


def _values_conflict(old_val, new_val) -> bool:
    """True if both values are non-empty and meaningfully different."""
    if old_val is None or old_val == "" or new_val is None or new_val == "":
        return False
    return str(old_val).strip().upper() != str(new_val).strip().upper()


# ── main migration ────────────────────────────────────────────────────────────

def main():
    db = get_db()

    # ── VERIFY MODE ──────────────────────────────────────────────────────────
    if VERIFY:
        return _run_verification(db)

    print(f"\n{'='*65}")
    print(f"migrate_vehicles.py  —  "
          f"{'DRY RUN (no writes)' if DRY_RUN else '⚠️  APPLYING CHANGES'}")
    print(f"{'='*65}\n")

    # ── 1. Load customer accounts ─────────────────────────────────────────────
    print("Loading customer accounts …")
    # uid → {name, companyName, lower_names}
    uid_to_info: dict[str, dict]      = {}
    # lower_name → [uid, …]  (multiple customers could share a name — detect ambiguous)
    name_to_uids: dict[str, list[str]] = {}

    for doc in db.collection("users").stream():
        d = doc.to_dict()
        if (d.get("role") or "").lower() != "customer":
            continue
        uid     = doc.id
        name    = (d.get("name")        or "").strip()
        company = (d.get("companyName") or "").strip()
        uid_to_info[uid] = {"name": name, "company": company}
        for variant in {name, company}:
            if not variant:
                continue
            key = variant.lower()
            name_to_uids.setdefault(key, [])
            if uid not in name_to_uids[key]:
                name_to_uids[key].append(uid)

    unique_customers = len(uid_to_info)
    print(f"  Loaded {len(name_to_uids)} name/company variants "
          f"from {unique_customers} customer account(s).\n")

    # ── 2. Scan vehicles ──────────────────────────────────────────────────────
    print("Scanning vehicles collection …\n")

    stats = {
        "total": 0, "already_normalised": 0, "needs_update": 0,
        "owner_id_added": 0, "plate_normalised": 0, "desc_normalised": 0,
        "date_normalised": 0, "odo_normalised": 0, "freq_normalised": 0,
        "conflicts": 0, "unresolved": 0, "ambiguous": 0,
    }

    # (doc_id, update_dict)
    safe_updates: list[tuple[str, dict]] = []
    conflict_report: list[dict]          = []
    unresolved_report: list[dict]        = []
    ambiguous_report: list[dict]         = []

    for doc in db.collection("vehicles").stream():
        d      = doc.to_dict()
        doc_id = doc.id
        stats["total"] += 1
        updates: dict        = {}
        conflicts_found: bool = False

        # ── Helper: propose a canonical field value ───────────────────────────
        def propose(canonical_key: str, old_key: str, new_value,
                    conflict_label: str | None = None) -> None:
            nonlocal conflicts_found
            existing = d.get(canonical_key)
            if existing is not None and existing != "" and existing != new_value:
                if _values_conflict(existing, new_value):
                    conflict_report.append({
                        "vehicleId": doc_id,
                        "field": canonical_key,
                        "old_value": existing,
                        "new_value": new_value,
                        "old_field": old_key,
                    })
                    conflicts_found = True
                    return
            # Only set if not already present
            if existing is None or existing == "":
                updates[canonical_key] = new_value

        # ── 2a. plateNumber ───────────────────────────────────────────────────
        old_plate    = (d.get("plate")       or "").strip()
        canon_plate  = (d.get("plateNumber") or "").strip()
        if old_plate and not canon_plate:
            updates["plateNumber"] = old_plate.upper()
            stats["plate_normalised"] += 1
        elif old_plate and canon_plate:
            if _values_conflict(old_plate, canon_plate):
                conflict_report.append({
                    "vehicleId": doc_id,
                    "field": "plateNumber",
                    "old_value": canon_plate,
                    "new_value": old_plate,
                    "old_field": "plate",
                })
                conflicts_found = True
            # else they agree — no update needed
        elif not old_plate and not canon_plate:
            pass  # nothing to do

        # ── 2b. description ───────────────────────────────────────────────────
        old_desc   = (d.get("desc") or d.get("assetDescription") or "").strip()
        canon_desc = (d.get("description") or "").strip()
        if old_desc and not canon_desc:
            updates["description"] = old_desc
            stats["desc_normalised"] += 1
        elif old_desc and canon_desc:
            if _values_conflict(old_desc, canon_desc):
                conflict_report.append({
                    "vehicleId": doc_id,
                    "field": "description",
                    "old_value": canon_desc,
                    "new_value": old_desc,
                    "old_field": "desc/assetDescription",
                })
                conflicts_found = True

        # ── 2c. lastServiceDate ───────────────────────────────────────────────
        old_lsd   = _normalise_date(d.get("lastSvcDate"))
        canon_lsd = _normalise_date(d.get("lastServiceDate"))
        if old_lsd and not canon_lsd:
            updates["lastServiceDate"] = old_lsd
            stats["date_normalised"] += 1
        elif old_lsd and canon_lsd:
            if old_lsd != canon_lsd:
                conflict_report.append({
                    "vehicleId": doc_id,
                    "field": "lastServiceDate",
                    "old_value": canon_lsd,
                    "new_value": old_lsd,
                    "old_field": "lastSvcDate",
                })
                conflicts_found = True

        # ── 2d. lastServiceOdometer ───────────────────────────────────────────
        old_lso   = _parse_int(d.get("lastSvcOdo"))
        canon_lso = _parse_int(d.get("lastServiceOdometer"))
        if old_lso is not None and old_lso > 0 and (canon_lso is None or canon_lso == 0):
            updates["lastServiceOdometer"] = old_lso
            stats["odo_normalised"] += 1
        elif old_lso and canon_lso and old_lso != canon_lso:
            conflict_report.append({
                "vehicleId": doc_id,
                "field": "lastServiceOdometer",
                "old_value": canon_lso,
                "new_value": old_lso,
                "old_field": "lastSvcOdo",
            })
            conflicts_found = True

        # ── 2e. serviceFrequency (normalize to int) ───────────────────────────
        raw_sf_old   = d.get("svcFreq")
        raw_sf_canon = d.get("serviceFrequency")
        old_sf       = _parse_int(raw_sf_old)
        canon_sf     = _parse_int(raw_sf_canon)
        if old_sf and not canon_sf:
            updates["serviceFrequency"] = old_sf
            stats["freq_normalised"] += 1
        elif canon_sf and isinstance(raw_sf_canon, str):
            # Already present but stored as string — normalise to int
            updates["serviceFrequency"] = canon_sf
        elif old_sf and canon_sf and old_sf != canon_sf:
            conflict_report.append({
                "vehicleId": doc_id,
                "field": "serviceFrequency",
                "old_value": canon_sf,
                "new_value": old_sf,
                "old_field": "svcFreq",
            })
            conflicts_found = True

        # ── 2f. odometer (normalize odo "12345 km" → odometer int) ───────────
        odo_int   = _parse_int(d.get("odo"))
        canon_odo = d.get("odometer")
        if isinstance(canon_odo, str):
            canon_odo_int = _parse_int(canon_odo)
            if canon_odo_int is not None:
                updates["odometer"] = canon_odo_int
        elif odo_int and (canon_odo is None or canon_odo == 0):
            updates["odometer"] = odo_int

        # ── 2g. ownerId backfill ──────────────────────────────────────────────
        existing_owner_id = (d.get("ownerId") or "").strip()
        if not existing_owner_id:
            owner_text = (d.get("owner") or "").strip()
            if owner_text:
                uids = name_to_uids.get(owner_text.lower(), [])
                if len(uids) == 1:
                    updates["ownerId"] = uids[0]
                    stats["owner_id_added"] += 1
                elif len(uids) == 0:
                    unresolved_report.append({
                        "vehicleId": doc_id,
                        "plate": d.get("plate") or d.get("plateNumber") or "?",
                        "owner": owner_text,
                    })
                    stats["unresolved"] += 1
                else:  # > 1 match
                    ambiguous_report.append({
                        "vehicleId": doc_id,
                        "plate": d.get("plate") or d.get("plateNumber") or "?",
                        "owner": owner_text,
                        "matched_uids": uids,
                    })
                    stats["ambiguous"] += 1

        # ── decide ────────────────────────────────────────────────────────────
        plate_disp = (d.get("plateNumber") or d.get("plate") or "?")
        if conflicts_found:
            stats["conflicts"] += 1
            print(f"  ⚠️  CONFLICT  doc={doc_id[:20]}  plate={plate_disp!r}")
        elif updates:
            stats["needs_update"] += 1
            safe_updates.append((doc_id, updates))
            keys = sorted(updates.keys())
            print(f"  🔧 UPDATE    doc={doc_id[:20]}  plate={plate_disp!r}  → {keys}")
        else:
            stats["already_normalised"] += 1
            print(f"  ✅ OK        doc={doc_id[:20]}  plate={plate_disp!r}")

    # ── 3. Reports ────────────────────────────────────────────────────────────
    print(f"\n{'─'*65}")
    print("SUMMARY")
    print(f"  Total vehicles       : {stats['total']}")
    print(f"  Already normalised   : {stats['already_normalised']}")
    print(f"  Needs normalisation  : {stats['needs_update']}")
    print(f"  Owner IDs to add     : {stats['owner_id_added']}")
    print(f"  Plate normalised     : {stats['plate_normalised']}")
    print(f"  Desc normalised      : {stats['desc_normalised']}")
    print(f"  Date normalised      : {stats['date_normalised']}")
    print(f"  Odo normalised       : {stats['odo_normalised']}")
    print(f"  Freq normalised      : {stats['freq_normalised']}")
    print(f"  Conflicts (skipped)  : {stats['conflicts']}")
    print(f"  Unresolved owners    : {stats['unresolved']}")
    print(f"  Ambiguous owners     : {stats['ambiguous']}")

    if conflict_report:
        print(f"\n  ──  CONFLICT DETAILS (require manual review)  ──")
        for c in conflict_report:
            print(f"    vehicleId={c['vehicleId'][:20]}  field={c['field']!r}  "
                  f"existing={c['old_value']!r}  incoming={c['new_value']!r}  "
                  f"(from field: {c['old_field']!r})")

    if unresolved_report:
        print(f"\n  ──  UNRESOLVED OWNERS (ownerId NOT set)  ──")
        for u in unresolved_report:
            print(f"    vehicleId={u['vehicleId'][:20]}  plate={u['plate']!r}  "
                  f"owner={u['owner']!r}")
        print("\n  → Correct the 'owner' field on these vehicles so it exactly")
        print("    matches a customer's name or companyName, then re-run.")

    if ambiguous_report:
        print(f"\n  ──  AMBIGUOUS OWNERS (ownerId NOT set)  ──")
        for a in ambiguous_report:
            print(f"    vehicleId={a['vehicleId'][:20]}  plate={a['plate']!r}  "
                  f"owner={a['owner']!r}  matched_uids={a['matched_uids']}")
        print("\n  → Multiple customers match this name.  Set ownerId manually.")

    # ── 4. Apply ──────────────────────────────────────────────────────────────
    if not safe_updates:
        print("\n  Nothing to migrate — all vehicle documents are already normalised.")
    elif DRY_RUN:
        print(f"\n  ℹ️  DRY RUN — no changes written.")
        print(f"  Run with --apply to apply {len(safe_updates)} safe update(s).\n")
    else:
        print(f"\n  Applying {len(safe_updates)} update(s) …")
        batch, batch_n, committed = db.batch(), 0, 0
        for doc_id, upd in safe_updates:
            batch.update(db.collection("vehicles").document(doc_id), upd)
            batch_n += 1
            if batch_n >= 400:
                batch.commit(); committed += batch_n
                batch, batch_n = db.batch(), 0
        if batch_n:
            batch.commit(); committed += batch_n
        print(f"  ✅ {committed} vehicle document(s) updated successfully.")
        print("\n  NOTE: Legacy fields (plate, desc, lastSvcDate, lastSvcOdo, svcFreq, odo)")
        print("        have been PRESERVED alongside the canonical fields.")
        print("        Run with --verify to check integrity, then manually remove")
        print("        legacy fields once satisfied.\n")

    print(f"\n{'='*65}\n")


# ── verification ──────────────────────────────────────────────────────────────

def _run_verification(db) -> None:
    print(f"\n{'='*65}")
    print("migrate_vehicles.py  —  VERIFICATION REPORT")
    print(f"{'='*65}\n")

    # Build vehicle lookup for maintenance check — include archived vehicles
    vehicles: dict[str, dict] = {}  # doc_id → data
    for doc in db.collection("vehicles").stream():
        vehicles[doc.id] = doc.to_dict()

    # Also include archived vehicles so historical maintenance records resolve correctly
    archived_vehicles: dict[str, dict] = {}
    try:
        for doc in db.collection("archive").document("vehicles").collection("vehicles").stream():
            archived_vehicles[doc.id] = doc.to_dict()
    except Exception:
        pass  # archive may not exist yet

    all_known_vehicles = {**vehicles, **archived_vehicles}

    # Build uid set for owner validation
    customer_uids = set()
    for doc in db.collection("users").stream():
        if (doc.to_dict().get("role") or "").lower() == "customer":
            customer_uids.add(doc.id)

    veh_ok = veh_fail = 0
    veh_failures: list[str] = []

    for doc_id, d in vehicles.items():
        plate = d.get("plateNumber") or d.get("plate") or ""
        issues = []
        if not d.get("ownerId"):
            issues.append("missing ownerId")
        elif d["ownerId"] not in customer_uids:
            issues.append(f"ownerId={d['ownerId']!r} not a known customer")
        if not d.get("plateNumber"):
            issues.append("missing plateNumber")
        if not d.get("lastServiceDate") and not d.get("lastSvcDate"):
            issues.append("missing lastServiceDate")

        if issues:
            veh_fail += 1
            veh_failures.append(
                f"  ✗ vehicles/{doc_id[:20]}  plate={plate!r}  → {', '.join(issues)}"
            )
        else:
            veh_ok += 1

    print(f"Vehicles: {veh_ok} OK  /  {veh_fail} with issues")
    for line in veh_failures:
        print(line)

    # Maintenance check
    maint_ok = maint_fail = 0
    maint_failures: list[str] = []

    for doc in db.collection("maintenance").stream():
        d      = doc.to_dict()
        doc_id = doc.id
        plate  = d.get("plate") or d.get("plateNumber") or ""
        issues = []
        if not d.get("ownerId"):
            issues.append("missing ownerId")
        if not d.get("vehicleId"):
            issues.append("missing vehicleId")
        elif d["vehicleId"] not in all_known_vehicles:
            issues.append(f"vehicleId={d['vehicleId']!r} not found in vehicles or archive")
        else:
            v = all_known_vehicles[d["vehicleId"]]
            if d.get("ownerId") and v.get("ownerId") and d["ownerId"] != v["ownerId"]:
                issues.append(
                    f"ownerId mismatch: maintenance={d['ownerId']!r} "
                    f"vs vehicle={v['ownerId']!r}"
                )

        if issues:
            maint_fail += 1
            maint_failures.append(
                f"  ✗ maintenance/{doc_id[:20]}  plate={plate!r}  → {', '.join(issues)}"
            )
        else:
            maint_ok += 1

    print(f"\nMaintenance: {maint_ok} OK  /  {maint_fail} with issues")
    for line in maint_failures:
        print(line)

    if veh_fail == 0 and maint_fail == 0:
        print("\n  ✅ All records are consistent with the canonical schema.")
    else:
        print(f"\n  ⚠️  {veh_fail + maint_fail} record(s) need attention.")
        print("     Run migrate_vehicles.py --apply and migrate_maintenance.py --apply first.")

    print(f"\n{'='*65}\n")


if __name__ == "__main__":
    main()
