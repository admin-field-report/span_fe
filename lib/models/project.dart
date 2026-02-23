class Project {
  final String id;
  final String name;
  final String description;
  final DateTime createDate;

  Project({
    required this.id,
    required this.name,
    required this.description,
    required this.createDate,
  });
  
  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      createDate: json['create_time'] != null 
          ? DateTime.parse(json['create_time']) 
          : DateTime.now(),
    );
  }
}