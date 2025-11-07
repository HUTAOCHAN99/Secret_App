class User {
  final String id;
  final String email;
  final String displayName;
  final String userPin;
  final bool isVerified;
  final DateTime? createdAt;

  User({
    required this.id,
    required this.email,
    required this.displayName,
    required this.userPin,
    required this.isVerified,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      displayName: json['display_name'] ?? '',
      userPin: json['user_pin'] ?? '',
      isVerified: json['is_verified'] ?? false,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']).toLocal()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'display_name': displayName,
      'user_pin': userPin,
      'is_verified': isVerified,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  User copyWith({
    String? id,
    String? email,
    String? displayName,
    String? userPin,
    bool? isVerified,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      userPin: userPin ?? this.userPin,
      isVerified: isVerified ?? this.isVerified,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'User(id: $id, email: $email, displayName: $displayName, userPin: $userPin, isVerified: $isVerified)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
  
    return other is User &&
      other.id == id &&
      other.email == email &&
      other.displayName == displayName &&
      other.userPin == userPin &&
      other.isVerified == isVerified;
  }

  @override
  int get hashCode {
    return id.hashCode ^
      email.hashCode ^
      displayName.hashCode ^
      userPin.hashCode ^
      isVerified.hashCode;
  }
}

class AuthResponse {
  final String accessToken;
  final String tokenType;
  final String userId;
  final String email;
  final String displayName;
  final String userPin;

  AuthResponse({
    required this.accessToken,
    required this.tokenType,
    required this.userId,
    required this.email,
    required this.displayName,
    required this.userPin,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      accessToken: json['access_token'] ?? '',
      tokenType: json['token_type'] ?? 'bearer',
      userId: json['user_id'] ?? '',
      email: json['email'] ?? '',
      displayName: json['display_name'] ?? '',
      userPin: json['user_pin'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      'token_type': tokenType,
      'user_id': userId,
      'email': email,
      'display_name': displayName,
      'user_pin': userPin,
    };
  }

  User toUser() {
    return User(
      id: userId,
      email: email,
      displayName: displayName,
      userPin: userPin,
      isVerified: true,
    );
  }

  @override
  String toString() {
    return 'AuthResponse(accessToken: $accessToken, tokenType: $tokenType, userId: $userId, email: $email, displayName: $displayName, userPin: $userPin)';
  }
}

class UserSearchResult {
  final String id;
  final String displayName;
  final String userPin;

  UserSearchResult({
    required this.id,
    required this.displayName,
    required this.userPin,
  });

  factory UserSearchResult.fromJson(Map<String, dynamic> json) {
    return UserSearchResult(
      id: json['id'] ?? '',
      displayName: json['display_name'] ?? '',
      userPin: json['user_pin'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'display_name': displayName,
      'user_pin': userPin,
    };
  }

  @override
  String toString() {
    return 'UserSearchResult(id: $id, displayName: $displayName, userPin: $userPin)';
  }
}

class RegisterRequest {
  final String email;
  final String password;
  final String displayName;

  RegisterRequest({
    required this.email,
    required this.password,
    required this.displayName,
  });

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'password': password,
      'display_name': displayName,
    };
  }
}

class LoginRequest {
  final String email;
  final String password;

  LoginRequest({
    required this.email,
    required this.password,
  });

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'password': password,
    };
  }
}

class VerifyRequest {
  final String email;
  final String code;

  VerifyRequest({
    required this.email,
    required this.code,
  });

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'code': code,
    };
  }
}