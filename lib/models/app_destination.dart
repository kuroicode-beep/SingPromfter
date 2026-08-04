// file: lib/models/app_destination.dart
//
// 상단 탭에서 선택 가능한 주요 화면 구분.
// 라벨·아이콘을 여기 두어 탭 목록을 하드코딩하지 않고 순회로 만든다.
// 순서가 곧 상단 메뉴 순서다(v4.0.0 사용자 지정):
// 홈 / 검색 / 유튜브 / 즐겨찾기 / 트레이닝 / 녹음 / 가져오기 이력 / 도움말 / 설정
import 'package:flutter/material.dart';

enum AppDestination {
  home,
  search,
  youtube,
  favorites,
  training,
  recordings,
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
    AppDestination.jobs => Icons.download_outlined,
    AppDestination.help => Icons.help_outline,
    AppDestination.settings => Icons.settings_outlined,
  };

  /// 스크린 리더용 라벨.
  String get semanticsLabel => '$label 화면';
}
