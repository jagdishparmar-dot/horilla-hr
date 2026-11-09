class MobileHome {
  MobileHome({
    required this.employeeId,
    required this.employeeName,
    required this.avatarUrl,
    required this.isClockedIn,
    required this.clockInTime,
    required this.worked,
    required this.breakTime,
    required this.overtime,
    required this.geofenceEnabled,
    this.geofenceName,
    this.geofenceLatitude,
    this.geofenceLongitude,
    this.geofenceRadiusMeters,
    this.clockOutTime,
    this.lastActivityAt,
    this.unreadNotifications = 0,
    this.badgeId,
    this.email,
    this.phone,
    this.jobPosition,
    this.department,
    this.shiftId,
    this.workTypeId,
    this.workSchedule,
    this.announcement,
    this.recentRequests = const [],
    this.birthdays = const [],
    this.newHires = const [],
    this.punches = const [],
    DateTime? fetchedAt,
  }) : fetchedAt = fetchedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final int? employeeId;
  final String employeeName;
  final String? avatarUrl;
  final String? badgeId;
  final String? email;
  final String? phone;
  final String? jobPosition;
  final String? department;
  final int? shiftId;
  final int? workTypeId;
  final bool isClockedIn;
  final String? clockInTime;
  final String? clockOutTime;
  final String? lastActivityAt;
  final String worked;
  final String breakTime;
  final String overtime;
  final bool geofenceEnabled;
  final String? geofenceName;
  final double? geofenceLatitude;
  final double? geofenceLongitude;
  final int? geofenceRadiusMeters;
  final int unreadNotifications;
  final HomeWorkSchedule? workSchedule;
  final HomeAnnouncement? announcement;
  final List<HomeRecentRequest> recentRequests;
  final List<HomeColleague> birthdays;
  final List<HomeColleague> newHires;
  final List<HomePunch> punches;

  /// When this payload was parsed. While clocked in, the worked timer adds
  /// time since this moment onto the server total, which already includes
  /// every session today.
  final DateTime fetchedAt;

  factory MobileHome.fromJson(Map<String, dynamic> json) {
    final employee = json['employee'] as Map<String, dynamic>? ?? {};
    final punch = json['punch'] as Map<String, dynamic>? ?? {};
    final today = json['today'] as Map<String, dynamic>? ?? {};
    final geofence = json['geofence'] as Map<String, dynamic>? ?? {};
    final schedule = json['work_schedule'] as Map<String, dynamic>?;
    final announcement = json['announcement'] as Map<String, dynamic>?;

    return MobileHome(
      employeeId: employee['id'] as int?,
      employeeName: employee['name'] as String? ?? 'Employee',
      avatarUrl: employee['avatar'] as String?,
      badgeId: employee['badge_id'] as String?,
      email: employee['email'] as String?,
      phone: employee['phone'] as String?,
      jobPosition: employee['job_position'] as String?,
      department: employee['department'] as String?,
      shiftId: employee['shift_id'] as int?,
      workTypeId: employee['work_type_id'] as int?,
      isClockedIn: punch['is_clocked_in'] as bool? ?? false,
      clockInTime: punch['clock_in_time'] as String?,
      clockOutTime: punch['clock_out_time'] as String?,
      lastActivityAt: punch['last_activity_at'] as String?,
      worked: today['worked'] as String? ?? '00:00:00',
      breakTime: today['break'] as String? ?? '00:00:00',
      overtime: today['overtime'] as String? ?? '00:00:00',
      geofenceEnabled: geofence['enabled'] as bool? ?? false,
      geofenceName: geofence['name'] as String?,
      geofenceLatitude: _asDouble(geofence['latitude']),
      geofenceLongitude: _asDouble(geofence['longitude']),
      geofenceRadiusMeters: _asInt(geofence['radius_in_meters']),
      unreadNotifications: json['unread_notifications'] as int? ?? 0,
      workSchedule: schedule == null
          ? null
          : HomeWorkSchedule.fromJson(schedule),
      announcement: announcement == null
          ? null
          : HomeAnnouncement.fromJson(announcement),
      recentRequests: (json['recent_requests'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => HomeRecentRequest.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      birthdays: (json['birthdays'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => HomeColleague.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      newHires: (json['new_hires'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => HomeColleague.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      punches: (punch['activities'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => HomePunch.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      fetchedAt: DateTime.now(),
    );
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String get placeLabel {
    if (!geofenceEnabled) return 'REMOTE';
    final name = geofenceName?.trim();
    if (name == null || name.isEmpty) return 'OFFICE';
    return name.toUpperCase();
  }

  String get roleLine {
    final parts = <String>[];
    final job = jobPosition?.trim();
    final dept = department?.trim();
    if (job != null && job.isNotEmpty) parts.add(job);
    if (dept != null && dept.isNotEmpty) parts.add(dept);
    return parts.join(' · ');
  }

  String get firstName {
    final parts = employeeName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? 'there' : parts.first;
  }

  String get displayBadgeId {
    final id = badgeId?.trim();
    if (id == null || id.isEmpty) return '—';
    return id.startsWith('ID:') ? id : 'ID: $id';
  }
}

class HomePunch {
  const HomePunch({
    required this.clockIn,
    required this.clockOut,
    required this.open,
  });

  final String? clockIn;
  final String? clockOut;
  final bool open;

  factory HomePunch.fromJson(Map<String, dynamic> json) {
    return HomePunch(
      clockIn: json['clock_in'] as String?,
      clockOut: json['clock_out'] as String?,
      open: json['open'] as bool? ?? json['clock_out'] == null,
    );
  }

  String get rangeLabel {
    final start = clockIn ?? '--:--';
    final end = open ? 'now' : (clockOut ?? '--:--');
    return '$start – $end';
  }
}

class HomeAnnouncement {
  const HomeAnnouncement({
    required this.id,
    required this.title,
    this.description,
    this.createdAt,
    this.expireDate,
  });

  final int id;
  final String title;
  final String? description;
  final DateTime? createdAt;
  final DateTime? expireDate;

  factory HomeAnnouncement.fromJson(Map<String, dynamic> json) {
    return HomeAnnouncement(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? 'Announcement',
      description: json['description'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      expireDate: DateTime.tryParse(json['expire_date'] as String? ?? ''),
    );
  }

  String get previewText {
    final text = (description ?? '').trim();
    if (text.isEmpty) return 'Tap to view announcement';
    return text;
  }
}

class HomeWorkSchedule {
  const HomeWorkSchedule({
    required this.shiftName,
    required this.weekStart,
    required this.weekEnd,
    required this.days,
  });

  final String shiftName;
  final DateTime weekStart;
  final DateTime weekEnd;
  final List<HomeScheduleDay> days;

  factory HomeWorkSchedule.fromJson(Map<String, dynamic> json) {
    return HomeWorkSchedule(
      shiftName: json['shift_name'] as String? ?? 'General',
      weekStart:
          DateTime.tryParse(json['week_start'] as String? ?? '') ??
          DateTime.now(),
      weekEnd:
          DateTime.tryParse(json['week_end'] as String? ?? '') ??
          DateTime.now(),
      days: (json['days'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => HomeScheduleDay.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  /// Today + next scheduled day (or tomorrow) for the home card preview.
  List<HomeScheduleDay> get previewDays {
    if (days.isEmpty) return const [];
    final todayIndex = days.indexWhere((d) => d.isToday);
    if (todayIndex < 0) return days.take(2).toList();
    final today = days[todayIndex];
    final next = todayIndex + 1 < days.length ? days[todayIndex + 1] : null;
    return [today, ?next];
  }
}

class HomeScheduleDay {
  const HomeScheduleDay({
    required this.date,
    required this.dayKey,
    required this.shiftName,
    required this.startTime,
    required this.endTime,
    required this.isToday,
    required this.hasSchedule,
  });

  final DateTime date;
  final String dayKey;
  final String shiftName;
  final String startTime;
  final String endTime;
  final bool isToday;
  final bool hasSchedule;

  factory HomeScheduleDay.fromJson(Map<String, dynamic> json) {
    return HomeScheduleDay(
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      dayKey: json['day_key'] as String? ?? '',
      shiftName: json['shift_name'] as String? ?? 'General',
      startTime: json['start_time'] as String? ?? '09:00',
      endTime: json['end_time'] as String? ?? '17:00',
      isToday: json['is_today'] as bool? ?? false,
      hasSchedule: json['has_schedule'] as bool? ?? false,
    );
  }

  String get timingLabel => '$startTime - $endTime';
}

class HomeRecentRequest {
  const HomeRecentRequest({
    required this.id,
    required this.title,
    required this.status,
    required this.requestedDays,
    required this.startDate,
    required this.endDate,
    required this.kind,
    this.reason,
  });

  final int id;
  final String title;
  final String status;
  final num requestedDays;
  final DateTime startDate;
  final DateTime endDate;
  final String kind;
  final String? reason;

  factory HomeRecentRequest.fromJson(Map<String, dynamic> json) {
    final start =
        DateTime.tryParse(json['start_date'] as String? ?? '') ??
        DateTime.now();
    final end = DateTime.tryParse(json['end_date'] as String? ?? '') ?? start;
    return HomeRecentRequest(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? 'Request',
      status: json['status'] as String? ?? 'requested',
      requestedDays: json['requested_days'] as num? ?? 1,
      startDate: start,
      endDate: end,
      kind: json['kind'] as String? ?? 'other',
      reason: json['reason'] as String?,
    );
  }
}

class HomeColleague {
  const HomeColleague({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.jobPosition,
    this.department,
  });

  final int id;
  final String name;
  final String? avatarUrl;
  final String? jobPosition;
  final String? department;

  factory HomeColleague.fromJson(Map<String, dynamic> json) {
    return HomeColleague(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatar'] as String?,
      jobPosition: json['job_position'] as String?,
      department: json['department'] as String?,
    );
  }

  String get roleLabel {
    final job = jobPosition?.trim();
    if (job != null && job.isNotEmpty) return job;
    final dept = department?.trim();
    if (dept != null && dept.isNotEmpty) return dept;
    return 'Colleague';
  }
}
