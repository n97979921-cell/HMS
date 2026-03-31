class UserStore {
  static final List<Map<String, String>> _users = [
    {'email': 'admin@hospital.com', 'password': 'Admin123'},
    {'email': 'doctor@hospital.com', 'password': 'Doctor123'},
    {'email': 'patient@hospital.com', 'password': 'Patient123'},
  ];

  static void addUser(String email, String password) {
    _users.add({'email': email, 'password': password});
  }

  static bool exists(String email) {
    return _users
        .any((u) => u['email']!.toLowerCase() == email.toLowerCase());
  }

  static bool validate(String email, String password) {
    return _users.any((u) =>
        u['email']!.toLowerCase() == email.toLowerCase() &&
        u['password'] == password);
  }
}