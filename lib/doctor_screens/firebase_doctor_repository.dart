// lib/doctor_screens/firebase_doctor_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'appointment_status.dart';
import 'doctor_appointment_list_item.dart';
import 'doctor_repository.dart';
import 'lab_test_status.dart';
import 'lab_test_list_item.dart';
import 'lab_test_detail.dart';
import 'doctor_profile.dart';
import 'prescription.dart';
import 'patient_profile.dart';
import 'test_type_price.dart';

class FirebaseDoctorRepository implements DoctorRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  Future<String> getDoctorName(String doctorId) async {
    try {
      final doc = await _db.collection('users').doc(doctorId).get();
      if (!doc.exists) return 'Doctor';
      return (doc.data()?['name'] as String?) ?? 'Doctor';
    } on FirebaseException catch (e) {
      throw Exception('Failed to load doctor profile: ${e.message}');
    }
  }

  @override
  Future<List<DoctorAppointmentListItem>> getAppointmentsForDate({
    required String doctorId,
    required DateTime date,
    required List<String> statuses,
  }) async {
    try {
      // The 'slots' collection stores 'date' as a plain string like
      // "2026-07-27", not a Firestore Timestamp — so we must compare
      // against that same string format instead of using a Timestamp range.
      final dateString = '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';

      final slotsSnap = await _db
          .collection('slots')
          .where('doctorId', isEqualTo: doctorId)
          .where('date', isEqualTo: dateString)
          .get();

      if (slotsSnap.docs.isEmpty) return [];

      final slotTimeById = <String, String>{
        for (final doc in slotsSnap.docs)
          doc.id: (doc.data()['startTime'] as String?) ?? '',
      };
      final slotIds = slotTimeById.keys.toList();

      final appointmentDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (var i = 0; i < slotIds.length; i += 10) {
        final chunk = slotIds.sublist(
            i, i + 10 > slotIds.length ? slotIds.length : i + 10);
        final snap = await _db
            .collection('appointments')
            .where('doctorId', isEqualTo: doctorId)
            .where('slotId', whereIn: chunk)
            .get();
        appointmentDocs.addAll(snap.docs);
      }

      final filtered = appointmentDocs.where((doc) {
        final status = (doc.data()['status'] as String? ?? '').toLowerCase();
        return statuses.contains(status);
      }).toList();

      if (filtered.isEmpty) return [];

      final patientIds = filtered
          .map((doc) => doc.data()['patientId'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final patientNameById = <String, String>{};
      await Future.wait(patientIds.map((id) async {
        final userDoc = await _db.collection('users').doc(id).get();
        patientNameById[id] = (userDoc.data()?['name'] as String?) ?? 'Unknown';
      }));

      return filtered.map((doc) {
        final data = doc.data();
        final slotId = data['slotId'] as String? ?? '';
        final patientId = data['patientId'] as String? ?? '';

        return DoctorAppointmentListItem(
          appointmentId: doc.id,
          patientId: patientId,
          patientName: patientNameById[patientId] ?? 'Unknown',
          slotTime: slotTimeById[slotId] ?? '',
          status: AppointmentStatusX.fromString(
              data['status'] as String? ?? 'requested'),
          appointmentType: AppointmentTypeX.fromString(
              data['appointmentType'] as String? ?? 'IN_PERSON'),
          admissionRecommended: data['admissionRecommended'] as bool? ?? false,
        );
      }).toList();
    } on FirebaseException catch (e) {
      throw Exception('Failed to load appointments: ${e.message}');
    }
  }

  @override
  Future<List<LabTestListItem>> getLabTestsForDoctor({
    required String doctorId,
    String? statusFilter,
  }) async {
    try {
      Query<Map<String, dynamic>> query =
          _db.collection('lab_tests').where('doctorId', isEqualTo: doctorId);

      if (statusFilter != null) {
        final schemaStatus = _toSchemaStatus(statusFilter);
        query = query.where('status', isEqualTo: schemaStatus);
      }

      final snap = await query.orderBy('createdAt', descending: true).get();
      if (snap.docs.isEmpty) return [];

      final patientIds = snap.docs
          .map((doc) => doc.data()['patientId'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final patientNameById = <String, String>{};
      await Future.wait(patientIds.map((id) async {
        final userDoc = await _db.collection('users').doc(id).get();
        patientNameById[id] = (userDoc.data()?['name'] as String?) ?? 'Unknown';
      }));

      return snap.docs.map((doc) {
        final data = doc.data();
        final patientId = data['patientId'] as String? ?? '';
        return LabTestListItem(
          testId: doc.id,
          patientName: patientNameById[patientId] ?? 'Unknown',
          testType: (data['testType'] as String?) ?? '',
          status: LabTestStatusX.fromString(
              (data['status'] as String?) ?? 'Pending'),
        );
      }).toList();
    } on FirebaseException catch (e) {
      throw Exception('Failed to load lab reports: ${e.message}');
    }
  }

  @override
  Future<LabTestDetail> getLabTestDetail(String testId) async {
    try {
      final doc = await _db.collection('lab_tests').doc(testId).get();
      if (!doc.exists) throw Exception('Report not found');

      final data = doc.data()!;
      final patientId = data['patientId'] as String? ?? '';
      final doctorId = data['doctorId'] as String? ?? '';

      final results = await Future.wait([
        _db.collection('users').doc(patientId).get(),
        _db.collection('users').doc(doctorId).get(),
      ]);
      final patientName = (results[0].data()?['name'] as String?) ?? 'Unknown';
      final doctorName = (results[1].data()?['name'] as String?) ?? 'Unknown';

      final updatedAt = data['updatedAt'];
      final reportDate = updatedAt is Timestamp ? updatedAt.toDate() : null;

      return LabTestDetail(
        testId: doc.id,
        patientName: patientName,
        doctorName: doctorName,
        reportDate: reportDate,
        testType: (data['testType'] as String?) ?? '',
        status:
            LabTestStatusX.fromString((data['status'] as String?) ?? 'Pending'),
        reportUrl: data['reportUrl'] as String?,
      );
    } on FirebaseException catch (e) {
      throw Exception('Failed to load report: ${e.message}');
    }
  }

  @override
  Future<DoctorProfile> getDoctorProfile(String doctorId) async {
    try {
      final userDoc = await _db.collection('users').doc(doctorId).get();
      if (!userDoc.exists) throw Exception('Doctor not found');
      final userData = userDoc.data()!;

      final profileDoc =
          await _db.collection('doctor_profiles').doc(doctorId).get();
      final profileData = profileDoc.data() ?? {};

      String departmentName = 'Not assigned';
      final departmentId = profileData['departmentId'] as String?;
      if (departmentId != null && departmentId.isNotEmpty) {
        final deptDoc =
            await _db.collection('departments').doc(departmentId).get();
        departmentName = (deptDoc.data()?['name'] as String?) ?? 'Not assigned';
      }

      final settingsDoc =
          await _db.collection('doctor_settings').doc(doctorId).get();
      final settingsData = settingsDoc.data();

      return DoctorProfile(
        doctorId: doctorId,
        name: (userData['name'] as String?) ?? '',
        email: (userData['email'] as String?) ?? '',
        phone: (userData['phone'] as String?) ?? '',
        cnic: (userData['cnic'] as String?) ?? '',
        specialization: (profileData['specialization'] as String?) ?? 'Not set',
        license: (profileData['license'] as String?) ?? 'Not set',
        departmentName: departmentName,
        appointmentStartTime: settingsData?['appointmentStartTime'] as String?,
        appointmentEndTime: settingsData?['appointmentEndTime'] as String?,
      );
    } on FirebaseException catch (e) {
      throw Exception('Failed to load profile: ${e.message}');
    }
  }

  @override
  Future<void> updateDoctorProfile({
    required String doctorId,
    required String name,
    required String phone,
  }) async {
    try {
      await _db.collection('users').doc(doctorId).update({
        'name': name,
        'phone': phone,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': doctorId,
      });
    } on FirebaseException catch (e) {
      throw Exception('Failed to update profile: ${e.message}');
    }
  }

  @override
  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
  }

  /// Converts a UI-side status filter (e.g. 'pending', 'in progress',
  /// 'Completed') into the exact string format stored in Firestore
  /// (e.g. 'Pending', 'In Progress', 'Completed'), using the same
  /// normalization logic as LabTestStatusX.fromString.
  String _toSchemaStatus(String statusFilter) {
    return LabTestStatusX.fromString(statusFilter).label;
  }

  @override
  Future<void> updateAppointmentStatus({
    required String appointmentId,
    required String status,
  }) async {
    try {
      await _db.collection('appointments').doc(appointmentId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw Exception('Failed to update appointment: ${e.message}');
    }
  }

  @override
  Future<void> startVideoConsultation({required String appointmentId}) async {
    try {
      await _db.collection('appointments').doc(appointmentId).update({
        'status': 'InProgress',
        'consultationStartedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw Exception('Failed to start consultation: ${e.message}');
    }
  }

  @override
  Future<void> addPrescription({
    required String appointmentId,
    required String doctorId,
    required String patientId,
    required List<PrescriptionMedicineInput> medicines,
  }) async {
    try {
      final prescriptionRef = _db.collection('prescriptions').doc();
      final batch = _db.batch();

      batch.set(prescriptionRef, {
        'prescriptionId': prescriptionRef.id,
        'appointmentId': appointmentId,
        'doctorId': doctorId,
        'patientId': patientId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      for (final med in medicines) {
        final medRef = _db.collection('prescription_medicines').doc();
        batch.set(medRef, {
          'prescriptionMedicineId': medRef.id,
          'prescriptionId': prescriptionRef.id,
          'medicineName': med.medicineName,
          'dosage': med.dosage,
          'frequency': med.frequency,
          'duration': med.duration,
          'instructions': med.instructions,
        });
      }

      await batch.commit();
    } on FirebaseException catch (e) {
      throw Exception('Failed to save prescription: ${e.message}');
    }
  }

  @override
  Future<PatientProfile> getPatientProfile(String patientId) async {
    try {
      final userDoc = await _db.collection('users').doc(patientId).get();
      if (!userDoc.exists) throw Exception('Patient not found');
      final userData = userDoc.data()!;

      final profileDoc =
          await _db.collection('patient_profiles').doc(patientId).get();
      final profileData = profileDoc.data() ?? {};

      return PatientProfile(
        patientId: patientId,
        name: (userData['name'] as String?) ?? '',
        email: (userData['email'] as String?) ?? '',
        phone: (userData['phone'] as String?) ?? '',
        cnic: (userData['cnic'] as String?) ?? '',
        age: profileData['age'] as int?,
        gender: profileData['gender'] as String?,
        bloodGroup: profileData['bloodGroup'] as String?,
        allergies: profileData['allergies'] as String?,
        chronicConditions: profileData['chronicConditions'] as String?,
        patientType: (profileData['patientType'] as String?) ?? 'REGISTERED',
      );
    } on FirebaseException catch (e) {
      throw Exception('Failed to load patient profile: ${e.message}');
    }
  }

  @override
  Future<List<TestTypePrice>> getTestTypePrices() async {
    try {
      final snap = await _db.collection('test_type_prices').get();
      return snap.docs
          .map((doc) => TestTypePrice(
                testType: doc.id,
                charge: (doc.data()['charge'] as num?) ?? 0,
              ))
          .toList();
    } on FirebaseException catch (e) {
      throw Exception('Failed to load test types: ${e.message}');
    }
  }

  @override
  Future<void> requestLabTest({
    required String appointmentId,
    required String doctorId,
    required String patientId,
    required String testType,
    required num charge,
  }) async {
    try {
      final testRef = _db.collection('lab_tests').doc();
      await testRef.set({
        'testId': testRef.id,
        'appointmentId': appointmentId,
        'doctorId': doctorId,
        'patientId': patientId,
        'testType': testType,
        'status': 'Pending',
        'reportUrl': null,
        'charge': charge,
        'paymentStatus': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw Exception('Failed to request lab test: ${e.message}');
    }
  }

  @override
  Future<void> recommendAdmission({
    required String appointmentId,
    required bool recommended,
  }) async {
    try {
      await _db.collection('appointments').doc(appointmentId).update({
        'admissionRecommended': recommended,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw Exception(
          'Failed to update admission recommendation: ${e.message}');
    }
  }
}
