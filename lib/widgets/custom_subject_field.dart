import 'package:flutter/material.dart';

class CustomSubjectField extends StatelessWidget {
  const CustomSubjectField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.savedSubjects,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> savedSubjects;

  static const _manualSubject = '\u0000enter_custom_subject';

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    focusNode: focusNode,
    maxLength: 100,
    textCapitalization: TextCapitalization.sentences,
    decoration: InputDecoration(
      labelText: 'Subject (optional)',
      hintText: 'Select or type a subject',
      suffixIcon: PopupMenuButton<String>(
        tooltip: 'Choose a saved subject',
        icon: const Icon(Icons.arrow_drop_down),
        onSelected: (value) {
          if (value == _manualSubject) {
            // Wait until the popup route has finished dismissing before
            // attaching focus to the text field below it.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (focusNode.canRequestFocus) focusNode.requestFocus();
            });
            return;
          }
          controller.value = TextEditingValue(
            text: value,
            selection: TextSelection.collapsed(offset: value.length),
          );
        },
        itemBuilder: (context) => [
          ...savedSubjects.map(
            (value) => PopupMenuItem<String>(
              value: value,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: _manualSubject,
            child: Text('Enter a different subject…'),
          ),
        ],
      ),
    ),
  );
}
