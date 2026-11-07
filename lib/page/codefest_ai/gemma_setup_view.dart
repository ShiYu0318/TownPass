// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:town_pass/page/codefest_ai/gemma_model_store.dart';

class GemmaSetupView extends StatefulWidget {
  const GemmaSetupView({super.key});
  @override
  State<GemmaSetupView> createState() => _GemmaSetupState();
}

class _GemmaSetupState extends State<GemmaSetupView>
    with WidgetsBindingObserver {
  final token = TextEditingController();
  bool accepted = false, downloading = false, installed = false;
  double progress = 0;
  String? notice;
  GemmaModelStore? store;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) store?.cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store?.cancel();
    token.clear();
    token.dispose();
    super.dispose();
  }

  Future<void> install() async {
    if (!accepted || downloading) return;
    setState(() {
      downloading = true;
      notice = null;
      progress = 0;
    });
    final current = GemmaModelStore();
    store = current;
    final credential = token.text.trim();
    token.clear();
    try {
      await current.install(
        termsAccepted: accepted,
        token: credential,
        onProgress: (value) {
          if (mounted && (value - progress > .005 || value == 1)) {
            setState(() => progress = value);
          }
        },
      );
      if (mounted) {
        setState(() {
          installed = true;
          notice = '已驗證並安裝 Google Gemma 3。回到聊天後即可使用。';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => notice = '安裝未完成。請確認已在 Hugging Face 接受模型授權、Token 有讀取權限、網路與可用儲存空間，再重試。未使用其他下載來源。',
        );
      }
    } finally {
      current.cancel();
      if (mounted) setState(() => downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('安裝手機聊天模型')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Google Gemma 3 1B',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            '首次安裝需要網路，下載約 584 MB。建議預留至少 2 GB 儲存空間、4 GB 以上記憶體；實際速度依手機而異。安裝後，對話在裝置端執行。',
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: downloading
                ? null
                : () => launchUrl(
                    Uri.parse(
                      'https://huggingface.co/litert-community/Gemma3-1B-IT',
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
            child: const Text('用自己的帳號接受模型授權'),
          ),
          TextButton(
            onPressed: downloading
                ? null
                : () => launchUrl(
                    Uri.parse('https://ai.google.dev/gemma/terms'),
                    mode: LaunchMode.externalApplication,
                  ),
            child: const Text('閱讀 Gemma 授權條款'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: accepted,
            onChanged: downloading
                ? null
                : (value) => setState(() => accepted = value ?? false),
            title: const Text('我已閱讀並接受 Gemma 條款，且有模型存取權限'),
          ),
          TextField(
            controller: token,
            enabled: !downloading && !installed,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Hugging Face Read Token（僅本次下載）',
              helperText: '只傳送到 Hugging Face，不保存、不交給網頁或聊天模型。',
            ),
          ),
          const SizedBox(height: 20),
          if (downloading) ...[
            LinearProgressIndicator(value: progress),
            Text('下載／驗證中 ${(progress * 100).toStringAsFixed(0)}%'),
            TextButton(
              onPressed: () => store?.cancel(),
              child: const Text('取消安裝'),
            ),
          ],
          FilledButton(
            onPressed: accepted && !downloading && !installed ? install : null,
            child: const Text('下載並驗證官方模型'),
          ),
          if (notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(notice!),
            ),
          if (installed)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('回到聊天'),
            ),
        ],
      ),
    ),
  );
}
