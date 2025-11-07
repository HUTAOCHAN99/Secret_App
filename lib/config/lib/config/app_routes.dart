// secret_app/lib/config/app_routes.dart
class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String verify = '/verify';
  static const String chats = '/chats';
  static const String chat = '/chat';
  static const String profile = '/profile';

  static Map<String, String> get routeNames {
    return {
      splash: 'Splash',
      login: 'Login',
      register: 'Register',
      verify: 'Verify',
      chats: 'Chats',
      chat: 'Chat',
      profile: 'Profile',
    };
  }

  static List<String> get publicRoutes {
    return [splash, login, register, verify];
  }

  static List<String> get protectedRoutes {
    return [chats, chat, profile];
  }

  static bool isPublicRoute(String route) {
    return publicRoutes.contains(route);
  }

  static bool isProtectedRoute(String route) {
    return protectedRoutes.contains(route);
  }
}