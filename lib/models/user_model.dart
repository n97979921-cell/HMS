class UserModel {
  String uid;
  String email;
  String name;
  String phone;
  String? cnic;
  String role;
  String status;
  DateTime createdAt;
  String? createdBy;
  DateTime? updatedAt;
  String? updatedBy;
  DateTime? deactivatedAt;
  String? deactivatedBy;
  String? deactivatedReason;
  DateTime? reactivatedAt;
  DateTime? deletedAt;
  String? deletedBy;

  UserModel({
    required this.uid,
    required this.email,
    required this.name,
    required this.phone,
    this.cnic,
    required this.role,
    required this.status,
    required this.createdAt,
    this.createdBy,
    this.updatedAt,
    this.updatedBy,
    this.deactivatedAt,
    this.deactivatedBy,
    this.deactivatedReason,
    this.reactivatedAt,
    this.deletedAt,
    this.deletedBy,
  });

  factory UserModel.fromFirestore(Map<String, dynamic> data) {
    return UserModel(
      uid: data['uid'] ?? '',
      email: data['email'] ?? '',
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      cnic: data['cnic'],
      role: data['role'] ?? 'patient',
      status: data['status'] ?? 'active',
      createdAt: data['createdAt']?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'],
      updatedAt: data['updatedAt']?.toDate(),
      updatedBy: data['updatedBy'],
      deactivatedAt: data['deactivatedAt']?.toDate(),
      deactivatedBy: data['deactivatedBy'],
      deactivatedReason: data['deactivatedReason'],
      reactivatedAt: data['reactivatedAt']?.toDate(),
      deletedAt: data['deletedAt']?.toDate(),
      deletedBy: data['deletedBy'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'phone': phone,
      if (cnic != null) 'cnic': cnic,
      'role': role,
      'status': status,
      'createdAt': createdAt,
      'createdBy': createdBy,
      'updatedAt': updatedAt,
      'updatedBy': updatedBy,
      'deactivatedAt': deactivatedAt,
      'deactivatedBy': deactivatedBy,
      'deactivatedReason': deactivatedReason,
      'reactivatedAt': reactivatedAt,
      'deletedAt': deletedAt,
      'deletedBy': deletedBy,
    };
  }
}
