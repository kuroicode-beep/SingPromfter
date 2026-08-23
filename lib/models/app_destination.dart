// file: lib/models/app_destination.dart
//
// 상단 탭에서 선택 가능한 주요 화면 구분.
// 라벨·아이콘을 여기 두어 탭 목록을 하드코딩하지 않고 순회로 만든다.
// 순서가 곧 상단 메뉴 순서다(v4.0.0 사용자 지정 + v5.0.0 작곡 추가):
// 홈 / 검색 / 유튜브 / 즐겨찾기 / 트레이닝 / 녹음 / 작곡 / 가져오기 이력 / 도움말 / 설정
import 'package:flutter/material.dart';

import '../utils/platform_capabilities.dart';

enum AppDestination {
  home,
  search,
  youtube,
  favorites,
  training,
  recordings,
  compose,
  jobs,
  help,
  settings,
}

extension AppDestinationInfo on AppDestination {
  String get label => switch (this) {
    AppDestination.home => '홈',
    AppDestination.search => '검색',
    AppDestination.youtube => '유튜브',
    AppDestination.favorites => '즐겨찾기',
    AppDestination.training => '트레이닝',
    AppDestination.recordings => '녹음',
    AppDestination.compose => '작곡',
    AppDestination.jobs => '가져오기 이력',
    AppDestination.help => '도움말',
    AppDestination.settings => '설정',
  };

  IconData get icon => switch (this) {
    AppDestination.home => Icons.home_outlined,
    AppDestination.search => Icons.search,
    AppDestination.youtube => Icons.smart_display_outlined,
    AppDestination.favorites => Icons.star_border,
    AppDestination.training => Icons.fitness_center,
    AppDestination.recordings => Icons.mic_none,
    AppDestination.compose => Icons.music_note_outlined,
    AppDestination.jobs => Icons.download_outlined,
    AppDestination.help => Icons.help_outline,
    AppDestination.settings => Icons.settings_outlined,
  };

  /// 스크린 리더용 라벨.
  String get semanticsLabel => '$label 화면';
}

/// 이 플랫폼에서 아예 쓸 수 없어 탭 목록에서 빼는 화면들.
///
/// 설정에서 켤 수 있는 것과 구분한다 — 작곡 탭은 PC에서 '작곡(꺼짐)'으로
/// 자리를 지키지만, 모바일에서는 켤 방법 자체가 없으므로 감춘다.
Set<AppDestination> get unavailableDestinations => {
  // 녹음은 ffmpeg DirectShow(Windows 전용)에 묶여 있다.
  if (!PlatformCapabilities.hasDeviceRecording) AppDestination.recordings,
  // 유튜브 검색은 되지만 가져오기(yt-dlp)가 안 된다 — 반쪽짜리 탭을
  // 남기면 "검색은 되는데 왜 못 가져오지"가 된다. 이력 탭도 함께 뺀다.
  if (!PlatformCapabilities.hasExternalTools) ...{
    AppDestination.youtube,
    AppDestination.jobs,
  },
  // 로컬 AI 서버는 PC에 있다.
  if (!PlatformCapabilities.hasLocalAi) AppDestination.compose,
};
