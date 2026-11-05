import 'package:flutter/material.dart';

class ShellScope extends InheritedWidget {
  final String role;
  final void Function(int) selectTab;
  const ShellScope({
    super.key,
    required this.role,
    required this.selectTab,
    required super.child,
  });
  static ShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>();
  @override
  bool updateShouldNotify(ShellScope old) =>
      old.role != role || old.selectTab != selectTab;
}
