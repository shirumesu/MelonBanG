import 'package:flutter/widgets.dart';

import '../../features/appearance/appearance.dart';

/// The units sizes and speeds below are shown in.
class ByteUnitsScope extends InheritedWidget {
  const ByteUnitsScope({super.key, required this.units, required super.child});
  final ByteUnits units;

  static ByteUnits of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ByteUnitsScope>()!.units;

  @override
  bool updateShouldNotify(ByteUnitsScope oldWidget) => units != oldWidget.units;
}
