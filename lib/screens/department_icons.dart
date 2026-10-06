import 'package:flutter/material.dart';

// 12 fixed icon options — admin inme se choose karega.
// Naam (string) Firestore mein save hota hai, IconData nahi
// (Firestore icons store nahi kar sakta).
const Map<String, IconData> departmentIconMap = {
  'favorite_outline': Icons.favorite_outline,
  'child_friendly_outlined': Icons.child_friendly_outlined,
  'pregnant_woman': Icons.pregnant_woman,
  'visibility_outlined': Icons.visibility_outlined,
  'psychology_outlined': Icons.psychology_outlined,
  'healing_outlined': Icons.healing_outlined,
  'hearing_outlined': Icons.hearing_outlined,
  'spa_outlined': Icons.spa_outlined,
  'biotech_outlined': Icons.biotech_outlined,
  'bloodtype_outlined': Icons.bloodtype_outlined,
  'monitor_heart_outlined': Icons.monitor_heart_outlined,
  'local_hospital_outlined': Icons.local_hospital_outlined, // default
};

const Map<String, Color> departmentColorMap = {
  'green': Color(0xFF1F8A70),
  'purple': Color(0xFF7E57C2),
  'orange': Color(0xFFC98A1B),
  'pink': Color(0xFFD1497A),
  'blue': Color(0xFF1565C0),
  'red': Color(0xFFD9534F),
};

// Firestore se string naam le kar asal IconData wapas deta hai.
// Purani departments jinke paas iconName nahi hai, unke liye
// default icon fallback hai.
IconData getDepartmentIcon(String? iconName) {
  return departmentIconMap[iconName] ?? Icons.local_hospital_outlined;
}

Color getDepartmentColor(String? colorKey) {
  return departmentColorMap[colorKey] ?? const Color(0xFF1F8A70);
}
