import 'package:flutter/material.dart';

import '../data/app_database.dart';

class CustomSubjectsScreen extends StatefulWidget {
  const CustomSubjectsScreen({super.key, required this.database});

  final AppDatabase database;

  @override
  State<CustomSubjectsScreen> createState() => _CustomSubjectsScreenState();
}

class _CustomSubjectsScreenState extends State<CustomSubjectsScreen> {
  List<String>? _subjects;
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    try {
      final subjects = await widget.database.customSubjects();
      if (!mounted) return;
      setState(() {
        _subjects = subjects;
        _loading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _editSubject({String? existing}) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _SubjectEditorDialog(existing: existing),
    );
    if (value == null || !mounted) return;
    try {
      if (existing == null) {
        await widget.database.addCustomSubject(value);
      } else {
        await widget.database.renameCustomSubject(existing, value);
      }
      await _loadSubjects();
    } on FormatException catch (error) {
      if (mounted) _showError(error.message.toString());
    } catch (_) {
      if (mounted) {
        _showError('Could not update saved subjects. Please try again.');
      }
    }
  }

  Future<void> _delete(String subject) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete saved subject?'),
        content: Text(
          '“$subject” will be removed from future selections. Existing expenses will not change.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.database.deleteCustomSubject(subject);
      await _loadSubjects();
    } catch (_) {
      if (mounted) {
        _showError('Could not delete the saved subject. Please try again.');
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Customized Subject Drop-down Menu')),
    backgroundColor: Theme.of(context).colorScheme.surface,
    body: Builder(
      builder: (context) {
        if (_loading) {
          return Center(
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
          );
        }
        if (_loadFailed) {
          return const Center(child: Text('Could not load saved subjects.'));
        }
        final subjects = _subjects ?? const <String>[];
        if (subjects.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'No saved subjects yet. Add subjects you use often; you can still type any subject when adding an expense.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: subjects.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final subject = subjects[index];
            return ListTile(
              title: Text(
                subject,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: const Text('Changes apply to future selections only.'),
              trailing: Wrap(
                spacing: 0,
                children: [
                  IconButton(
                    tooltip: 'Rename',
                    onPressed: () => _editSubject(existing: subject),
                    icon: Icon(
                      Icons.edit_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: () => _delete(subject),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            );
          },
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _editSubject(),
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Theme.of(context).colorScheme.onPrimary,
      icon: const Icon(Icons.add),
      label: const Text('Add subject'),
    ),
  );
}

class _SubjectEditorDialog extends StatefulWidget {
  const _SubjectEditorDialog({this.existing});

  final String? existing;

  @override
  State<_SubjectEditorDialog> createState() => _SubjectEditorDialogState();
}

class _SubjectEditorDialogState extends State<_SubjectEditorDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.existing);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return AlertDialog(
      title: Text(existing == null ? 'Add subject' : 'Rename subject'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 100,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Subject'),
        onSubmitted: (text) => Navigator.pop(context, text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(existing == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
