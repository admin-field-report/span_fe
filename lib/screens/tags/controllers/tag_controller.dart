import 'package:flutter/material.dart';
import 'dart:convert';
import '../../../models/tag_models.dart';
import '../../../core/api_service.dart';

class TagController extends ChangeNotifier {
  final ApiService _api = ApiService(); 

  bool isLoading = false;
  bool isGroupDetailsLoading = false;
  
  List<AppTag> globalTags = [];
  List<AppTemplate> globalTemplates = [];
  List<AppTagGroup> tagGroups = [];

  // Call this when the screen loads
  Future<void> fetchAllData() async {
    isLoading = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        _api.get('/template/user'),
        _api.get('/tag/company'),
        _api.get('/tagGroupItem/company'),
      ]);

      final templatesRes = results[0];
      final tagsRes = results[1];
      final groupsRes = results[2];

      final templatesData = jsonDecode(templatesRes.body);
      final tagsData = jsonDecode(tagsRes.body);
      final groupsData = jsonDecode(groupsRes.body);

      // debugPrint("Templates Response: ${templatesRes.body}");
      // debugPrint("Tags Response: ${tagsRes.body}");
      // debugPrint("Groups Response: ${groupsRes.body}");

      if (templatesData['success'] == true && templatesData['data'] != null) {
        globalTemplates = (templatesData['data'] as List)
            .map((t) => AppTemplate.fromJson(t as Map<String, dynamic>))
            .toList();
      }
      
      if (tagsData['success'] == true && tagsData['data'] != null) {
        globalTags = (tagsData['data'] as List)
            .map((t) => AppTag.fromJson(t as Map<String, dynamic>))
            .toList();
      }

      debugPrint("Parsed ${globalTemplates.length} templates, ${globalTags.length} tags");

      if (groupsData['success'] == true && groupsData['data'] != null) {
        tagGroups = (groupsData['data'] as List)
            .map((g) => AppTagGroup.fromJson(g as Map<String, dynamic>))
            .toList();
      }

      debugPrint("Parsed ${tagGroups.length} tag groups");

    } catch (e) {
      print("Error fetching tag data: $e");
    } finally {
      isLoading = false;
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

        tagGroups[groupIndex].templates = fetchedTemplates;
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

  Future<bool> createTagGroup({
    required String name, 
    required List<String> tagIds, 
    required List<String> templateIds
  }) async {
    try {
      final response = await _api.post('/tagGroup/group', {
        "name": name,
        "tag_id_list": tagIds,
        "tag_group_id_list": [],
        "template_id_list": templateIds
      });

      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true) {
        await fetchAllData(); 
        return true;
      }
    } catch (e) {
      print("Error creating group: $e");
    }
    return false;
  }
}