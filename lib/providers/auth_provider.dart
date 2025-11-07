// secret_app/lib/providers/auth_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/crypto_auth_ffi.dart';
import '../services/supabase_service.dart';
import '../services/crypto_auth.dart';
import '../services/crypto_service_factory.dart';
import '../config/supabase_config.dart';

class AuthProvider with ChangeNotifier {
  User? _user;
  String? _userPin;
  String? _displayName;
  String? _email;
  bool _isLoading = false;
  String? _error;
  bool _isInitialized = false;
  
  late final dynamic _cryptoService;
  bool _useArgon2 = false;

  BuildContext? _context;
  
  void setContext(BuildContext context) {
    _context = context;
  }

  bool get _mounted => _context != null;
  
  User? get user => _user;
  String? get userPin => _userPin;
  String? get displayName => _displayName;
  String? get email => _email;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _user != null;
  bool get isInitialized => _isInitialized;
  String? get userId => _user?.id;
  bool get useArgon2 => _useArgon2;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (kDebugMode) {
        debugPrint('🔄 Initializing AuthProvider with Hybrid Crypto Auth...');
      }
      _setLoading(true);

      _initializeCrypto();

      await SupabaseConfig.initialize();

      if (SupabaseConfig.isAvailable) {
        final supabaseService = SupabaseService();
        _user = supabaseService.currentUser;

        if (_user != null) {
          await _loadUserProfile();
          if (kDebugMode) {
            debugPrint('✅ AuthProvider initialized with user: ${_user!.email}');
          }
        } else {
          if (kDebugMode) {
            debugPrint('ℹ️ AuthProvider initialized - no user logged in');
          }
        }

        _setupAuthListener();
      } else {
        if (kDebugMode) {
          debugPrint('⚠️ Supabase not available - running in limited mode');
        }
      }

