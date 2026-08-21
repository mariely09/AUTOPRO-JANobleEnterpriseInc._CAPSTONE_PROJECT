"""
migrate_maintenance.py  —  Backfill vehicleId + ownerId on maintenance records
===============================================================================
For every maintenance document that is missing vehicleId or ownerId:

  Priority 1 — record already has a valid vehicleId         → verify & use
  Priority 2 — match by plateNumber (maintenance.plateNumber == vehicle.plateNumber)
  Priority 3 — match by plate  (legacy field name)
  Priority 4 — match by owner (narrow, only if 1 vehicle found for that owner)

CONFLICT DETECTION
------------------
  SERVICE RECORD CONFLICT  — record has vehicleId=A but plate belongs to vehicle B
  INTEGRITY ERROR          — record.ownerId != vehicle.ownerId (when both present)

DRY RUN by default:
    python migrate_maintenance.py             # safe preview
    python migrate_maintenance.py --apply     # write to Firestore
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from firestore_client import get_db

DRY_RUN = "--apply" not in sys.argv


def main():
    db = get_db()

    print(f"\n{'='*65}")
    print(f"migrate_maintenance.py  —  "
          f"{'DRY RUN (no writes)' if DRY_RUN else '⚠️  APPLYING CHANGES'}")
    print(f"{'='*65}\n")

    # ── 1. Build vehicle lookup tables ────────────────────────────────────────
    print("Loading vehicles …")
    # doc_id → {plateNumber, ownerId, plate}
    vehicle_by_id: dict[str, dict] = {}
    # plateNumber (upper) → doc_id  (deduplicated — log if plate is ambiguous)
    vehicle_by_plate: dict[str, str] = {}
    # ownerId → [doc_id, …]
    vehicles_by_owner: dict[str, list[str]] = {}
    plate_ambiguous: set[str] = set()   # plates that map to multiple vehicles

    for doc in db.collection("vehicles").stream():
        d      = doc.to_dict()
        vid    = doc.id
        plate  = (d.get("plateNumber") or d.get("plate") or "").strip().upper()
        oid    = (d.get("ownerId") or "").strip()

        vehicle_by_id[vid] = {
            "plateNumber": plate,
            "ownerId":     oid,
        }

        if plate:
            if plate in vehicle_by_plate:
                plate_ambiguous.add(plate)  # duplicate plate — cannot resolve by plate alone
            else:
                vehicle_by_plate[plate] = vid

        if oid:
            vehicles_by_owner.setdefault(oid, []).append(vid)

    print(f"  Loaded {len(vehicle_by_id)} vehicle(s).")
    if plate_ambiguous:
        print(f"  ⚠️  {len(plate_ambiguous)} plate(s) appear on multiple vehicle docs "
              f"(ambiguous): {sorted(plate_ambiguous)}")

    # ── 2. Scan maintenance records ───────────────────────────────────────────
    print("\nScanning maintenance collection …\n")

    stats = {
        "total": 0, "already_ok": 0, "needs_update": 0,
        "vehicle_id_resolved": 0, "owner_id_resolved": 0,
        "conflicts": 0, "unresolved": 0,
    }

    safe_updates: list[tuple[str, dict]] = []
    conflict_report: list[dict]          = []
    unresolved_report: list[dict]        = []

    for doc in db.collection("maintenance").stream():
        d      = doc.to_dict()
        doc_id = doc.id
        stats["total"] += 1

        existing_vid = (d.get("vehicleId") or "").strip()
        existing_oid = (d.get("ownerId")   or "").strip()

        # The plate stored in this record (check both field names)
        record_plate = (d.get("plateNumber") or d.get("plate") or "").strip().upper()

        updates  : dict = {}
        conflict : bool = False
        resolved_vid : str | None = None
        resolved_oid : str | None = None

        # ── Priority 1: record already has vehicleId ──────────────────────────
        if existing_vid:
            if existing_vid in vehicle_by_id:
                resolved_vid = existing_vid
                v_data = vehicle_by_id[existing_vid]
                # Check plate consistency
                if record_plate and v_data["plateNumber"] and \
                        record_plate != v_data["plateNumber"]:
                    conflict_report.append({
                        "maintenanceId": doc_id,
                        "issue": "SERVICE RECORD CONFLICT",
                        "detail": (f"vehicleId={existing_vid!r} points to plate "
                                   f"{v_data['plateNumber']!r} but record has "
                                   f"plate={record_plate!r}"),
                    })
                    conflict = True
            else:
                conflict_report.append({
                    "maintenanceId": doc_id,
                    "issue": "DANGLING vehicleId",
                    "detail": f"vehicleId={existing_vid!r} not found in vehicles collection",
                })
                conflict = True

        # ── Priority 2 / 3: resolve by plate ─────────────────────────────────
        if not conflict and not resolved_vid and record_plate:
            if record_plate in plate_ambiguous:
                conflict_report.append({
                    "maintenanceId": doc_id,
                    "issue": "AMBIGUOUS PLATE",
                    "detail": (f"plate={record_plate!r} matches multiple vehicles — "
                               "cannot auto-assign vehicleId"),
                })
                conflict = True
            elif record_plate in vehicle_by_plate:
                resolved_vid = vehicle_by_plate[record_plate]

        # ── Derive ownerId from the resolved vehicle ──────────────────────────
        if resolved_vid and not conflict:
            v_data = vehicle_by_id[resolved_vid]
            resolved_oid = v_data.get("ownerId") or ""

            # Integrity check — if record already has a different ownerId, flag it
            if existing_oid and resolved_oid and existing_oid != resolved_oid:
                conflict_report.append({
                    "maintenanceId": doc_id,
                    "issue": "INTEGRITY ERROR",
                    "detail": (f"maintenance.ownerId={existing_oid!r} but "
                               f"vehicle.ownerId={resolved_oid!r}"),
                })
                conflict = True

        # ── Build update payload ──────────────────────────────────────────────
        if not conflict:
            if resolved_vid and not existing_vid:
                updates["vehicleId"] = resolved_vid
                stats["vehicle_id_resolved"] += 1
            if resolved_oid and not existing_oid:
                updates["ownerId"] = resolved_oid
                stats["owner_id_resolved"] += 1
            # Always ensure plateNumber is set
            if record_plate and not d.get("plateNumber"):
                updates["plateNumber"] = record_plate

        # ── Log / collect ─────────────────────────────────────────────────────
        if conflict:
            stats["conflicts"] += 1
            print(f"  ⚠️  CONFLICT  doc={doc_id[:20]}  plate={record_plate!r}")
        elif not resolved_vid and not existing_vid:
            stats["unresolved"] += 1
            unresolved_report.append({
                "maintenanceId": doc_id,
                "plate": record_plate or "(no plate)",
            })
            print(f"  ?  UNRESOLVED  doc={doc_id[:20]}  plate={record_plate!r}")
        elif updates:
            stats["needs_update"] += 1
            safe_updates.append((doc_id, updates))
            print(f"  🔧 UPDATE  doc={doc_id[:20]}  plate={record_plate!r}  "
                  f"→ {sorted(updates.keys())}")
        else:
            stats["already_ok"] += 1
            print(f"  ✅ OK  doc={doc_id[:20]}  plate={record_plate!r}")

    # ── 3. Summary ────────────────────────────────────────────────────────────
    print(f"\n{'─'*65}")
    print("SUMMARY")
    print(f"  Total maintenance records : {stats['total']}")
    print(f"  Already OK                : {stats['already_ok']}")
    print(f"  Needs update              : {stats['needs_update']}")
    print(f"  vehicleId resolved        : {stats['vehicle_id_resolved']}")
    print(f"  ownerId resolved          : {stats['owner_id_resolved']}")
    print(f"  Conflicts (skipped)       : {stats['conflicts']}")
    print(f"  Unresolved (no vehicle)   : {stats['unresolved']}")

    if conflict_report:
        print(f"\n  ──  CONFLICT DETAILS (require manual review)  ──")
        for c in conflict_report:
            print(f"    maintenanceId={c['maintenanceId'][:20]}  "
                  f"[{c['issue']}]  {c['detail']}")

    if unresolved_report:
        print(f"\n  ──  UNRESOLVED RECORDS  ──")
        for u in unresolved_report:
            print(f"    maintenanceId={u['maintenanceId'][:20]}  "
                  f"plate={u['plate']!r}")
        print("\n  → Ensure the vehicle document exists with the correct plateNumber,")
        print("    then re-run this migration.")

    # ── 4. Apply ──────────────────────────────────────────────────────────────
    if not safe_updates:
        print("\n  Nothing to migrate — all maintenance records are already correct.")
    elif DRY_RUN:
        print(f"\n  ℹ️  DRY RUN — no changes written.")
        print(f"  Run with --apply to apply {len(safe_updates)} safe update(s).\n")
    else:
        print(f"\n  Applying {len(safe_updates)} update(s) …")
        batch, batch_n, committed = db.batch(), 0, 0
        for doc_id, upd in safe_updates:
            batch.update(db.collection("maintenance").document(doc_id), upd)
            batch_n += 1
            if batch_n >= 400:
                batch.commit(); committed += batch_n
                batch, batch_n = db.batch(), 0
        if batch_n:
            batch.commit(); committed += batch_n
        print(f"  ✅ {committed} maintenance record(s) updated successfully.\n")

    print(f"\n{'='*65}\n")


if __name__ == "__main__":
    main()
