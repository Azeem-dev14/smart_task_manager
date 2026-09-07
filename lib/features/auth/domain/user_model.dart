/// Domain entity representing an authenticated user profile in the application.
///
/// Corresponds to the Firestore document schema stored at `users/{userId}`:
/// - [uid]: Unique authentication identifier.
/// - [name]: Display name.
/// - [email]: Email address.
/// - [createdAt]: Account creation timestamp.
/// - [themeMode]: User preferred appearance ('system', 'light', 'dark').
class UserModel {
  final String uid;
  final String name;
  final String email;
  final DateTime createdAt;
  final String themeMode;

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.createdAt,
    this.themeMode = 'system',
  });

  /// Returns a copy of this [UserModel] with specified properties replaced.
  UserModel copyWith({
    String? uid,
    String? name,
    String? email,
    DateTime? createdAt,
    String? themeMode,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  /// Serializes this model into a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'createdAt': createdAt.toIso8601String(),
      'themeMode': themeMode,
    };
  }

  /// Deserializes a [UserModel] from a JSON map.
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      uid: json['uid']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      themeMode: json['themeMode']?.toString() ?? 'system',
    );
  }
}
