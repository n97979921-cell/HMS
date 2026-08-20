// lib/models/appointment_status.dart
enum AppointmentStatus {
  requested,
  confirmed,
  checkedIn,
  inProgress,
  completed,
  cancelled,
  noShow
}

enum AppointmentType { inPerson, videoCall, walkIn }

extension AppointmentStatusX on AppointmentStatus {
  static AppointmentStatus fromString(String value) {
    return AppointmentStatus.values.firstWhere(
      (e) => e.name.toLowerCase() == value.toLowerCase(),
      orElse: () => AppointmentStatus.requested,
    );
  }
}

extension AppointmentTypeX on AppointmentType {
  String get label {
    switch (this) {
      case AppointmentType.inPerson:
        return 'In-Person';
      case AppointmentType.videoCall:
        return 'Video';
      case AppointmentType.walkIn:
        return 'Walk-in';
    }
  }

  static AppointmentType fromString(String value) {
    switch (value.toUpperCase()) {
      case 'IN_PERSON':
        return AppointmentType.inPerson;
      case 'VIDEO_CALL':
        return AppointmentType.videoCall;
      case 'WALK_IN':
        return AppointmentType.walkIn;
      default:
        return AppointmentType.inPerson;
    }
  }
}
