import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Stream<DocumentSnapshot<Map<String, dynamic>>> getUserStream(
    String uid,
  ) {
    return _firestore.collection('users').doc(uid).snapshots();
  }

  static Future<void> initUser(User user) async {
    print("UserService: Checking if user exists in Firestore: ${user.uid}");
    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (!doc.exists) {
      print(
        "UserService: User does not exist, creating new record with 30-day trial.",
      );
      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'isPro': false,
        'trialStartDate': DateTime.now().toIso8601String(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      print("UserService: Record created successfully.");
    } else {
      print("UserService: User already exists. isPro: ${doc.data()?['isPro']}");
    }
  }

  static Future<void> updateProStatus(String uid, String paymentId) async {
    print("UserService: Upgrading user to Pro: $uid, PaymentId: $paymentId");
    await _firestore.collection('users').doc(uid).set({
      'isPro': true,
      'paymentId': paymentId,
      'upgradedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    print("UserService: Pro status saved to Firestore successfully.");
  }

  static int getTrialDaysRemaining(String? trialStartDateStr) {
    if (trialStartDateStr == null)
      return 30; // Default to 30 if null (e.g. initializing)
    final startDate = DateTime.tryParse(trialStartDateStr);
    if (startDate == null) return 30;

    final now = DateTime.now();
    final difference = now.difference(startDate).inDays;
    final remaining = 30 - difference;
    return remaining < 0 ? 0 : remaining;
  }
}
