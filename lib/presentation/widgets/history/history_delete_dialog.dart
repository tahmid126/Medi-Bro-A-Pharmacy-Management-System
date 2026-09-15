import 'package:flutter/material.dart';

class HistoryDeleteDialog extends StatelessWidget {
  final String title;
  final String contentText;
  final String confirmButtonText;

  const HistoryDeleteDialog({
    super.key,
    required this.title,
    required this.contentText,
    this.confirmButtonText = 'Delete',
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(contentText),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: Text(confirmButtonText),
        ),
      ],
    );
  }
}
