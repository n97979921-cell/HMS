import 'package:flutter/material.dart';
import '../widgets/app_ui.dart';

/// PATIENT HELP / SUPPORT SCREEN
///
/// ⚠️ HOSPITAL CONTACT BADALNA HO TO SIRF YAHAN BADLO — neeche
/// _hospitalPhone aur _hospitalEmail. Baaki poori screen automatic
/// update ho jayegi.
///
/// NOTE: Contact sirf DISPLAY ke liye hai — patient number/email
/// dekh ke khud apne phone se rabta karega. Koi tap-to-call ya
/// email launch nahi (is liye url_launcher ki zaroorat nahi).
///
/// 1122 = Pakistan ki official emergency service (Rescue 1122).
/// Yeh permanent hai, kabhi mat badalna.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  // ── YAHAN BADLO (hospital ka asli number/email milne par) ──────
  static const String _hospitalPhone = '0308-9456453'; // TODO: asli number
  static const String _hospitalEmail =
      'familywelcarehospital@gmail.com'; // TODO
  // ────────────────────────────────────────────────────────────────

  static const String _emergencyNumber = '1122'; // Rescue 1122 — fixed

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Emergency (1122) — sabse upar ──
                  _buildEmergencyCard(),
                  const SizedBox(height: 22),
                  _sectionLabel('HOSPITAL CONTACT'),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        _buildContactCard(
                          icon: Icons.call_outlined,
                          iconColor: AppColors.teal,
                          iconBg: AppColors.tealSoft,
                          title: 'Call the hospital',
                          subtitle: _hospitalPhone,
                        ),
                        const Divider(height: 1, color: AppColors.divider),
                        _buildContactCard(
                          icon: Icons.email_outlined,
                          iconColor: AppColors.blue,
                          iconBg: AppColors.blueSoft,
                          title: 'Email us',
                          subtitle: _hospitalEmail,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  _sectionLabel('HELPFUL INFORMATION'),
                  const SizedBox(height: 10),
                  _buildInfoTile(
                    'How do I book an appointment?',
                    'Go to Home, choose Video consult or In-clinic visit, '
                        'pick a department and doctor, then select a time slot.',
                  ),
                  _buildInfoTile(
                    'When is my appointment confirmed?',
                    'After you request an appointment, the hospital reception '
                        'reviews and confirms it. You can track the status under '
                        'My Appointments.',
                  ),
                  _buildInfoTile(
                    'How do I pay?',
                    'Consultation fees are paid online via EasyPaisa after '
                        'booking. Lab tests and room charges are paid at the '
                        'hospital reception.',
                  ),
                  _buildInfoTile(
                    'Where are my prescriptions and reports?',
                    'They appear on the Home screen after a completed visit.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(text,
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: AppColors.muted));
  }

  Widget _buildHeader(BuildContext context) {
    return const AppHeader(
      title: 'Help & Support',
      subtitle: 'We are here for you',
    );
  }

  // Emergency 1122 — sirf display (tap nahi)
  Widget _buildEmergencyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF9A2E16),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.emergency_outlined,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Medical Emergency',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
                SizedBox(height: 2),
                Text('Call Rescue 1122',
                    style: TextStyle(
                        color: Color(0xFFFFD9CF),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const Text(_emergencyNumber,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  // Contact row — sirf display (koi Call/Email button nahi)
  Widget _buildContactCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          AppIconTile(
            icon: icon,
            color: iconColor,
            background: iconBg,
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(String question, String answer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Theme(
        // ExpansionTile ki default divider line hatane ke liye
        data: ThemeData().copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          iconColor: AppColors.teal,
          collapsedIconColor: AppColors.faint,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(18))),
          collapsedShape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(18))),
          title: Text(question,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text)),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(answer,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.muted, height: 1.55)),
            ),
          ],
        ),
      ),
    );
  }
}
