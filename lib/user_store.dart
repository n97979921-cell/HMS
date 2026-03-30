// Shared user store - multiple accounts support
class UserStore {
  static final List<Map<String, String>> _users = [
    {'email': 'admin@hospital.com', 'password': 'Admin123'},
    {'email': 'doctor@hospital.com', 'password': 'Doctor123'},
    {'email': 'patient@hospital.com', 'password': 'Patient123'},
  ];

  static List<Map<String, String>> get users => _users;

  static bool login(String email, String password) {
    return _users.any(
      (u) =>
          u['email']!.toLowerCase() == email.toLowerCase().trim() &&
          u['password'] == password.trim(),
    );
  }

  static bool emailExists(String email) {
    return _users.any(
      (u) => u['email']!.toLowerCase() == email.toLowerCase().trim(),
    );
  }

  static void register(String email, String password) {
    _users.add({'email': email.trim(), 'password': password.trim()});
  }
}