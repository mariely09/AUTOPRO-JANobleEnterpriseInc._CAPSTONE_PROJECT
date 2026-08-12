"""
Database cleanup script to delete AI Settings related Firestore collections.

This script removes:
1. ai_settings collection (rotation settings and configuration)
2. ai_api_keys collection (Groq API keys)

Run this script once to clean up the database after removing the AI Settings feature.

Usage:
    python delete_ai_settings_collections.py
"""

from firestore_client import get_db


def delete_collection(collection_name, batch_size=100):
    """Delete all documents in a Firestore collection in batches."""
    db = get_db()
    coll_ref = db.collection(collection_name)
    
    deleted = 0
    while True:
        # Get a batch of documents
        docs = list(coll_ref.limit(batch_size).stream())
        
        if not docs:
            break
        
        # Delete the batch
        batch = db.batch()
        for doc in docs:
            batch.delete(doc.reference)
        batch.commit()
        
        deleted += len(docs)
        print(f"  Deleted {len(docs)} documents from {collection_name}")
    
    return deleted


def main():
    """Delete AI Settings related Firestore collections."""
    print("=" * 60)
    print("AI Settings Database Cleanup")
    print("=" * 60)
    print("\nThis will permanently delete the following collections:")
    print("  - ai_settings")
    print("  - ai_api_keys")
    print()
    
    confirm = input("Are you sure you want to proceed? (yes/no): ").strip().lower()
    
    if confirm != "yes":
        print("\nCanceled. No changes made.")
        return
    
    print("\nDeleting collections...\n")
    
    # Delete ai_settings collection
    print("Deleting ai_settings collection...")
    count = delete_collection("ai_settings")
    print(f"✓ Deleted {count} documents from ai_settings\n")
    
    # Delete ai_api_keys collection
    print("Deleting ai_api_keys collection...")
    count = delete_collection("ai_api_keys")
    print(f"✓ Deleted {count} documents from ai_api_keys\n")
    
    print("=" * 60)
    print("Cleanup completed successfully!")
    print("=" * 60)


if __name__ == "__main__":
    main()
