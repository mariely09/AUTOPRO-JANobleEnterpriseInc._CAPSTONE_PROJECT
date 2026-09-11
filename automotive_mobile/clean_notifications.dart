// Run this script once to clean up old notifications with emojis
// Usage: dart run clean_notifications.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  // Initialize Firebase
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSyDlCt4R7NZT-489E-BcuAJVX9Dt0Vgn6v0',
      appId: '1:560074806897:android:8d64c07518f4f1c88c3e59',
      messagingSenderId: '560074806897',
      projectId: 'caltex-autopro-capstone-project',
      storageBucket: 'caltex-autopro-capstone-project.firebasestorage.app',
    ),
  );

  print('🔥 Connected to Firebase');
  print('🗑️  Deleting all notifications...');

  final db = FirebaseFirestore.instance;
  final snapshot = await db.collection('notifications').get();
  
  print('Found ${snapshot.docs.length} notifications');

  // Delete in batches
  final batch = db.batch();
  for (var doc in snapshot.docs) {
    batch.delete(doc.reference);
  }
  
  await batch.commit();
  
  print('✅ All notifications deleted!');
  print('📝 New notifications will have clean titles (no emojis)');
}
