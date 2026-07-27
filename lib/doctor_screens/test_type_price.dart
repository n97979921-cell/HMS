// lib/doctor_screens/test_type_price.dart

/// A lab test type and its admin-set charge, read from `test_type_prices`.
/// Used to populate the dropdown in the Request Lab Test screen — the
/// charge shown here is copied onto the `lab_tests` document at the
/// moment of creation (same "copy fee at creation time" pattern used
/// elsewhere in this schema, e.g. consultationFee).
class TestTypePrice {
  final String testType;
  final num charge;

  TestTypePrice({required this.testType, required this.charge});
}