// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:town_pass/page/codefest_scan/codefest_scan_session.dart';

class CodefestScanView extends StatefulWidget {
  const CodefestScanView({super.key, required this.session});
  final CodefestScanSession session;
  @override
  State<CodefestScanView> createState() => _CodefestScanViewState();
}

class _CodefestScanViewState extends State<CodefestScanView>
    with WidgetsBindingObserver {
  final _camera = MobileScannerController(
    autoStart: false,
    formats: [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_checkClose);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkClose();
      if (mounted && !widget.session.closing) unawaited(_start());
    });
  }

  Future<void> _start() async {
    try {
      await _camera.start();
    } catch (_) {
      /* MobileScanner errorBuilder displays camera failure. */
    }
  }

  Future<void> _stop() async {
    try {
      await _camera.stop();
    } catch (_) {}
  }

  void _checkClose() {
    if (mounted &&
        widget.session.closing &&
        ModalRoute.of(context)?.isCurrent == true)
      Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !widget.session.closing)
      unawaited(_start());
    else if (state != AppLifecycleState.resumed)
      unawaited(_stop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_checkClose);
    unawaited(_camera.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('持續掃碼導航'),
        leading: CloseButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: MobileScanner(
                controller: _camera,
                onDetect: (capture) {
                  if (!mounted) return;
                  for (final code in capture.barcodes) {
                    final payload = code.rawValue;
                    if (payload != null &&
                        widget.session.acceptPayload(payload))
                      break;
                  }
                },
                errorBuilder: (context, error) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('相機不可用或尚未授權。請確認權限；可返回網頁，保留目的地。'),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: ValueListenableBuilder<Map<String, Object>>(
                valueListenable: widget.session,
                builder: (context, guide, child) => Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${guide['title']} · ${guide['floor']}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                guide['instruction']! as String,
                                style: const TextStyle(
                                  fontSize: 22,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '掃下一個定位碼即可更新位置。重複影格不會反覆重算；同碼需按下方重新讀取。',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed: guide['canAdvance'] == true
                                ? () => widget.session.requestAdvance(
                                    guide['guidanceToken']! as String,
                                  )
                                : null,
                            child: Text(guide['nextLabel']! as String),
                          ),
                          OutlinedButton(
                            onPressed: () {
                              widget.session.allowSameCodeAgain();
                            },
                            child: const Text('重新讀取同一碼'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('關閉相機，回導航'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
