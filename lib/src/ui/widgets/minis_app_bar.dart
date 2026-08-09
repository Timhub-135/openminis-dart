import 'package:flutter/material.dart';

/// A consistent AppBar for pushed sub-screens: always shows a back arrow so
/// navigation is uniform across every page (settings sub-screens, wiki, etc.).
/// Falls back to `Navigator.maybePop` so it works whether or not a parent
/// exists in the stack.
class MinisAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final bool showBack;

  const MinisAppBar({super.key, this.title, this.titleWidget, this.actions, this.showBack = true});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: titleWidget ?? (title == null ? null : Text(title!)),
      leading: showBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: '返回',
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : null,
      actions: actions,
    );
  }
}
