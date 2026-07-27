// file: lib/models/app_destination.dart
//
// 상단 탭에서 선택 가능한 주요 화면 구분.
// 라벨·아이콘을 여기 두어 탭 목록을 하드코딩하지 않고 순회로 만든다.
import 'package:flutter/material.dart';

enum AppDestination { home, search, favorites, recordings, jobs, settings }

extension AppDestinationInfo on AppDestination {
  String get label => switch (this) {
    AppDestination.home => '홈',
    AppDestination.search => '곡 검색',
    AppDestination.favorites => '즐겨찾기',
    AppDestination.recordings => '녹음',
    AppDestination.jobs => '가져오기',
    AppDestination.settings => '설정',
  };

  IconData get icon => switch (this) {
    AppDestination.home => Icons.home_outlined,
    AppDestination.search => Icons.search,
    AppDestination.favorites => Icons.star_border,
    AppDestination.recordings => Icons.mic_none,
    AppDestination.jobs => Icons.download_outlined,
    AppDestination.settings => Icons.settings_outlined,
  };

  /// 스크린 리더용 라벨.
  String get semanticsLabel => '$label 화면';
}
