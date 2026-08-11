import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


/// iOS's own usage figure for today, rendered by a sandboxed extension.
/// The app can display it but never read the number.
class ScreenTimeReport extends StatelessWidget {
  const ScreenTimeReport({super.key, this.height = 140});

  final double height;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      child: const UiKitView(
        viewType: 'screenstreaks/report',
        creationParamsCodec: StandardMessageCodec(),
      ),
    );
  }
}
