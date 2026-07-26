import 'package:flutter/material.dart';

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

  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  // ── YAHAN BADLO (hospital ka asli number/email milne par) ──────
  static const String _hospitalPhone = '0300-0000000'; // TODO: asli number
  static const String _hospitalEmail = 'info@familywellcare.com'; // TODO
  // ────────────────────────────────────────────────────────────────

  static const String _emergencyNumber = '1122'; // Rescue 1122 — fixed

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Emergency (1122) — sabse upar, laal, prominent ──
                    _buildEmergencyCard(),
                    const SizedBox(height: 24),

                    const Text(
                      'Hospital contact',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2F3A),
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildContactCard(
                      icon: Icons.call_outlined,
                      iconColor: _primary,
                      iconBg: const Color(0xFFDCEFE9),
                      title: 'Call the hospital',
                      subtitle: _hospitalPhone,
                    ),
                    const SizedBox(height: 12),
                    _buildContactCard(
                      icon: Icons.email_outlined,
                      iconColor: const Color(0xFF1565C0),
                      iconBg: const Color(0xFFD9ECF8),
                      title: 'Email us',
                      subtitle: _hospitalEmail,
                    ),
                    const SizedBox(height: 24),

                    // ── Info / FAQ ──
                    const Text(
                      'Helpful information',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2F3A),
                      ),
                    ),
                    const SizedBox(height: 12),
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
                    // Q3 — general kar diya
                    _buildInfoTile(
                      'How do I pay?',
                      'Consultation fees are paid online via EasyPaisa after '
                          'booking. Lab tests and room charges are paid at the '
                          'hospital reception.',
                    ),
                    // Q4 — general kar diya
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
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _primaryDark,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.arrow_back, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          const Text('Help & Support',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // Emergency 1122 — sirf display (tap nahi)
  Widget _buildEmergencyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD9534F), Color(0xFFB5322E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.emergency_outlined,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Medical Emergency',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 2),
                Text('Call Rescue 1122',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const Text(_emergencyNumber,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  // Contact card — sirf display (koi Call/Email button nahi)
  Widget _buildContactCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A2F3A))),
                const SizedBox(height: 2),
                Text(subtitle,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
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
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Theme(
        // ExpansionTile ki default divider line hatane ke liye
        data: ThemeData().copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          iconColor: _primary,
          collapsedIconColor: Colors.grey,
          title: Text(question,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A2F3A))),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(answer,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}
