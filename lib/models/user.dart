class CompanyModel {
  final String id;
  final String name;
  final String? logo;

  CompanyModel({
    required this.id,
    required this.name,
    this.logo,
  });

  factory CompanyModel.fromJson(Map<String, dynamic> json) {
    return CompanyModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      logo: json['logo'],
    );
  }
}

class UserModel {
  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final String companyId;
  final CompanyModel? company;

  UserModel({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.companyId,
    this.company,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      companyId: json['company_id'] ?? '',
      company: json['company'] != null ? CompanyModel.fromJson(json['company']) : null,
    );
  }
}
