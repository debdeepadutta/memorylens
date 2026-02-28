import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  // Get current user stream
  static Stream<User?> get userStream => _auth.authStateChanges();

  static User? get currentUser => _auth.currentUser;

  // Sign up with Email and Password
  static Future<UserCredential> signUpWithEmail(
    String email,
    String password,
  ) async {
    return await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // Sign in with Email and Password
  static Future<UserCredential> signInWithEmail(
    String email,
    String password,
  ) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  static bool _isGoogleSignInInitialized = false;

  // Google Sign In
  static Future<UserCredential?> signInWithGoogle() async {
    if (!_isGoogleSignInInitialized) {
      await _googleSignIn.initialize(
        serverClientId:
            '1014343078519-lpfatntkc3lhi6tgnhaegd1pelmfu9in.apps.googleusercontent.com',
      );
      _isGoogleSignInInitialized = true;
    }

    final GoogleSignInAccount? authAccount =
        await _googleSignIn.attemptLightweightAuthentication() ??
        await _googleSignIn.authenticate();

    if (authAccount == null) return null; // User canceled

    final GoogleSignInAuthentication googleAuth = authAccount.authentication;
    final GoogleSignInClientAuthorization? authClient = await authAccount
        .authorizationClient
        .authorizationForScopes(['email']);

    final OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: authClient?.accessToken,
      idToken: googleAuth.idToken,
    );

    return await _auth.signInWithCredential(credential);
  }

  // Send Password Reset Email
  static Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // Sign Out
  static Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
