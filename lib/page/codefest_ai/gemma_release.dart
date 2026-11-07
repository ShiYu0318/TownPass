// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter/services.dart';

/// Trusted metadata is compiled into the App; never fetched from a user URL.
class GemmaRelease {
  static const officialSource =
      'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/42d538a932e8d5b12e6b3b455f5572560bd60b2c/gemma3-1b-it-int4.litertlm';
  static const revision = '42d538a932e8d5b12e6b3b455f5572560bd60b2c';
  static const size = 584417280;
  static const expectedDigest =
      '1325ae366d31950f137c9c357b9fa89448b176d76998180c08ceaca78bba98be';
  static const download =
      'https://home.yoyo899843.com/models/gemma3-1b-it-int4.litertlm';
  final bool available;
  final String? digest;
  final String agreement, policy, notice;
  GemmaRelease._(
    this.available,
    this.digest,
    this.agreement,
    this.policy,
    this.notice,
  );
  factory GemmaRelease.parse(Map<String, dynamic> value) {
    if (value['schema'] != 1 ||
        value['available'] is! bool ||
        value['source'] != officialSource ||
        value['revision'] != revision ||
        value['size'] != size ||
        value['download_url'] != download) {
      throw const FormatException('Invalid approved model release');
    }
    for (final key in ['agreement', 'policy', 'notice']) {
      if (value[key] is! String || (value[key] as String).isEmpty) {
        throw const FormatException('Missing model terms');
      }
    }
    final digest = value['sha256'];
    if (value['available'] == true && (digest != expectedDigest)) {
      throw const FormatException('Missing pinned model hash');
    }
    return GemmaRelease._(
      value['available'],
      digest is String ? digest : null,
      value['agreement'],
      value['policy'],
      value['notice'],
    );
  }
  static Future<GemmaRelease> load() async => GemmaRelease.parse(
    jsonDecode(await rootBundle.loadString('assets/gemma_release.json'))
        as Map<String, dynamic>,
  );
}
