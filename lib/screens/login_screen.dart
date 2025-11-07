import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
   @override
  LoginScreenState createState() => LoginScreenState(); 
}

class LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    print('🔓 LoginScreen initialized');
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    await Future.delayed(Duration(milliseconds: 100));
    
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.initialize();
    
    print('🔐 LoginScreen - Current auth status: ${authProvider.isLoggedIn}');
    
    if (authProvider.isLoggedIn && mounted) {
      print('🚀 User already logged in, redirecting to chats...');
      Navigator.pushReplacementNamed(context, '/chats');
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      print('❌ Form validation failed');
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      print('🔄 LoginScreen: Starting login process...');
      print('   📧 Email: ${_emailController.text.trim()}');
      
      await authProvider.login(
        _emailController.text.trim(),
        _passwordController.text,
      );
      
      print('✅ LoginScreen: Login successful!');
      print('   🔐 isLoggedIn: ${authProvider.isLoggedIn}');
      print('   👤 User: ${authProvider.email}');
      
      await Future.delayed(Duration(milliseconds: 500));
      
      if (authProvider.isLoggedIn && mounted) {
        print('🚀 Navigating to chats screen...');
        Navigator.pushReplacementNamed(context, '/chats');
      } else {
        print('❌ Login successful but user not logged in?');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Login failed - please try again'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ LoginScreen: Login error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email';
    }
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  void _navigateToRegister() {
    print('🔄 Navigating to register screen...');
    Navigator.pushNamed(context, '/register');
  }

  void _navigateToDebug() {
    print('🔄 Navigating to debug screen...');
    Navigator.pushNamed(context, '/debug');
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Login to Secret Chat'),
        actions: [
          IconButton(
            icon: Icon(Icons.bug_report),
            onPressed: _navigateToDebug,
            tooltip: 'Debug Info',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 40),
              // Header
              Icon(
                Icons.chat,
                size: 80,
                color: Colors.blue,
              ),
              SizedBox(height: 20),
              Text(
                'Secret Chat',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Secure encrypted messaging',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              SizedBox(height: 40),
              
              // Email Field
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                  hintText: 'your@email.com',
                ),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                validator: _validateEmail,
                onFieldSubmitted: (_) {
                  FocusScope.of(context).nextFocus();
                },
              ),
              SizedBox(height: 20),

              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                  hintText: 'Enter your password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                  ),
                ),
                obscureText: !_isPasswordVisible,
                textInputAction: TextInputAction.done,
                validator: _validatePassword,
                onFieldSubmitted: (_) => _login(),
              ),
              SizedBox(height: 30),

              // Login Button
              authProvider.isLoading
                  ? Center(
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Signing in...'),
                        ],
                      ),
                    )
                  : ElevatedButton(
                      onPressed: _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        minimumSize: Size(double.infinity, 56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Sign In',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
              SizedBox(height: 20),

              // Register Link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Don\'t have an account?'),
                  TextButton(
                    onPressed: _navigateToRegister,
                    child: Text(
                      'Create Account',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),

              if (authProvider.isLoggedIn) ...[
                Card(
                  color: Colors.orange[50],
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Debug Info:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[800],
                          ),
                        ),
                        SizedBox(height: 8),
                        Text('Already logged in as: ${authProvider.email}'),
                        Text('User PIN: ${authProvider.userPin}'),
                        SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pushReplacementNamed(context, '/chats');
                          },
                          child: Text('Go to Chats'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}