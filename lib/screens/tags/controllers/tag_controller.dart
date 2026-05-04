import 'package:flutter/material.dart';
import 'dart:convert';
import '../../../models/tag_models.dart';
import '../../../core/api_service.dart';

class TagController extends ChangeNotifier {
  final ApiService _api = ApiService(); 

  bool isTemplatesLoading = false;
  bool isTagsLoading = false;
  bool isGroupsLoading = false;
  bool isGroupDetailsLoading = false;
  
  List<AppTag> globalTags = [];
  List<AppTemplate> globalTemplates = [];
  List<AppTagGroup> tagGroups = [];

  // // Call this when the screen loads
  // Future<void> fetchAllData() async {
  //   isLoading = true;
  //   notifyListeners();

  //   try {
  //     final results = await Future.wait([
  //       _api.get('/template/user'),
  //       _api.get('/tag/company'),
  //       _api.get('/tagGroupItem/company'),
  //     ]);

  //     final templatesRes = results[0];
  //     final tagsRes = results[1];
  //     final groupsRes = results[2];

  //     final templatesData = jsonDecode(templatesRes.body);
  //     final tagsData = jsonDecode(tagsRes.body);
  //     final groupsData = jsonDecode(groupsRes.body);

  //     if (templatesData['success'] == true && templatesData['data'] != null) {
  //       globalTemplates = (templatesData['data'] as List)
  //           .map((t) => AppTemplate.fromJson(t as Map<String, dynamic>))
  //           .toList();
  //     }
      
  //     if (tagsData['success'] == true && tagsData['data'] != null) {
  //       globalTags = (tagsData['data'] as List)
  //           .map((t) => AppTag.fromJson(t as Map<String, dynamic>))
  //           .toList();
  //     }

  //     debugPrint("Parsed ${globalTemplates.length} templates, ${globalTags.length} tags");

  //     if (groupsData['success'] == true && groupsData['data'] != null) {
  //       tagGroups = (groupsData['data'] as List)
  //           .map((g) => AppTagGroup.fromJson(g as Map<String, dynamic>))
  //           .toList();
  //     }

  //     debugPrint("Parsed ${tagGroups.length} tag groups");

  //   } catch (e) {
  //     print("Error fetching tag data: $e");
  //   } finally {
  //     isLoading = false;
  //     notifyListeners();
  //   }
  // }

  // 🚀 1. Fetch Templates 
  Future<void> fetchTemplates() async {
    isTemplatesLoading = true;
    notifyListeners();

    try {
      final response = await _api.get('/template/user');
      final data = jsonDecode(response.body);

      if (data['success'] == true && data['data'] != null) {
        globalTemplates = (data['data'] as List)
            .map((t) => AppTemplate.fromJson(t as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint("Error fetching templates: $e");
    } finally {
      isTemplatesLoading = false;
      notifyListeners();
    }
  }

  // 🚀 2. Fetch Tags 
  Future<void> fetchTags() async {
    isTagsLoading = true;
    notifyListeners();

    try {
      final response = await _api.get('/tag/company');
      final data = jsonDecode(response.body);

      if (data['success'] == true && data['data'] != null) {
        globalTags = (data['data'] as List)
            .map((t) => AppTag.fromJson(t as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint("Error fetching tags: $e");
    } finally {
      isTagsLoading = false;
      notifyListeners();
    }
  }

  // 🚀 3. Fetch Tag Groups 
  Future<void> fetchGroups() async {
    isGroupsLoading = true;
    notifyListeners();

    try {
      final response = await _api.get('/tagGroupItem/company');
      final data = jsonDecode(response.body);

      if (data['success'] == true && data['data'] != null) {
        tagGroups = (data['data'] as List)
            .map((g) => AppTagGroup.fromJson(g as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint("Error fetching tag groups: $e");
    } finally {
      isGroupsLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchTemplatesForGroup(String groupId) async {
    final groupIndex = tagGroups.indexWhere((g) => g.id == groupId);
    if (groupIndex == -1) return;

    isGroupDetailsLoading = true;
    notifyListeners();

    try {
      final response = await _api.get('/template/tag-group/$groupId');

      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true && responseData['data'] != null) {
        final List dynamicData = responseData['data'] as List;
        
        final fetchedTemplates = dynamicData.map((item) {
          final templateMap = item['template'] as Map<String, dynamic>;
          return AppTemplate.fromJson(templateMap);
        }).toList();

        final seenIds = <String>{};
        final uniqueTemplates = fetchedTemplates.where((template) {
          return seenIds.add(template.id); 
        }).toList();

        tagGroups[groupIndex].templates = uniqueTemplates;
      }
    } catch (e) {
      print("Error fetching templates for group $groupId: $e");
    } finally {
      isGroupDetailsLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createTag(String name, Color color) async {
    try {
      final response = await _api.post('/tag/create', {
        "name": name,
        "color": colorToHex(color),
      });

      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true && responseData['data'] != null) {
        final newTag = AppTag.fromJson(responseData['data'] as Map<String, dynamic>);
        globalTags.add(newTag);
        notifyListeners();
        return true;
      }
    } catch (e) {
      print("Error creating tag: $e");
    }
    return false;
  }

  Future<String?> createTagGroup({  
    required String name,
    required List<String> tagIds,
    required List<String> templateIds,
    required List<Map<String, String>> newTags, // <-- ADD THIS
  }) async {
    notifyListeners();

    try {
      final payload = {
        "name": name,
        "tag_id_list": tagIds,
        "template_id_list": templateIds,
        "new_tag_list": newTags,
      };

      final response = await _api.post('/tagGroup/new-group', payload);
      final responseData = jsonDecode(response.body);

       if (responseData['success'] == true || responseData['data'] != null) {
        final newId = responseData['data']['id']; 

        await fetchGroups(); 
        
        return newId;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    } finally {
      notifyListeners();
    }
  }

  Future<bool> updateGroupTags({
    required String groupId,
    required List<String> tagIds,
    required List<Map<String, String>> newTags,
  }) async {
    isGroupDetailsLoading = true;
    notifyListeners();

    try {
      final payload = {
        "tag_id_list": tagIds,
        "new_tag_list": newTags,
      };

      final response = await _api.put('/tagGroup/update-tag/$groupId', payload);
      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true) {
        fetchGroups();
        if (newTags.isNotEmpty) {
          fetchTags();
        }
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    } finally {
      isGroupDetailsLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateGroupTemplates({
    required String groupId,
    required List<String> templateIds,
  }) async {
    notifyListeners();

    try {
      final payload = {
        "tag_group_id": groupId,
        "template_id_list": templateIds,
      };

      final response = await _api.post('/tagGroupItem/associate-tag-group-to-template', payload);
      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true) {
        fetchTemplatesForGroup(groupId);
        return true; 
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }
}