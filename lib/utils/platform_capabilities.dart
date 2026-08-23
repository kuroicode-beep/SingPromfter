// file: lib/utils/platform_capabilities.dart
//
// "이 플랫폼에서 되는 일인가"를 답하는 단일 결정점. AiGate가 설정을 보고
// 답한다면, 이쪽은 플랫폼을 보고 답한다 — 사용자가 켤 수 없는 것들이다.
//
// 안드로이드가 데스크탑과 다른 지점은 셋이다.
//   ① 앱이 외부 실행파일(ffmpeg·yt-dlp·node)을 돌릴 수 없다 — 샌드박스.
//   ② 로컬 AI 서버(SAW)는 PC에 있다. 폰의 127.0.0.1은 폰 자신이라 닿지 않는다.
//   ③ 창 제어(window_manager)가 없다. 전체화면은 SystemChrome이 맡는다.
//
// 켤 수 없는 기능은 '(꺼짐)' 라벨도 달지 않고 아예 감춘다 — 설정에서 켤
// 방법이 없는데 자리만 지키면 사용자는 켜는 방법을 찾아 헤맨다.
import 'dart:io';

import 'package:flutter/foundation.dart';

class PlatformCapabilities {
  PlatformCapabilities._();

  /// 테스트에서 모바일 환경을 흉내내기 위한 우회로. 프로덕션에서는 null이다.
  @visibleForTesting
  static bool? debugIsMobileOverride;

  static bool get isMobile =>
      debugIsMobileOverride ?? (Platform.isAndroid || Platform.isIOS);

  /// ffmpeg·yt-dlp 같은 외부 실행파일을 부를 수 있나.
  /// 믹스·듀엣·키 변주·조성 감지·EQ 분석·가사 자동 맞춤·유튜브 다운로드가
  /// 전부 여기에 걸린다(AI가 아니라 외부 도구 의존이다).
  static bool get hasExternalTools => !isMobile;

  /// 로컬 AI 서버(SAW)에 닿을 수 있나. 폰에서는 PC 원격 위임을 붙이기
  /// 전까지 불가능하다.
  static bool get hasLocalAi => !isMobile;

  /// 마이크 녹음이 가능한가. 현재 녹음은 ffmpeg DirectShow(Windows 전용)라
  /// 모바일에서는 불가 — `record` 패키지로 갈아탈 때 여기만 바꾸면 된다.
  static bool get hasDeviceRecording => !isMobile;

  /// 창 크기·전체화면을 앱이 직접 제어할 수 있나(window_manager).
  static bool get hasWindowControl => !isMobile && Platform.isWindows;

  /// 제어 API 서버(MCP 입구)를 띄울 수 있나. 모바일은 백그라운드 수명이
  /// 보장되지 않고, PC에서 폰의 루프백에 닿을 수도 없다.
  static bool get hasControlServer => !isMobile;

  /// 파일을 앱 밖 폴더로 내보낼 수 있나. 모바일은 Scoped Storage라
  /// 임의 경로에 쓰지 못한다(공유 시트·SAF로 대체해야 한다).
  static bool get hasFreeFileExport => !isMobile;
}
