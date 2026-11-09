/// Colleague directory shapes, taken from `GET /employee/directory/`.
library;

String? _str(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty || text == 'null' ? null : text;
}

int? _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

class DirectoryEntry {
  const DirectoryEntry({
    required this.id,
    required this.name,
    this.badgeId,
    this.photo,
    this.jobPosition,
    this.department,
  });

  final int id;
  final String name;
  final String? badgeId;
  final String? photo;
  final String? jobPosition;
  final String? department;

  factory DirectoryEntry.fromJson(Map<String, dynamic> json) {
    final first = _str(json['first_name']) ?? '';
    final last = _str(json['last_name']) ?? '';
    return DirectoryEntry(
      id: _int(json['id']) ?? 0,
      name: _str(json['name']) ?? '$first $last'.trim(),
      badgeId: _str(json['badge_id']),
      photo: _str(json['photo']),
      jobPosition: _str(json['job_position']),
      department: _str(json['department']),
    );
  }

  /// "Designer · Engineering", "Engineering" or "" depending on what is set.
  String get roleLine =>
      [jobPosition, department].whereType<String>().join(' · ');
}

class DirectoryDepartment {
  const DirectoryDepartment({required this.id, required this.name});

  final int id;
  final String name;

  factory DirectoryDepartment.fromJson(Map<String, dynamic> json) =>
      DirectoryDepartment(
        id: _int(json['id']) ?? 0,
        name: _str(json['name']) ?? 'Department',
      );
}

class DirectoryPage {
  const DirectoryPage({
    required this.entries,
    required this.count,
    required this.hasNext,
    required this.departments,
  });

  final List<DirectoryEntry> entries;
  final int count;
  final bool hasNext;
  final List<DirectoryDepartment> departments;

  factory DirectoryPage.fromJson(Map<String, dynamic> json) {
    final rows = json['results'];
    final depts = json['departments'];
    return DirectoryPage(
      entries: rows is List
          ? rows
                .whereType<Map>()
                .map(
                  (e) => DirectoryEntry.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const [],
      count: _int(json['count']) ?? 0,
      hasNext: _str(json['next']) != null,
      departments: depts is List
          ? depts
                .whereType<Map>()
                .map(
                  (e) => DirectoryDepartment.fromJson(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .toList()
          : const [],
    );
  }
}

class DirectoryDetail {
  const DirectoryDetail({
    required this.entry,
    this.jobRole,
    this.company,
    this.managerId,
    this.managerName,
    this.workSite,
    this.workLocation,
    this.workEmail,
    this.workPhone,
  });

  final DirectoryEntry entry;
  final String? jobRole;
  final String? company;
  final int? managerId;
  final String? managerName;
  final String? workSite;
  final String? workLocation;
  final String? workEmail;
  final String? workPhone;

  factory DirectoryDetail.fromJson(Map<String, dynamic> json) {
    final manager = json['manager'];
    return DirectoryDetail(
      entry: DirectoryEntry.fromJson(json),
      jobRole: _str(json['job_role']),
      company: _str(json['company']),
      managerId: manager is Map ? _int(manager['id']) : null,
      managerName: manager is Map ? _str(manager['name']) : null,
      workSite: _str(json['work_site']),
      workLocation: _str(json['work_location']),
      workEmail: _str(json['work_email']),
      workPhone: _str(json['work_phone']),
    );
  }
}

/// The signed-in employee's assigned site, from `GET /mobile/work-site/`.
class WorkSiteInfo {
  const WorkSiteInfo({
    required this.kind,
    this.name,
    this.company,
    this.latitude,
    this.longitude,
    this.radiusMeters,
    this.geofenceEnabled = false,
    this.location,
  });

  /// `site`, `company` or null when nothing is configured.
  final String? kind;
  final String? name;
  final String? company;
  final double? latitude;
  final double? longitude;
  final int? radiusMeters;
  final bool geofenceEnabled;
  final String? location;

  bool get isConfigured => kind != null;
  bool get hasCoordinates => latitude != null && longitude != null;

  factory WorkSiteInfo.fromJson(Map<String, dynamic> json) {
    double? asDouble(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    return WorkSiteInfo(
      kind: _str(json['kind']),
      name: _str(json['name']),
      company: _str(json['company']),
      latitude: asDouble(json['latitude']),
      longitude: asDouble(json['longitude']),
      radiusMeters: _int(json['radius_in_meters']),
      geofenceEnabled: json['geofence_enabled'] == true,
      location: _str(json['location']),
    );
  }
}
