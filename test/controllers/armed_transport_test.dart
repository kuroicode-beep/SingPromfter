// file: test/controllers/armed_transport_test.dart
//
// 녹음 고정 중 스페이스의 분기(진리표)와, 조각 컨텍스트·저장 안내의 순수 부품.
//
// 이 분기가 `playing`(이벤트로 늦게 서는 값)에 기대던 시절에 「멈춘 화면에서
// 유령 녹음」이 돌았다. 기준을 동기 상태(takeOpen)로 옮긴 것을 전 조합으로 고정한다.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/controllers/armed_transport.dart';

void main() {
  group('armedSpaceAction — 진리표(16조합 전부)', () {
    // (busy, sessionReady, takeOpen, playing) → 기대값
    const table = <(bool, bool, bool, bool), ArmedSpaceAction>{
      // busy가 아니고 조각이 없고 멈춰 있을 때: 준비 여부가 가른다.
      (false, false, false, false): ArmedSpaceAction.refuseNotReady,
      (false, true, false, false): ArmedSpaceAction.startTake,
      // 조각 없이 재생 중: 세션 준비와 무관하게 그냥 멈춘다.
      (false, false, false, true): ArmedSpaceAction.pauseOnly,
      (false, true, false, true): ArmedSpaceAction.pauseOnly,
      // 조각이 열려 있으면 언제나 끝낸다 — playing이 아직 false여도(이벤트 지연),
      // 세션이 준비 상태가 아니어도(끊기는 중) 부른 소리는 닫아서 저장한다.
      (false, false, true, false): ArmedSpaceAction.endTake,
      (false, false, true, true): ArmedSpaceAction.endTake,
      (false, true, true, false): ArmedSpaceAction.endTake,
      (false, true, true, true): ArmedSpaceAction.endTake,
      // busy면 나머지가 무엇이든 버린다.
      (true, false, false, false): ArmedSpaceAction.ignore,
      (true, false, false, true): ArmedSpaceAction.ignore,
      (true, false, true, false): ArmedSpaceAction.ignore,
      (true, false, true, true): ArmedSpaceAction.ignore,
      (true, true, false, false): ArmedSpaceAction.ignore,
      (true, true, false, true): ArmedSpaceAction.ignore,
      (true, true, true, false): ArmedSpaceAction.ignore,
      (true, true, true, true): ArmedSpaceAction.ignore,
    };

    test('표가 16조합을 빠짐없이 덮는다', () {
      expect(table.length, 16);
      for (final busy in [false, true]) {
        for (final ready in [false, true]) {
          for (final open in [false, true]) {
            for (final playing in [false, true]) {
              expect(
                table.containsKey((busy, ready, open, playing)),
                isTrue,
                reason: '빠진 조합: $busy/$ready/$open/$playing',
              );
            }
          }
        }
      }
    });

    for (final entry in table.entries) {
      final (busy, ready, open, playing) = entry.key;
      test('busy=$busy ready=$ready takeOpen=$open playing=$playing '
          '→ ${entry.value.name}', () {
        expect(
          armedSpaceAction(
            busy: busy,
            sessionReady: ready,
            takeOpen: open,
            playing: playing,
          ),
          entry.value,
        );
      });
    }

    test('🔴 재생 직후(playing이 아직 false)의 스페이스는 조각을 또 열지 않고 끝낸다', () {
      // forcePlay를 건 직후 — 상태 이벤트가 오기 전이라 playing은 false다.
      // 예전 기준(playing)이라면 「시작」으로 읽혀 조각을 다시 열려고 했다.
      expect(
        armedSpaceAction(
          busy: false,
          sessionReady: true,
          takeOpen: true,
          playing: false,
        ),
        ArmedSpaceAction.endTake,
      );
    });

    test('🔴 준비가 안 됐으면 재생을 걸지 않는다 — 음악만 나오는 조용한 실패 방지', () {
      final action = armedSpaceAction(
        busy: false,
        sessionReady: false,
        takeOpen: false,
        playing: false,
      );
      expect(action, ArmedSpaceAction.refuseNotReady);
      expect(action, isNot(ArmedSpaceAction.startTake));
    });
  });

  group('ArmedTakeContext — 사이드카를 오가는 조각 컨텍스트', () {
    const full = ArmedTakeContext(
      songId: 'song-1',
      songTitle: '거리에서',
      trackSlot: 2,
      pitchSemitones: -2,
      activeAudioPath: r'C:\data\cache\pitch\mr__p-2.m4a',
      tempoScale: 0.9,
    );

    test('JSON 문자열을 거쳐도 그대로 돌아온다(사이드카는 파일이다)', () {
      final decoded =
          jsonDecode(jsonEncode(full.toJson())) as Map<String, Object?>;
      final back = ArmedTakeContext.fromJson(decoded)!;
      expect(back.songId, 'song-1');
      expect(back.songTitle, '거리에서');
      expect(back.trackSlot, 2);
      expect(back.pitchSemitones, -2);
      expect(back.activeAudioPath, r'C:\data\cache\pitch\mr__p-2.m4a');
      expect(back.tempoScale, 0.9);
    });

    test('가사 전용 곡 — 슬롯·경로가 null이어도 왕복한다', () {
      const bare = ArmedTakeContext(songId: 's', songTitle: '무반주');
      final back = ArmedTakeContext.fromJson(
        jsonDecode(jsonEncode(bare.toJson())) as Map<String, Object?>,
      )!;
      expect(back.trackSlot, isNull);
      expect(back.activeAudioPath, isNull);
      expect(back.pitchSemitones, 0);
      expect(back.tempoScale, 1.0);
    });

    test('곡 id가 없으면 null — 어느 곡인지 모르는 조각이다', () {
      expect(ArmedTakeContext.fromJson(const {}), isNull);
      expect(ArmedTakeContext.fromJson(const {'songId': ''}), isNull);
      expect(ArmedTakeContext.fromJson(const {'songId': 7}), isNull);
    });

    test('형이 어긋난 값은 기본값으로 읽는다(깨진 사이드카에 관대하게)', () {
      final back = ArmedTakeContext.fromJson(const {
        'songId': 's',
        'songTitle': 12,
        'trackSlot': '2',
        'pitchSemitones': 'x',
        'activeAudioPath': '',
        'tempoScale': 0,
      })!;
      expect(back.songTitle, '');
      expect(back.trackSlot, isNull);
      expect(back.pitchSemitones, 0);
      expect(back.activeAudioPath, isNull);
      // 0배속은 말이 안 된다 — 반주 자르기가 0으로 나누지 않게 1.0으로 받는다.
      expect(back.tempoScale, 1.0);
    });

    test('정수로 저장된 템포(1)도 읽는다 — JSON은 1.0을 1로 쓰기도 한다', () {
      final back = ArmedTakeContext.fromJson(const {
        'songId': 's',
        'tempoScale': 1,
        'trackSlot': 3.0,
      })!;
      expect(back.tempoScale, 1.0);
      expect(back.trackSlot, 3);
    });

    test('fromJsonOrUnknown — 못 읽어도 소리를 버리지 않게 곡 없는 컨텍스트를 준다', () {
      final unknown = ArmedTakeContext.fromJsonOrUnknown(const {});
      expect(unknown.songId, '');
      expect(unknown.songTitle, '복구된 녹음');
      expect(
        ArmedTakeContext.fromJsonOrUnknown(full.toJson()).songId,
        'song-1',
      );
    });
  });

  group('formatSongPosition', () {
    test('분:초 — 초는 두 자리', () {
      expect(formatSongPosition(0), '0:00');
      expect(formatSongPosition(9999), '0:09');
      expect(formatSongPosition(83000), '1:23');
      expect(formatSongPosition(600000), '10:00');
    });

    test('음수는 0으로', () {
      expect(formatSongPosition(-500), '0:00');
    });
  });

  group('armedTakeSavedMessage — 「조각 저장 — m:ss부터 s.s초」', () {
    test('스페이스를 누른 자리와 부른 길이로 말한다(리드인은 뺀다)', () {
      // 파일 t=0은 곡 82.7초, 리드인 300ms → 누른 자리는 1:23. 파일 2.7초 − 0.3 = 2.4초.
      expect(
        armedTakeSavedMessage(
          songPositionMs: 82700,
          leadInMs: 300,
          durationMs: 2700,
        ),
        '조각 저장 — 1:23부터 2.4초',
      );
    });

    test('곡 맨 앞 — 리드인이 0이어도 맞다', () {
      expect(
        armedTakeSavedMessage(songPositionMs: 0, leadInMs: 0, durationMs: 1540),
        '조각 저장 — 0:00부터 1.5초',
      );
    });

    test('리드인이 파일보다 길게 적혀 있어도 음수 길이를 내지 않는다', () {
      expect(
        armedTakeSavedMessage(
          songPositionMs: 1000,
          leadInMs: 300,
          durationMs: 200,
        ),
        '조각 저장 — 0:01부터 0.0초',
      );
    });

    test('곡 위치가 의심스러우면 같은 토스트에 한 줄을 덧붙인다', () {
      final message = armedTakeSavedMessage(
        songPositionMs: 82700,
        leadInMs: 300,
        durationMs: 2700,
        timelineSuspect: true,
      );
      expect(message, startsWith('조각 저장 — 1:23부터 2.4초'));
      expect(message, contains('이 조각은 곡 위치가 부정확할 수 있습니다'));
      expect(message, contains(kArmedTimelineSuspectNote));
    });

    test('🔴 끝이 잘렸으면 같은 토스트에 알린다 — 평소 토스트와 똑같으면 모르고 넘어간다', () {
      final message = armedTakeSavedMessage(
        songPositionMs: 82700,
        leadInMs: 300,
        durationMs: 2700,
        truncated: true,
      );
      expect(const LineSplitter().convert(message), [
        '조각 저장 — 1:23부터 2.4초',
        kArmedTruncatedNote,
      ]);
      expect(kArmedTruncatedNote, contains('잘렸을 수 있습니다'));
    });

    test('구멍을 메웠으면 몇 ms인지 알린다', () {
      final message = armedTakeSavedMessage(
        songPositionMs: 82700,
        leadInMs: 300,
        durationMs: 2700,
        filledGapMs: 100,
      );
      expect(const LineSplitter().convert(message), [
        '조각 저장 — 1:23부터 2.4초',
        '녹음 중 100ms가 끊겨 무음으로 메웠습니다',
      ]);
    });

    test('안내가 겹치면 한 장에 차례로 담는다(토스트는 새로 뜨면 앞의 것을 지운다)', () {
      final message = armedTakeSavedMessage(
        songPositionMs: 82700,
        leadInMs: 300,
        durationMs: 2700,
        timelineSuspect: true,
        truncated: true,
        filledGapMs: 40,
      );
      expect(const LineSplitter().convert(message), [
        '조각 저장 — 1:23부터 2.4초',
        kArmedTruncatedNote,
        armedFilledGapNote(40),
        kArmedTimelineSuspectNote,
      ]);
    });
  });

  group('LastTakeGuard — Ctrl+R이 엉뚱한 테이크를 물리지 않게', () {
    test('평소에는 막지 않는다', () {
      final guard = LastTakeGuard();
      expect(guard.consumeBlock(), isNull);
      guard.noteCommitted();
      expect(guard.consumeBlock(), isNull);
    });

    test('🔴 직전 조각이 너무 짧아 버려졌으면 한 번 막고, 다시 누르면 통과시킨다', () {
      // 스페이스, 스페이스(실수 — 0.5초 미만), Ctrl+R. 목록의 맨 앞은 실수 조각이
      // 아니라 **그 앞의 멀쩡한 조각**이다 — 그대로 물리면 6초 뒤 파일까지 지워진다.
      final guard = LastTakeGuard()..noteDropped(kTakeDroppedTooShortNote);
      final blocked = guard.consumeBlock();
      expect(blocked, contains('너무 짧아 이미 버렸습니다'));
      expect(blocked, contains('취소할 것이 없습니다'));
      // 정말 앞 조각을 물리려는 것이면 한 번 더 누른다.
      expect(guard.consumeBlock(), isNull);
    });

    test('저장 실패도 같은 구멍이다', () {
      final guard = LastTakeGuard()..noteDropped(kTakeDroppedSaveFailedNote);
      expect(guard.consumeBlock(), contains('저장되지 않았습니다'));
    });

    test('그 뒤에 새 테이크가 올라오면 풀린다 — 맨 앞이 다시 「직전 녹음」이다', () {
      final guard = LastTakeGuard()
        ..noteDropped(kRecordingDroppedTooShortNote)
        ..noteCommitted();
      expect(guard.consumeBlock(), isNull);
    });
  });

  group('큰 경고의 글자', () {
    test('🔴 세션 끊김 — 제목은 사유에 중립이고, 조각은 「저장했다」고 단정하지 않는다', () {
      // 이 길은 마이크 끊김뿐 아니라 45분 상한 도달·재기동한 세션의 무음도 탄다.
      final cap = armedSessionLostAlert(
        message: '고정 세션이 상한(45분)에 닿아 조각이 끊겼습니다.',
        hadOpenTake: true,
      );
      expect(cap.title, '녹음 고정이 꺼졌습니다');
      expect(cap.title, isNot(contains('마이크')));
      expect(cap.detail, startsWith('고정 세션이 상한(45분)에 닿아 조각이 끊겼습니다.'));
      // 저장은 이 경고 **뒤에** 돈다 — 「너무 짧음」이나 실패로 끝날 수 있다.
      expect(cap.detail, contains('저장하는 중입니다'));
      expect(cap.detail, isNot(contains('저장했습니다')));
      expect(cap.detail, contains('Alt+R'));
    });

    test('세션 끊김 — 열린 조각이 없었으면 조각 줄이 없다', () {
      final idle = armedSessionLostAlert(
        message: '마이크 연결이 끊겼습니다 — 종료 코드 1',
        hadOpenTake: false,
      );
      expect(idle.detail, isNot(contains('조각')));
      expect(idle.detail, contains('Alt+R'));
    });

    test('저장 실패 — 평소에는 사유와 복구 안내만', () {
      final alert = armedSaveFailedAlert(reason: '디스크가 가득 찼습니다');
      expect(alert.title, '조각을 저장하지 못했습니다');
      expect(alert.detail, startsWith('디스크가 가득 찼습니다'));
      expect(alert.detail, contains('복구됨'));
      expect(alert.detail, isNot(contains('Alt+R')));
    });

    test('🔴 끊김 뒤의 저장 실패 — 끊김 경고를 덮어도 사유와 고정 해제가 남는다', () {
      final alert = armedSaveFailedAlert(
        reason: '디스크가 가득 찼습니다',
        lostMessage: '마이크 연결이 끊겼습니다 — 종료 코드 1',
      );
      expect(alert.title, contains('녹음 고정이 꺼졌고'));
      expect(alert.detail, startsWith('마이크 연결이 끊겼습니다 — 종료 코드 1'));
      expect(alert.detail, contains('디스크가 가득 찼습니다'));
      expect(alert.detail, contains('Alt+R로 고정을 다시 켜 주세요'));
    });

    test('재생이 막혔을 때의 안내는 혼자서도 뜻이 통한다', () {
      expect(kArmedPlaybackBlockedMessage, contains('녹음도 시작하지 않았습니다'));
      expect(kArmedPlaybackBlockedMessage, contains('R'));
    });
  });
}
