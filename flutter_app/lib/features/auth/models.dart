class AuthSession {
  const AuthSession({
    required this.access,
    required this.refresh,
    required this.employeeId,
    required this.fullName,
    this.avatarUrl,
    this.geoFencing = false,
  });

  final String access;
  final String refresh;
  final int employeeId;
  final String fullName;
  final String? avatarUrl;
  final bool geoFencing;

  factory AuthSession.fromLoginJson(Map<String, dynamic> json) {
    final employee = json['employee'] as Map<String, dynamic>? ?? {};
    return AuthSession(
      access: json['access'] as String,
      refresh: json['refresh'] as String? ?? '',
      employeeId: employee['id'] as int? ?? 0,
      fullName: employee['full_name'] as String? ??
          employee['employee_first_name'] as String? ??
          'Employee',
      avatarUrl: employee['employee_profile'] as String? ??
          employee['get_avatar'] as String?,
      geoFencing: json['geo_fencing'] as bool? ?? false,
    );
  }

  String get firstName {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? 'there' : parts.first;
  }
}
