class Template {
  final String id;
  final String name;
  final String userId;
  final String companyId;
  final DateTime createDate;

  Template({
    required this.id,
    required this.name,
    required this.userId,
    required this.companyId,
    required this.createDate,
  });
  
  factory Template.fromJson(Map<String, dynamic> json) {
    return Template(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      userId: json['user_id'] ?? '',
      companyId: json['company_id'] ?? '',
      createDate: json['create_time'] != null 
          ? DateTime.parse(json['create_time']) 
          : DateTime.now(),
    );
  }
}