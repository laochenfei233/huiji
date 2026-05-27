import 'package:flutter/material.dart';
import 'package:yanji/models/template.dart';
import 'package:yanji/services/template_service.dart';

class TemplateManagementScreen extends StatefulWidget {
  const TemplateManagementScreen({super.key});

  @override
  State<TemplateManagementScreen> createState() =>
      _TemplateManagementScreenState();
}

class _TemplateManagementScreenState extends State<TemplateManagementScreen> {
  final TemplateService _templateService = TemplateService();
  List<Template> _templates = [];
  bool _isLoading = true;
  String? _defaultTemplateId;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() => _isLoading = true);

    try {
      final templates = await _templateService.getAllTemplates();
      final defaultId = await _templateService.getDefaultTemplateId();
      setState(() {
        _templates = templates;
        _defaultTemplateId = defaultId;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载模板失败: $e')),
        );
      }
    }
  }

  Future<void> _toggleDefault(Template template) async {
    if (_defaultTemplateId == template.id) {
      await _templateService.clearDefaultTemplate();
    } else {
      await _templateService.setDefaultTemplate(template.id);
    }
    _loadTemplates();
  }

  void _addNewTemplate() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TemplateEditorScreen(
          template: null,
          onSave: _saveTemplate,
        ),
      ),
    );
  }

  void _editTemplate(Template template) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TemplateEditorScreen(
          template: template,
          onSave: _saveTemplate,
        ),
      ),
    );
  }

  Future<void> _saveTemplate(Template template) async {
    try {
      if (template.id.isEmpty) {
        // 新模板
        final newTemplate = template.copyWith(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
        );
        await _templateService.addTemplate(newTemplate);
      } else {
        // 更新现有模板
        await _templateService.updateTemplate(template);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('模板保存成功')),
        );
        _loadTemplates();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存模板失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteTemplate(String templateId) async {
    try {
      if (_defaultTemplateId == templateId) {
        await _templateService.clearDefaultTemplate();
      }
      await _templateService.deleteTemplate(templateId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('模板删除成功')),
        );
        _loadTemplates();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除模板失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('模板管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addNewTemplate,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _templates.length,
              itemBuilder: (context, index) {
                final template = _templates[index];
                final isDefault = _defaultTemplateId == template.id;
                return Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: ListTile(
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(template.name),
                        ),
                        if (isDefault)
                          const Chip(
                            label: Text(
                              '默认',
                              style: TextStyle(fontSize: 12),
                            ),
                            backgroundColor: Color(0xFF4A90D9),
                            labelStyle: TextStyle(color: Colors.white),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      template.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _editTemplate(template),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            isDefault ? Icons.star : Icons.star_border,
                            color: isDefault ? Colors.amber : null,
                          ),
                          tooltip: isDefault ? '取消默认' : '设为默认',
                          onPressed: () => _toggleDefault(template),
                        ),
                        if (!isDefault)
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _deleteTemplate(template.id),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewTemplate,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class TemplateEditorScreen extends StatefulWidget {
  final Template? template;
  final Function(Template) onSave;

  const TemplateEditorScreen({
    super.key,
    required this.template,
    required this.onSave,
  });

  @override
  State<TemplateEditorScreen> createState() => _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends State<TemplateEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _promptController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.template?.name ?? '');
    _descriptionController =
        TextEditingController(text: widget.template?.description ?? '');
    _promptController =
        TextEditingController(text: widget.template?.prompt ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  void _saveTemplate() {
    if (_formKey.currentState!.validate()) {
      final template = Template(
        id: widget.template?.id ?? '',
        name: _nameController.text,
        description: _descriptionController.text,
        prompt: _promptController.text,
        isDefault: widget.template?.isDefault ?? false,
      );

      widget.onSave(template);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.template == null ? '新建模板' : '编辑模板'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveTemplate,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '模板名称',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入模板名称';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: '模板描述',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入模板描述';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const Text(
                '提示词模板',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '使用 {{content}} 作为会议内容的占位符',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TextFormField(
                  controller: _promptController,
                  decoration: const InputDecoration(
                    hintText: '在此输入提示词模板...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: null,
                  expands: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入提示词模板';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}