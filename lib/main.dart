import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/app_constants.dart';
import 'config/env_loader.dart';
import 'config/lib/config/app_routes.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/verify_screen.dart';
import 'screens/chat_list_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/profile_screen.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) {
    debugPrint('🚀 Starting ${AppConstants.appName}...');
  }

  try {
    // Load environment variables
    await EnvLoader.load();
    
    if (kDebugMode) {
      debugPrint('✅ Environment loaded successfully');
      // Print debug info tanpa expose sensitive data
      final envVars = EnvLoader.getAll();
      debugPrint('📋 Loaded ${envVars.length} environment variables');
      
      final hasSupabaseUrl = AppConstants.supabaseUrl.isNotEmpty;
      final hasSupabaseKey = AppConstants.supabaseAnonKey.isNotEmpty;
      
      debugPrint('🔑 SUPABASE_URL: ${hasSupabaseUrl ? "✓ SET" : "✗ MISSING"}');
      debugPrint('🔑 SUPABASE_ANON_KEY: ${hasSupabaseKey ? "✓ SET" : "✗ MISSING"}');
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('❌ Error loading environment: $e');
    }
    // Jangan crash app, lanjut dengan values kosong
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AuthProvider _authProvider = AuthProvider();
  final SupabaseService _supabaseService = SupabaseService();

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      if (kDebugMode) {
        debugPrint('🎯 Initializing application...');
      }

      await _authProvider.initialize();

      if (kDebugMode) {
        debugPrint('✅ App initialization completed');
        debugPrint('🔐 Auth status: ${_authProvider.isLoggedIn ? "LOGGED IN" : "NOT LOGGED IN"}');
        debugPrint('🗃️ Encrypted tables: Initialized');
        debugPrint('🔐 Encryption: Camellia-256 + XOR systems ready');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ App initialization failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authProvider)
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        initialRoute: AppRoutes.splash,
        routes: {
          AppRoutes.splash: (context) => const SplashScreen(),
          AppRoutes.login: (context) => const LoginScreen(),
          AppRoutes.register: (context) => const RegisterScreen(),
          AppRoutes.verify: (context) => const VerifyScreen(),
          AppRoutes.chats: (context) => const ChatListScreen(),
          AppRoutes.chat: (context) {
            final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
            return ChatScreen(
              chatId: args['chatId'],
              otherUserName: args['otherUserName'],
              otherUserPin: args['otherUserPin'],
            );
          },
          AppRoutes.profile: (context) => const ProfileScreen(),
        },
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Tunggu minimal 2 detik untuk splash screen
    await Future.delayed(const Duration(seconds: 2));

    if (kDebugMode) {
      debugPrint('🔐 Checking authentication status...');
    }

    try {
      await authProvider.checkAuthStatus();

      if (authProvider.isLoggedIn) {
        if (kDebugMode) {
          debugPrint('🚀 User is logged in, navigating to chats...');
        }
        if (mounted) {
          Navigator.pushReplacementNamed(context, AppRoutes.chats);
        }
      } else {
        if (kDebugMode) {
          debugPrint('🔓 User not logged in, navigating to login...');
        }
        if (mounted) {
          Navigator.pushReplacementNamed(context, AppRoutes.login);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Auth check error: $e');
      }
      // Fallback ke login screen jika ada error
      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.login);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: Colors.white,
            ),
            const SizedBox(height: 20),
            Text(
              AppConstants.appName,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Secure Encrypted Messaging',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 10),
            const Text(
              'Camellia-256 + XOR Encryption',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 30),
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 20),
            const Text(
              'Loading Security Systems...',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}