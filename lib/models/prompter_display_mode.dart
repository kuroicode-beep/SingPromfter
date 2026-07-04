// file: lib/models/prompter_display_mode.dart
//
// 프롬pter 가사 표시 방식. 하이라이트 모드의 줄 이동은 자동 스크롤 타이머 기준이다.
enum PrompterDisplayMode {
  full,
  highlight,
}

extension PrompterDisplayModeCodec on PrompterDisplayMode {
  String get storageValue => name;

  static PrompterDisplayMode fromStorage(String? raw) {
    if (raw == PrompterDisplayMode.highlight.name) {
      return PrompterDisplayMode.highlight;
    }
    return PrompterDisplayMode.full;
  }
}
