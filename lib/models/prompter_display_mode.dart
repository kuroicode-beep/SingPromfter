// file: lib/models/prompter_display_mode.dart
//
// 프롬프터 가사 표시 방식.
enum PrompterDisplayMode {
  /// 가사 전체를 자동 스크롤한다.
  full,

  /// 3줄 창으로 보여주며 재생 위치에 비례해 줄을 넘긴다(추정).
  highlight,

  /// 싱크 가사(LRC)의 실제 타임스탬프로 줄을 넘긴다.
  timed,
}

extension PrompterDisplayModeCodec on PrompterDisplayMode {
  String get storageValue => name;

  String get label => switch (this) {
    PrompterDisplayMode.full => '전체 가사',
    PrompterDisplayMode.highlight => '줄 하이라이트',
    PrompterDisplayMode.timed => '싱크 가사',
  };

  /// 3줄 창 레이아웃을 쓰는 모드인지.
  bool get usesWindowedLayout => this != PrompterDisplayMode.full;

  static PrompterDisplayMode fromStorage(String? raw) {
    for (final mode in PrompterDisplayMode.values) {
      if (mode.name == raw) return mode;
    }
    return PrompterDisplayMode.full;
  }
}
