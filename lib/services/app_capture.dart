// file: lib/services/app_capture.dart
//
// 앱 자기 화면 캡처. 제어 API(POST /api/screenshot)가 랜딩 페이지 스크린샷
// 같은 자동화에 쓴다 — OS 캡처는 백신·권한 문제가 있어 앱이 직접 찍는다.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 앱 루트(RepaintBoundary)의 키. main.dart가 빌더에서 감싼다.
final GlobalKey appCaptureBoundaryKey = GlobalKey(debugLabel: 'app-capture');

/// 현재 창 내용을 PNG로 저장한다. 성공하면 저장 경로, 실패하면 null.
Future<String?> captureAppScreenshot(String path) async {
  try {
    final boundary = appCaptureBoundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) return null;
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return path;
  } catch (e, stack) {
    debugPrint('앱 화면 캡처 실패: $e\n$stack');
    return null;
  }
}
