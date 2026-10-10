// lib/doctor_screens/request_lab_test_screen.dart
import 'package:flutter/material.dart';
import '../widgets/app_ui.dart';
import 'doctor_repository.dart';
import 'test_type_price.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class _RLColors {
  static const primary = Color(0xFF0E6E68);
  static const error = Color(0xFFB23A1E);
}

/// Doctor ek saath MULTIPLE lab tests request kar sakta hai — har test
/// apna alag lab_tests document banta hai (Receptionist/Lab-Staff side
/// pe individually dikhega, individually pay/process hoga — schema
/// decision).
class RequestLabTestScreen extends StatefulWidget {
  final DoctorRepository repository;
  final String appointmentId;
  final String doctorId;
  final String patientId;
  final String patientName;

  const RequestLabTestScreen({
    super.key,
    required this.repository,
    required this.appointmentId,
    required this.doctorId,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<RequestLabTestScreen> createState() => _RequestLabTestScreenState();
}

class _RequestLabTestScreenState extends State<RequestLabTestScreen> {
  List<TestTypePrice> _testTypes = [];
  final Set<TestTypePrice> _selected = {}; // multi-select
  Set<String> _alreadyRequested = {}; // is appointment ke liye
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTestTypes();
    _loadAlreadyRequested();
  }

  // Is appointment ke liye jo tests PEHLE SE request ho chuke hain
  // (koi bhi status), unhe disable karna hai — duplicate-prevention.
  Future<void> _loadAlreadyRequested() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('lab_tests')
          .where('appointmentId', isEqualTo: widget.appointmentId)
          .get();
      if (mounted) {
        setState(() {
          _alreadyRequested =
              snap.docs.map((d) => d.data()['testType'] as String).toSet();
        });
      }
    } catch (_) {
      // fail ho to koi disable nahi hoga — worst case duplicate
      // ban sakta hai, lekin crash nahi hoga
    }
  }

  Future<void> _loadTestTypes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await widget.repository.getTestTypePrices();
      if (mounted) {
        setState(() {
          _testTypes = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load test types. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  void _toggleSelection(TestTypePrice test, bool? checked) {
    setState(() {
      if (checked == true) {
        _selected.add(test);
      } else {
        _selected.remove(test);
      }
    });
  }

  num get _totalCharge => _selected.fold<num>(0, (sum, t) => sum + t.charge);

  Future<void> _submit() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one test')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    int successCount = 0;
    final List<String> failedTests = [];

    // Har test apna ALAG request/document — ek fail ho to baaki
    // rukte nahi, taake partial-success bhi patient/doctor ko
    // milta rahe (koi bhi cheez atomic-block nahi honi chahiye,
    // yeh independent requests hain).
    for (final test in _selected) {
      try {
        await widget.repository.requestLabTest(
          appointmentId: widget.appointmentId,
          doctorId: widget.doctorId,
          patientId: widget.patientId,
          testType: test.testType,
          charge: test.charge,
        );
        successCount++;
      } catch (e) {
        failedTests.add(test.testType);
      }
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (failedTests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successCount == 1
              ? 'Lab test requested'
              : '$successCount lab tests requested'),
          backgroundColor: _RLColors.primary,
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '$successCount requested. Failed: ${failedTests.join(", ")}'),
          backgroundColor: _RLColors.error,
        ),
      );
      if (successCount > 0) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return AppHeader(
      title: 'Request Lab Test',
      subtitle: widget.patientName,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.teal));
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: AppColors.danger, size: 40),
              const SizedBox(height: 12),
              Text(_errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadTestTypes,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.header, elevation: 0),
                child:
                    const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }
    if (_testTypes.isEmpty) {
      return const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: AppEmptyState(
          icon: Icons.science_outlined,
          title:
              'No test types have been configured yet. Ask the admin to add test type prices first.',
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            children: [
              Text(
                'Patient: ${widget.patientName}',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text),
              ),
              const SizedBox(height: 2),
              const Text(
                'Select one or more tests to request.',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: _testTypes.map((t) {
                    final isSelected = _selected.contains(t);
                    final isAlreadyRequested =
                        _alreadyRequested.contains(t.testType);
                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: isAlreadyRequested
                          ? null
                          : (checked) => _toggleSelection(t, checked),
                      activeColor: AppColors.teal,
                      checkboxShape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(t.testType,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: isAlreadyRequested
                                  ? AppColors.faint
                                  : AppColors.text)),
                      subtitle: Text(
                          isAlreadyRequested
                              ? 'Already requested'
                              : 'Rs. ${t.charge}',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.muted)),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, 16 + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.divider)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_selected.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        '${_selected.length} test${_selected.length == 1 ? '' : 's'} selected',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted)),
                    Text('Total: Rs. $_totalCharge',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0B5E57))),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.header,
                    disabledBackgroundColor: AppColors.header.withOpacity(0.5),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : Text(
                          _selected.length > 1
                              ? 'Request ${_selected.length} Tests'
                              : 'Request Test',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
