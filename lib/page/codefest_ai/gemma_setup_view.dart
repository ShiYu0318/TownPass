// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:town_pass/page/codefest_ai/gemma_model_store.dart';
import 'package:town_pass/page/codefest_ai/gemma_release.dart';

class GemmaSetupView extends StatefulWidget {
  const GemmaSetupView({super.key});
  @override
  State<GemmaSetupView> createState() => _GemmaSetupState();
}

class _GemmaSetupState extends State<GemmaSetupView>
    with WidgetsBindingObserver {
  bool accepted = false, downloading = false, installed = false;
  double progress = 0;
  String? notice;
  GemmaModelStore? store;
  GemmaRelease? release;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GemmaRelease.load()
        .then((value) {
          if (mounted) setState(() => release = value);
        })
        .catchError((_) {
          if (mounted) setState(() => notice = '模型下載資訊尚未準備好。請更新 App，導航功能仍可使用。');
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) store?.cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store?.cancel();
    super.dispose();
  }

  void showTerms() {
    final current = release;
    if (current == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gemma 模型條款'),
        scrollable: true,
        content: SelectableText(
          '${current.agreement}\n\n${current.policy}\n\n${current.notice}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  Future<void> install() async {
    final currentRelease = release;
    if (!accepted || downloading || currentRelease?.available != true) return;
    setState(() {
      downloading = true;
      notice = null;
      progress = 0;
    });
    final current = GemmaModelStore();
    store = current;
    try {
      await current.install(
        termsAccepted: accepted,
        release: currentRelease,
        onProgress: (value) {
          if (mounted && (value - progress > .005 || value == 1)) {
            setState(() => progress = value);
          }
        },
      );
      if (mounted) {
        setState(() {
          installed = true;
          notice = '模型已下載並驗證完成。之後可離線聊天。';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => notice = '下載尚未完成。請確認網路與可用儲存空間，再重試。未完成的檔案不會作為聊天模型使用。');
      }
    } finally {
      current.cancel();
      if (mounted) setState(() => downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('啟用手機聊天')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            '下載一次，之後離線使用',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Google Gemma 3 1B 模型約 584 MB，建議連接 Wi-Fi，預留至少 2 GB 儲存空間。聊天在手機處理，不需要 Hugging Face 帳號、Token 或聊天 API Key。實際速度依手機而異。',
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: release != null && !downloading ? showTerms : null,
            child: const Text('閱讀模型條款與禁止用途政策'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: accepted,
            onChanged: downloading || installed
                ? null
                : (value) => setState(() => accepted = value ?? false),
            title: const Text('我同意 Gemma 使用條款與禁止用途政策，並遵守模型使用限制'),
          ),
          if (release != null && !release!.available)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('團隊正在準備模型安裝包，發布後即可一鍵下載。你仍可使用地圖與設施搜尋。'),
            ),
          if (downloading) ...[
            LinearProgressIndicator(value: progress),
            Text('下載／驗證中 ${(progress * 100).toStringAsFixed(0)}%'),
            TextButton(
              onPressed: () => store?.cancel(),
              child: const Text('取消下載'),
            ),
          ],
          FilledButton(
            onPressed:
                accepted &&
                    !downloading &&
                    !installed &&
                    release?.available == true
                ? install
                : null,
            child: const Text('同意並下載模型（約 584 MB）'),
          ),
          if (notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(notice!),
            ),
          if (installed)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('開始聊天'),
            ),
        ],
      ),
    ),
  );
}
