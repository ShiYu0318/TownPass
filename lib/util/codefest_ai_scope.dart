// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Native cleanup cannot depend on JavaScript firing during WebView disposal.
class CodefestAIScope extends StatefulWidget {
  const CodefestAIScope({super.key, required this.child});
  final Widget child;
  static Future<void> stop() async {
    try {
      await const MethodChannel('codefest/on_device_ai').invokeMethod('unload');
    } on PlatformException {
      /* Host may already be tearing down. */
    } on MissingPluginException {
      /* Other platforms do not expose local AI. */
    }
  }

  @override
  State<CodefestAIScope> createState() => _CodefestAIScopeState();
}

class _CodefestAIScopeState extends State<CodefestAIScope> {
  @override
  void dispose() {
    unawaited(CodefestAIScope.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
