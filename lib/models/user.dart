class UserModel {
  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final String companyId;

  UserModel({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.companyId,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      companyId: json['company_id'] ?? '',
    );
  }
}