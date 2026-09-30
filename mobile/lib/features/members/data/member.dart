enum AccessLevel {
  member('Membre'),
  manager('Manager'),
  admin('Administrateur');

  const AccessLevel(this.label);

  final String label;

  static AccessLevel fromJson(String value) =>
      values.firstWhere((level) => level.name == value, orElse: () => member);
}

class Member {
  const Member({
    required this.id,
    required this.email,
    required this.fullName,
    required this.accessLevel,
    required this.skills,
    required this.availability,
    required this.isActive,
    this.jobTitle,
    this.photoUrl,
    this.createdAt,
  });

  factory Member.fromJson(Map<String, dynamic> json) => Member(
    id: json['id'] as String,
    email: json['email'] as String,
    fullName: json['full_name'] as String,
    jobTitle: json['job_title'] as String?,
    photoUrl: json['photo_url'] as String?,
    accessLevel: AccessLevel.fromJson(json['access_level'] as String),
    skills: List<String>.unmodifiable(json['skills'] as List<dynamic>),
    availability: json['availability'] as int,
    isActive: json['is_active'] as bool,
    createdAt: json['created_at'] == null ? null : DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String email;
  final String fullName;
  final String? jobTitle;
  final String? photoUrl;
  final AccessLevel accessLevel;
  final List<String> skills;

  /// Disponibilité en pourcentage (0–100).
  final int availability;
  final bool isActive;
  final DateTime? createdAt;

  bool get canCreateProjects =>
      accessLevel == AccessLevel.manager || accessLevel == AccessLevel.admin;

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.take(2).map((p) => p.isEmpty ? '' : p[0].toUpperCase()).join();
  }
}
