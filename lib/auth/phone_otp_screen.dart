import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class PhoneOtpScreen extends StatefulWidget {
  const PhoneOtpScreen({super.key});

  @override
  State<PhoneOtpScreen> createState() => _PhoneOtpScreenState();
}

class _PhoneOtpScreenState extends State<PhoneOtpScreen> {
  final _phoneController = TextEditingController();
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  bool _isOtpSent = false;
  bool _isLoading = false;
  String? _verificationId;
  String? _errorMessage;
  ConfirmationResult? _webConfirmationResult;

  Timer? _timer;
  int _start = 60;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _phoneController.text = '+91 ';
  }

  void _startTimer() {
    setState(() {
      _start = 60;
      _canResend = false;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_start == 0) {
        setState(() {
          _canResend = true;
          timer.cancel();
        });
      } else {
        setState(() {
          _start--;
        });
      }
    });
  }

  Future<void> _verifyPhone() async {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    String phone = _phoneController.text.trim();
    if (!phone.startsWith('+')) {
      // Basic formatting cleanup
      phone = '+91${phone.replaceAll(RegExp(r'\D'), '')}';
    } else {
      phone = '+${phone.replaceAll(RegExp(r'\D'), '')}';
    }

    try {
      if (kIsWeb) {
        _webConfirmationResult = await FirebaseAuth.instance
            .signInWithPhoneNumber(phone);
        if (mounted) {
          setState(() {
            _isOtpSent = true;
            _isLoading = false;
          });
          _startTimer();
        }
      } else {
        // Phone auth is only supported on Android and iOS in the standard firebase_auth mobile SDK.
        // For Desktop, it usually requires a different approach or is not supported.
        if (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS) {
          setState(() {
            _errorMessage =
                'Phone authentication is only supported on Android and iOS devices.';
            _isLoading = false;
          });
          return;
        }

        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: phone,
          verificationCompleted: (PhoneAuthCredential credential) async {
            // Auto-resolution (Android only)
            await FirebaseAuth.instance.signInWithCredential(credential);
            if (mounted) Navigator.pop(context); // AuthWrapper takes over
          },
          verificationFailed: (FirebaseAuthException e) {
            if (mounted) {
              setState(() {
                String message = e.message ?? 'Verification failed (${e.code})';
                if (e.code == 'internal-error') {
                  message +=
                      '\n\nPlease ensure SHA-256 fingerprint is added to Firebase and Play Integrity API is enabled.';
                }
                _errorMessage = message;
                _isLoading = false;
              });
            }
          },
          codeSent: (String verificationId, int? resendToken) {
            if (mounted) {
              setState(() {
                _verificationId = verificationId;
                _isOtpSent = true;
                _isLoading = false;
              });
              _startTimer();
            }
          },
          codeAutoRetrievalTimeout: (String verificationId) {
            if (mounted) {
              setState(() {
                _verificationId = verificationId;
              });
            }
          },
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _verifyOtp() async {
    final smsCode = _otpControllers.map((c) => c.text).join('');
    if (smsCode.length != 6) {
      setState(() => _errorMessage = 'Please enter all 6 digits');
      return;
    }

    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      if (kIsWeb) {
        await _webConfirmationResult!.confirm(smsCode);
        if (mounted) Navigator.pop(context); // AuthWrapper takes over
      } else {
        final credential = PhoneAuthProvider.credential(
          verificationId: _verificationId!,
          smsCode: smsCode,
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
        if (mounted) Navigator.pop(context); // AuthWrapper takes over
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = e.message ?? 'Invalid OTP code';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Phone Verification',
          style: TextStyle(color: Colors.black),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Icon(
                Icons.mark_email_read_outlined,
                size: 64,
                color: const Color(0xFF6B8CAE),
              ),
              const SizedBox(height: 24),
              Text(
                _isOtpSent ? 'Verify Phone' : 'Enter Phone Number',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _isOtpSent
                    ? 'Enter the 6-digit code sent to\n${_phoneController.text}'
                    : 'We will send you a 6-digit verification code.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 48),

              if (!_isOtpSent) ...[
                // Phone Field
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontSize: 18, letterSpacing: 1.2),
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    errorText: _errorMessage,
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _verifyPhone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A2E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor: const Color(
                      0xFF1A1A2E,
                    ).withAlpha(150),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Send OTP',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ] else ...[
                // OTP Field
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (index) {
                    return SizedBox(
                      width: 48,
                      child: TextField(
                        controller: _otpControllers[index],
                        focusNode: _otpFocusNodes[index],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 1,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF6B8CAE),
                              width: 2,
                            ),
                          ),
                        ),
                        // Handle formatting and moving to next node via inputFormatters / onChange is easier
                        onChanged: (value) {
                          if (value.isNotEmpty && index < 5) {
                            _otpFocusNodes[index + 1].requestFocus();
                          } else if (value.isEmpty && index > 0) {
                            _otpFocusNodes[index - 1].requestFocus();
                          }
                          // remove error when typing
                          if (_errorMessage != null) {
                            setState(() => _errorMessage = null);
                          }
                        },
                      ),
                    );
                  }),
                ),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A2E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor: const Color(
                      0xFF1A1A2E,
                    ).withAlpha(150),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Verify OTP',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                const SizedBox(height: 24),
                // Resend Timer
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _canResend
                          ? "Didn't receive code? "
                          : "Resend code in 00:${_start.toString().padLeft(2, '0')}",
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    if (_canResend)
                      TextButton(
                        onPressed: _verifyPhone,
                        child: const Text(
                          'Resend',
                          style: TextStyle(
                            color: Color(0xFF6B8CAE),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    for (var c in _otpControllers) {
      c.dispose();
    }
    for (var fn in _otpFocusNodes) {
      fn.dispose();
    }
    _timer?.cancel();
    super.dispose();
  }
}
