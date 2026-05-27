import 'dart:convert';
import 'package:yanji/models/template.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TemplateService {
  static const String _templatesKey = 'meeting_summary_templates';
  static const String _defaultTemplatesKey = 'default_templates_loaded';
  
  // 内置模板（非默认，用户可手动设为默认）
  static final List<Template> _defaultTemplates = [
    Template(
      id: 'executive_summary',
      name: 'Executive 摘要',
      description: '生成简洁明了的摘要，突出关键决策和行动项',
      prompt: '请根据以下会议内容生成摘要，包含：1.会议主题 2.关键决策 3.重要讨论点 4.后续行动项\n\n会议内容：{{content}}',
    ),
    Template(
      id: 'detailed_summary',
      name: '详细纪要',
      description: '生成包含所有讨论内容的详细会议纪要',
      prompt: '请根据以下会议内容生成详细会议纪要，包含：1.会议基本信息 2.参会人员 3.议程和讨论内容 4.决策事项 5.行动项和负责人 6.下次会议安排（如果有）\n\n会议内容：{{content}}',
    ),
    Template(
      id: 'action_items',
      name: '行动项清单',
      description: '提取会议中的所有行动项和责任人',
      prompt: '请从以下会议内容中提取所有行动项，为每个行动项指定责任人和截止日期（如果提及），以清单形式输出：\n\n会议内容：{{content}}',
    ),
    Template(
      id: 'decision_log',
      name: '决策日志',
      description: '专门记录会议中做出的重要决策',
      prompt: '请从以下会议内容中提取所有决策事项，包括决策背景、决策内容和决策理由：\n\n会议内容：{{content}}',
    ),
    Template(
      id: 'q_and_a',
      name: '问答整理',
      description: '整理会议中的问答内容',
      prompt: '请整理以下会议内容中的问答部分，按问题分类并给出回答：\n\n会议内容：{{content}}',
    ),
  ];

  /// 获取默认模板
  List<Template> get defaultTemplates => _defaultTemplates;

  /// 加载用户自定义模板
  Future<List<Template>> loadCustomTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final templatesJson = prefs.getString(_templatesKey) ?? '[]';
    
    try {
      final List<dynamic> templatesData = jsonDecode(templatesJson);
      return templatesData
          .map((data) => Template.fromJson(Map<String, dynamic>.from(data)))
          .toList();
    } catch (e) {
      print('Error loading custom templates: $e');
      return [];
    }
  }

  /// 保存用户自定义模板
  Future<void> saveCustomTemplates(List<Template> templates) async {
    final prefs = await SharedPreferences.getInstance();
    final templatesJson = jsonEncode(
        templates.map((template) => template.toJson()).toList());
    await prefs.setString(_templatesKey, templatesJson);
  }

  /// 确保默认模板已加载（不再将默认模板写入 SharedPreferences，避免重复）
  Future<void> ensureDefaultTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoaded = prefs.getBool(_defaultTemplatesKey) ?? false;
    if (!isLoaded) {
      await prefs.setBool(_defaultTemplatesKey, true);
    }
  }

  /// 添加新模板
  Future<void> addTemplate(Template template) async {
    final templates = await loadCustomTemplates();
    templates.add(template);
    await saveCustomTemplates(templates);
  }

  /// 更新模板
  Future<void> updateTemplate(Template updatedTemplate) async {
    final templates = await loadCustomTemplates();
    final index = templates.indexWhere((t) => t.id == updatedTemplate.id);
    if (index != -1) {
      templates[index] = updatedTemplate;
      await saveCustomTemplates(templates);
    }
  }

  /// 删除模板
  Future<void> deleteTemplate(String templateId) async {
    final templates = await loadCustomTemplates();
    templates.removeWhere((t) => t.id == templateId);
    await saveCustomTemplates(templates);
  }

  /// 获取所有模板（默认+自定义，去重）
  Future<List<Template>> getAllTemplates() async {
    await ensureDefaultTemplates();
    final defaultIds = _defaultTemplates.map((t) => t.id).toSet();
    final allRaw = await loadCustomTemplates();
    final customTemplates = allRaw.where((t) => !defaultIds.contains(t.id)).toList();
    return [..._defaultTemplates, ...customTemplates];
  }

  /// 根据ID获取模板
  Future<Template?> getTemplateById(String id) async {
    final templates = await getAllTemplates();
    try {
      return templates.firstWhere((template) => template.id == id);
    } catch (e) {
      return null;
    }
  }

  static const String _defaultTemplateIdKey = 'default_template_id';

  /// 设置默认模板
  Future<void> setDefaultTemplate(String templateId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultTemplateIdKey, templateId);
  }

  /// 获取当前默认模板 ID
  Future<String?> getDefaultTemplateId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_defaultTemplateIdKey);
  }

  /// 取消默认模板
  Future<void> clearDefaultTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_defaultTemplateIdKey);
  }
}