import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_service.dart';

class PaymentService {
  final Razorpay _razorpay = Razorpay();
  final Function(PaymentSuccessResponse)? onSuccess;
  final Function(PaymentFailureResponse)? onFailure;
  final Function(ExternalWalletResponse)? onExternalWallet;

  PaymentService({this.onSuccess, this.onFailure, this.onExternalWallet}) {
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  void dispose() {
    _razorpay.clear();
  }

  void startPayment(User user, int amountPaise) {
    var options = {
      'key': 'rzp_test_SLTytkExq4wXcq',
      'amount': amountPaise,
      'name': 'MemoryLens',
      'description': 'MemoryLens Pro - Lifetime Access',
      'prefill': {
        'name': user.displayName ?? '',
        'contact': '', // Optional if phone is known
        'email': user.email ?? '',
      },
      'theme': {'color': '#1A1A2E'},
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      print("Razorpay Error: $e");
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await UserService.updateProStatus(
          user.uid,
          response.paymentId ?? 'unknown',
        );
      }
    } catch (e) {
      print("Error updating pro status in Firestore: $e");
    } finally {
      onSuccess?.call(response);
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    onFailure?.call(response);
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    onExternalWallet?.call(response);
  }
}
