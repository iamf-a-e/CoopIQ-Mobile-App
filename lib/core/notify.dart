import 'package:flutter/material.dart';
import 'theme.dart';

Future<void> showNotice(
  BuildContext context, {
  required String title,
  required String message,
  bool error = false,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false, // must tap OK
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      icon: Icon(
        error ? Icons.error_outline : Icons.check_circle_outline,
        size: 48,
        color: error ? ctx.danger : Theme.of(ctx).colorScheme.primary,
      ),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(message, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}