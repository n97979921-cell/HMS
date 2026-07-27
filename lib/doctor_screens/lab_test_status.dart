// lib/doctor_screens/lab_test_status.dart
enum LabTestStatus { pending, inProgress, completed, cancelled }

extension LabTestStatusX on LabTestStatus {
  String get label {
    switch (this) {
      case LabTestStatus.pending:
        return 'Pending';
      case LabTestStatus.inProgress:
        return 'In Progress';
      case LabTestStatus.completed:
        return 'Completed';
      case LabTestStatus.cancelled:
        return 'Cancelled';
    }
  }

  static LabTestStatus fromString(String value) {
    switch (value.toLowerCase().replaceAll(' ', '')) {
      case 'pending':
        return LabTestStatus.pending;
      case 'inprogress':
        return LabTestStatus.inProgress;
      case 'completed':
        return LabTestStatus.completed;
      case 'cancelled':
        return LabTestStatus.cancelled;
      default:
        return LabTestStatus.pending;
    }
  }
}