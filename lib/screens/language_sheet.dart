import 'package:flutter/material.dart';
import '../core/settings.dart';
import '../core/strings.dart';
import '../core/theme.dart';

/// Bottom sheet to pick the app language. The whole app switches immediately.
Future<void> showLanguageSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final current = Settings.instance.lang;
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(ctx.tr('choose_language'), style: Theme.of(ctx).textTheme.titleLarge),
            ),
          ),
          for (final l in Strings.languages)
            ListTile(
              title: Text(l.name),
              trailing: l.code == current ? Icon(Icons.check_circle, color: ctx.brand) : null,
              onTap: () {
                Settings.instance.setLang(l.code);
                Navigator.pop(ctx);
              },
            ),
          const SizedBox(height: 8),
        ]),
      );
    },
  );
}
