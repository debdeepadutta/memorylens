import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Data Detection Regex Tests', () {
    test('OTP Detection', () {
      final otpRegex = RegExp(
        r'(?:otp|code|verification|verify|pin|is|#)\D*(\b\d{4,6}\b)',
        caseSensitive: false,
      );

      expect(otpRegex.firstMatch("Your OTP is 1234")?.group(1), "1234");
      expect(
        otpRegex.firstMatch("Verification code: 567890")?.group(1),
        "567890",
      );
      expect(otpRegex.firstMatch("Your code is #9999")?.group(1), "9999");
      expect(otpRegex.firstMatch("PIN: 1234")?.group(1), "1234");
    });

    test('Phone Number Detection', () {
      final phoneRegex = RegExp(
        r'(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}',
      );

      final matches = phoneRegex
          .allMatches("Call us at +1-800-555-0199 or 555 123 4567")
          .map((m) => m.group(0))
          .toList();
      expect(matches.contains("+1-800-555-0199"), true);
      expect(matches.contains("555 123 4567"), true);
    });

    test('URL Detection', () {
      final urlRegex = RegExp(
        r'https?:\/\/(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&//=]*)',
        caseSensitive: false,
      );

      final matches = urlRegex
          .allMatches("Visit https://google.com or http://example.org/path?q=1")
          .map((m) => m.group(0))
          .toList();
      expect(matches.contains("https://google.com"), true);
      expect(matches.contains("http://example.org/path?q=1"), true);
    });

    test('Email Detection', () {
      final emailRegex = RegExp(
        r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
        caseSensitive: false,
      );

      final matches = emailRegex
          .allMatches("Contact info@test.com or support@example.co.uk")
          .map((m) => m.group(0))
          .toList();
      expect(matches.contains("info@test.com"), true);
      expect(matches.contains("support@example.co.uk"), true);
    });
  });
}
