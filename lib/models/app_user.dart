/// The signed-in person. [id] is the local row id as text, or the Firebase uid.
class AppUser {
  final String id;
  final String name;
  final String email;
  final String currencyCode;
  final DateTime createdAt;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.currencyCode,
    required this.createdAt,
  });

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  String get initial => name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  AppUser copyWith({String? name, String? currencyCode}) => AppUser(
        id: id,
        name: name ?? this.name,
        email: email,
        currencyCode: currencyCode ?? this.currencyCode,
        createdAt: createdAt,
      );

  factory AppUser.fromMap(Map<String, Object?> map) => AppUser(
        id: map['id'].toString(),
        name: map['name'] as String,
        email: map['email'] as String,
        currencyCode: map['currency'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );
}