      _isInitialized = true;
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error initializing AuthProvider: $e');
      }
      _error = e.toString();
      _setLoading(false);
      notifyListeners();
    }
  }

  void _initializeCrypto() {
    try {
      _cryptoService = CryptoServiceFactory.getCryptoService();

      _useArgon2 = _cryptoService is CryptoAuthFFI && _cryptoService.isAvailable;
      
      if (kDebugMode) {
        final engineInfo = CryptoServiceFactory.getCryptoEngineInfo();
        if (_useArgon2) {
          debugPrint('🚀 Using ARGON2ID + SHA3-512 (Native FFI)');
        } else {
          debugPrint('⚡ Using PBKDF2-like + SHA-256-like (Dart Fallback)');
        }
        debugPrint('   🔧 Engine: ${engineInfo['engine']}');
        debugPrint('   📊 Algorithm: ${engineInfo['algorithm']}');
        debugPrint('   🛡️ Security: ${engineInfo['security_level']}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Crypto initialization failed, using fallback: $e');
      }
      _cryptoService = CryptoAuthService();
      _useArgon2 = false;
    }
  }

  Future<void> _loadUserProfile() async {
    if (_user == null || !SupabaseConfig.isAvailable) return;

    try {
      if (kDebugMode) {
        debugPrint('🔄 Loading user profile from Supabase...');
      }
      final supabaseService = SupabaseService();
      final profile = await supabaseService.getUserProfile(_user!.id);

      if (profile != null) {
        _userPin = profile['user_pin']?.toString();
        _displayName = profile['display_name']?.toString();
        _email = profile['email']?.toString();

        if (kDebugMode) {
          debugPrint('✅ User profile loaded successfully');
          debugPrint('   📌 PIN: $_userPin');
          debugPrint('   👋 Name: $_displayName');
        }
      } else {
        if (kDebugMode) {
          debugPrint('⚠️ User profile not found in Supabase');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error loading user profile: $e');
      }
    }
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _setLoading(true);
    _error = null;

    try {
      if (kDebugMode) {
        debugPrint('🔄 Starting registration with HYBRID CRYPTO AUTH...');
        final engineInfo = CryptoServiceFactory.getCryptoEngineInfo();
        debugPrint('   🔧 Crypto Engine: ${engineInfo['algorithm']}');
      }

      final passwordStrength = _validatePasswordStrength(password);
      if (!passwordStrength.isValid) {
        throw Exception('Password too weak: ${passwordStrength.issues.join(', ')}');
      }

      if (kDebugMode) {
        debugPrint('✅ Password strength: ${passwordStrength.strength} (Score: ${passwordStrength.score}/${passwordStrength.maxScore})');
      }

      final challenge = _generateRegistrationChallenge(email, displayName);
      final authData = await _performRegistrationAuth(
        password: password,
        challenge: challenge,
      );

      if (!SupabaseConfig.isAvailable) {
        throw Exception('Supabase not configured. Please check your .env file');
      }

      final supabaseService = SupabaseService();
      final result = await supabaseService.signUpWithCrypto(
        email: email,
        password: password,
        displayName: displayName,
        passwordHash: authData['passwordHash'],
        salt: authData['salt'],
      );

      if (result['success'] != true) {
        throw Exception(result['error']?.toString() ?? 'Registration failed');
      }

      final userId = result['user_id']?.toString();
      final userPin = result['user_pin']?.toString();
      
      if (userId == null || userId.isEmpty) {
        throw Exception('Registration failed - user ID is null or empty');
      }
      
      if (userPin == null || userPin.isEmpty) {
        throw Exception('Registration failed - user PIN is null or empty');
      }

      _user = supabaseService.currentUser;
      _userPin = userPin;
      _displayName = displayName;
      _email = email;

      if (kDebugMode) {
        debugPrint('✅ Registration successful!');
        debugPrint('   📧 Email: $email');
        debugPrint('   📌 Generated PIN: $userPin');
        debugPrint('   👤 User ID: $userId');
        debugPrint('   🔐 Security: ${_useArgon2 ? "Argon2id + SHA3-512" : "PBKDF2-like + SHA-256-like"}');
        debugPrint('   📧 OTP email sent to: $email');
      }

      _setLoading(false);
      notifyListeners();

      return {
        'success': true,
        'user_id': userId,
        'email': email,
        'display_name': displayName,
        'user_pin': userPin,
        'security_level': _useArgon2 ? 'argon2id_sha3_512' : 'pbkdf2_sha256',
        'crypto_engine': _useArgon2 ? 'native_ffi' : 'dart_fallback',
      };
    } catch (e) {
      _error = e.toString();
      if (kDebugMode) {
        debugPrint('❌ Registration failed: $e');
      }
      _setLoading(false);
      notifyListeners();
      rethrow;
    }
  }

  Future<dynamic> _performHybridAuthentication({
    required String password,
    required String challenge,
    String? storedHash,
    String? storedSalt,
  }) async {
    try {
      if (_useArgon2) {

        return await _cryptoService.hybridAuthenticate(
          password: password,
          challenge: challenge,
          storedHash: storedHash,
          storedSalt: storedSalt,
        );
      } else {
        return await _cryptoService.hybridAuthenticate(
          password: password,
          challenge: challenge,
          storedHash: storedHash,
          storedSalt: storedSalt,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Hybrid auth failed, using Dart fallback: $e');
      }

      final fallbackService = CryptoAuthService();
      return await fallbackService.hybridAuthenticate(
        password: password,
        challenge: challenge,
        storedHash: storedHash,
        storedSalt: storedSalt,
      );
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    _setLoading(true);
    _error = null;

    try {
      if (kDebugMode) {
        debugPrint('🔄 Starting login process with HYBRID CRYPTO...');
        final engineInfo = CryptoServiceFactory.getCryptoEngineInfo();
        debugPrint('   🔧 Crypto Engine: ${engineInfo['algorithm']}');
      }

      if (!SupabaseConfig.isAvailable) {
        throw Exception('Supabase not configured. Please check your .env file');
      }

      final supabaseService = SupabaseService();
      final isVerified = await supabaseService.isEmailVerified(email);
      
      if (!isVerified) {
        throw Exception('Please verify your email first. Check your email for OTP code.');
      }

      final userAuthData = await supabaseService.getUserAuthData(email);
      
      if (userAuthData == null) {
        throw Exception('User not found or invalid credentials');
      }

      if (userAuthData['password_hash'] != null && userAuthData['salt'] != null) {
        final challenge = _generateLoginChallenge();
        try {
          final authResult = await _performHybridAuthentication(
            password: password,
            challenge: challenge,
            storedHash: userAuthData['password_hash'],
            storedSalt: userAuthData['salt'],
          );

          if (!authResult.success) {
            throw Exception('Invalid password');
          }

          if (kDebugMode) {
            debugPrint('✅ Password verification successful with hybrid crypto auth');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Crypto auth failed, trying legacy login: $e');
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint('ℹ️ User has no crypto data, using legacy login');
        }
      }

      final response = await supabaseService.signIn(email, password);

      if (response.user != null) {
        _user = response.user;
        await _loadUserProfile();

        if (kDebugMode) {
          debugPrint('✅ Login successful!');
          debugPrint('   👤 User: ${_user!.email}');
          debugPrint('   📌 PIN: $_userPin');
          debugPrint('   👋 Name: $_displayName');
        }

        _setLoading(false);
        notifyListeners();

        return {
          'user_id': _user!.id,
          'email': _user!.email,
          'display_name': _displayName,
          'user_pin': _userPin,
          'security_level': userAuthData['password_hash'] != null ? 
            (_useArgon2 ? 'argon2id_sha3_512' : 'pbkdf2_sha256') : 'legacy',
        };
      } else {
        throw Exception('Login failed - no user returned');
      }
    } catch (e) {
      _error = e.toString();
      if (kDebugMode) {
        debugPrint('❌ Login failed: $e');
      }
      _setLoading(false);
      notifyListeners();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _performRegistrationAuth({
    required String password,
    required String challenge,
  }) async {
    try {
      final authResult = await _performHybridAuthentication(
        password: password,
        challenge: challenge,
      );

      return {
        'passwordHash': authResult.passwordHash,
        'salt': authResult.salt,
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Auth failed, using direct Dart service: $e');
      }

      final fallbackService = CryptoAuthService();
      final result = await fallbackService.hybridAuthenticate(
        password: password,
        challenge: challenge,
      );
      
      return {
        'passwordHash': result.passwordHash,
        'salt': result.salt,
      };
    }
  }

  Future<void> verify(String email, String otpCode) async {
    _setLoading(true);
    _error = null;

    try {
      if (kDebugMode) {
        debugPrint('🔄 Verifying OTP code from email...');
      }

      if (!SupabaseConfig.isAvailable) {
        throw Exception('Supabase not configured');
      }

      final supabaseService = SupabaseService();
      
      final isValid = await supabaseService.verifyEmailOtp(email, otpCode);

      if (!isValid) {
        throw Exception('Invalid or expired OTP code');
      }

      await _loadUserProfile();

      if (kDebugMode) {
        debugPrint('✅ OTP verification successful!');
      }

      _setLoading(false);
      notifyListeners();
      
    } catch (e) {
      _error = e.toString();
      if (kDebugMode) {
        debugPrint('❌ OTP verification failed: $e');
      }
      _setLoading(false);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> resendOtp(String email) async {
    _setLoading(true);
    _error = null;

    try {
      if (kDebugMode) {
        debugPrint('🔄 Resending OTP email to: $email');
      }

      if (!SupabaseConfig.isAvailable) {
        throw Exception('Supabase not configured');
      }

      final supabaseService = SupabaseService();
      await supabaseService.resendVerificationEmail(email);

      if (kDebugMode) {
        debugPrint('✅ OTP email resent! Check your email.');
      }

      _setLoading(false);
      notifyListeners();

      if (_mounted && _context != null) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          SnackBar(
            content: Text('Verification code sent to $email'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _error = e.toString();
      if (kDebugMode) {
        debugPrint('❌ Failed to resend OTP email: $e');
      }
      _setLoading(false);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 Logging out from Supabase...');
      }
      _setLoading(true);

      if (SupabaseConfig.isAvailable) {
        final supabaseService = SupabaseService();
        await supabaseService.signOut();
      }

      // Reset state
      _user = null;
      _userPin = null;
      _displayName = null;
      _email = null;
      _error = null;

      if (kDebugMode) {
        debugPrint('✅ User logged out successfully');
      }
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error during logout: $e');
      }
      _error = e.toString();
      _setLoading(false);
      notifyListeners();
      throw Exception('Logout failed: $e');
    }
  }

  Future<void> checkAuthStatus() async {
    try {
      await initialize();
      if (kDebugMode) {
        debugPrint('🔐 Auth status: ${isLoggedIn ? "LOGGED IN" : "NOT LOGGED IN"}');
        if (isLoggedIn) {
          debugPrint('👤 Current user: $_email');
          final engineInfo = CryptoServiceFactory.getCryptoEngineInfo();
          debugPrint('   🔐 Crypto Engine: ${engineInfo['algorithm']}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error checking auth status: $e');
      }
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setupAuthListener() {
    if (!SupabaseConfig.isAvailable) return;

    final supabaseService = SupabaseService();
    supabaseService.client.auth.onAuthStateChange.listen((AuthState data) {
      final AuthChangeEvent event = data.event;

      if (kDebugMode) {
        debugPrint('🔐 Auth state changed: $event');
      }

      if (event == AuthChangeEvent.signedIn) {
        _user = data.session?.user;
        if (_user != null) {
          _loadUserProfile();
        }
        notifyListeners();
      } else if (event == AuthChangeEvent.signedOut) {
        _user = null;
        _userPin = null;
        _displayName = null;
        _email = null;
        notifyListeners();
      }
    });
  }

  // Helper methods untuk challenge generation
  String _generateRegistrationChallenge(String email, String displayName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'reg_${email}_${displayName}_$timestamp';
  }

  String _generateLoginChallenge() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'login_${_email}_$timestamp';
  }

  PasswordStrength _validatePasswordStrength(String password) {
    int score = 0;
    final issues = <String>[];

    if (password.length >= 8) {
      score += 1;
    } else {
      issues.add('At least 8 characters');
    }

    if (RegExp(r'[A-Z]').hasMatch(password)) {
      score += 1;
    } else {
      issues.add('Uppercase letters');
    }

    if (RegExp(r'[a-z]').hasMatch(password)) {
      score += 1;
    } else {
      issues.add('Lowercase letters');
    }

    if (RegExp(r'[0-9]').hasMatch(password)) {
      score += 1;
    } else {
      issues.add('Numbers');
    }

    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) {
      score += 1;
    } else {
      issues.add('Special characters');
    }

    return PasswordStrength(
      score: score,
      strength: score >= 4 ? 'Strong' : score >= 3 ? 'Medium' : 'Weak',
      maxScore: 5,
      issues: issues,
      isValid: score >= 3,
    );
  }

  Future<void> testCryptoFunctions() async {
    try {
      if (kDebugMode) {
        debugPrint('🧪 Testing crypto functions...');
      }

      final testResults = await CryptoServiceFactory.testAllServices();
      
      for (final entry in testResults.entries) {
        debugPrint('   ${entry.key}: ${entry.value['available'] ? '✅' : '❌'} ${entry.value['algorithm'] ?? ''}');
        if (!entry.value['available']) {
          debugPrint('      Error: ${entry.value['error']}');
        }
      }

      debugPrint('🎉 Crypto test completed');
    } catch (e) {
      debugPrint('❌ Crypto test failed: $e');
    }
  }

  Map<String, dynamic>? get userData {
    if (!isLoggedIn) return null;

    final engineInfo = CryptoServiceFactory.getCryptoEngineInfo();
    return {
      'userId': _user!.id,
      'email': _email,
      'displayName': _displayName,
      'userPin': _userPin,
      'cryptoEngine': engineInfo['engine'],
      'algorithm': engineInfo['algorithm'],
    };
  }

  void printDebugInfo() {
    if (kDebugMode) {
      debugPrint('\n🔍 AUTH PROVIDER DEBUG INFO:');
      debugPrint('   isInitialized: $_isInitialized');
      debugPrint('   isLoggedIn: $isLoggedIn');
      debugPrint('   isLoading: $_isLoading');
      debugPrint('   email: $_email');
      debugPrint('   displayName: $_displayName');
      debugPrint('   userPin: $_userPin');
      debugPrint('   userId: ${_user?.id ?? "null"}');
      debugPrint('   error: $_error');
      debugPrint('   Supabase Available: ${SupabaseConfig.isAvailable}');
      
      final engineInfo = CryptoServiceFactory.getCryptoEngineInfo();
      debugPrint('   Crypto Engine: ${engineInfo['engine']}');
      debugPrint('   Algorithm: ${engineInfo['algorithm']}');
      debugPrint('   Security Level: ${engineInfo['security_level']}');
    }
  }

  @override
  String toString() {
    final engineInfo = CryptoServiceFactory.getCryptoEngineInfo();
    return 'AuthProvider{isLoggedIn: $isLoggedIn, email: $_email, cryptoEngine: ${engineInfo['engine']}}';
  }
}

class PasswordStrength {
  final int score;
  final String strength;
  final int maxScore;
  final List<String> issues;
  final bool isValid;

  PasswordStrength({
    required this.score,
    required this.strength,
    required this.maxScore,
    required this.issues,
    required this.isValid,
  });
}