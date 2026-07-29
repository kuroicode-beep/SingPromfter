import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/controllers/playback_controller.dart';

// 반주를 물리는 동안 도착한 길이를 초기화가 도로 지우면 안 된다.
// (지우면 진행바 총 시간·End 키·가사 추정 이동이 전부 죽는다.)
void main() {
  test('길이 초기화는 새 길이가 도착하기 전에 일어난다', () {
    // prepareAudioForSelection의 순서를 스냅샷 수준에서 재현한다.
    var state = const PlaybackSnapshot(duration: Duration(seconds: 200));

    // 1) 이전 곡 길이를 먼저 버린다.
    state = state.copyWith(duration: Duration.zero);
    expect(state.duration, Duration.zero);

    // 2) 준비 중 네이티브에서 새 길이가 도착한다.
    state = state.copyWith(duration: const Duration(seconds: 247));

    // 3) 준비 완료 표시는 길이를 건드리지 않는다.
    state = state.copyWith(audioReady: true);

    expect(state.duration, const Duration(seconds: 247));
    expect(state.audioReady, isTrue);
  });

  test('copyWith는 duration을 생략하면 유지한다', () {
    const state = PlaybackSnapshot(duration: Duration(seconds: 100));
    expect(state.copyWith(playing: true).duration, const Duration(seconds: 100));
  });

  test('곡 선택 해제는 길이를 0으로 되돌린다', () {
    const state = PlaybackSnapshot(duration: Duration(seconds: 100));
    final cleared = state.copyWith(
      clearSong: true,
      clearTrack: true,
      duration: Duration.zero,
    );
    expect(cleared.duration, Duration.zero);
    expect(cleared.song, isNull);
  });
}
