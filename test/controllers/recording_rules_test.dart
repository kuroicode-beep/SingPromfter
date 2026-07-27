import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/controllers/recording_controller.dart';
import 'package:singpromfter_app/models/recording_take.dart';
import 'package:singpromfter_app/services/recording_library_service.dart';

RecordingTake take({
  String id = 't1',
  String songId = 's1',
  String title = '봄날',
  String comment = '',
  int rating = 0,
  bool keep = false,
  DateTime? at,
}) {
  return RecordingTake(
    id: id,
    songId: songId,
    songTitle: title,
    fileName: '$id.wav',
    recordedAt: at ?? DateTime(2026, 7, 28, 10),
    durationMs: 60000,
    comment: comment,
    rating: rating,
    isKeep: keep,
  );
}

void main() {
  group('shouldAutoAdvance — 녹음 중 자동 진행 차단', () {
    test('녹음 중이면 다음 곡이 있어도 넘어가지 않는다', () {
      expect(
        shouldAutoAdvance(isRecording: true, queueHasNext: true),
        isFalse,
      );
    });

    test('녹음이 아니면 다음 곡이 있을 때 넘어간다', () {
      expect(
        shouldAutoAdvance(isRecording: false, queueHasNext: true),
        isTrue,
      );
    });

    test('다음 곡이 없으면 넘어가지 않는다', () {
      expect(
        shouldAutoAdvance(isRecording: false, queueHasNext: false),
        isFalse,
      );
    });
  });

  group('inputLevelLabel — 색이 아닌 말로 상태 전달', () {
    test('구간별 문구', () {
      expect(inputLevelLabel(null), '입력 확인 중');
      expect(inputLevelLabel(-60), '소리 없음');
      expect(inputLevelLabel(-35), '너무 작음');
      expect(inputLevelLabel(-15), '입력 좋음');
      expect(inputLevelLabel(-1), '너무 큼');
    });
  });

  group('normalizedLevel', () {
    test('0~1로 제한한다', () {
      expect(normalizedLevel(null), 0);
      expect(normalizedLevel(-100), 0);
      expect(normalizedLevel(0), 1);
      expect(normalizedLevel(10), 1);
      expect(normalizedLevel(-30), closeTo(0.5, 0.01));
    });
  });

  _ffmpegRecordingTests();

  group('RecordingFilter', () {
    final takes = [
      take(id: 'a', rating: 4),
      take(id: 'b', comment: '고음 불안'),
      take(id: 'c', keep: true),
      take(id: 'd', songId: 's2', title: '거리에서'),
    ];

    test('전체 모드는 다 보여준다', () {
      expect(RecordingFilter.apply(takes), hasLength(4));
    });

    test('평가함 / 코멘트 / 보관 필터', () {
      expect(
        RecordingFilter.apply(takes, mode: RecordingFilterMode.rated)
            .map((t) => t.id),
        ['a'],
      );
      expect(
        RecordingFilter.apply(takes, mode: RecordingFilterMode.commented)
            .map((t) => t.id),
        ['b'],
      );
      expect(
        RecordingFilter.apply(takes, mode: RecordingFilterMode.keep)
            .map((t) => t.id),
        ['c'],
      );
    });

    test('곡 제목으로 검색한다 (초성 포함)', () {
      expect(
        RecordingFilter.apply(takes, query: '거리').map((t) => t.id),
        ['d'],
      );
      expect(
        RecordingFilter.apply(takes, query: 'ㄱㄹㅇㅅ').map((t) => t.id),
        ['d'],
      );
    });

    test('코멘트로도 검색한다', () {
      expect(
        RecordingFilter.apply(takes, query: '고음').map((t) => t.id),
        ['b'],
      );
    });

    test('곡 id로 한정할 수 있다', () {
      expect(RecordingFilter.apply(takes, songId: 's2'), hasLength(1));
    });

    test('최근 순 정렬', () {
      final sorted = RecordingFilter.sortByNewest([
        take(id: 'old', at: DateTime(2026, 1, 1)),
        take(id: 'new', at: DateTime(2026, 7, 1)),
      ]);
      expect(sorted.first.id, 'new');
    });
  });

  group('RecordingTake JSON', () {
    test('왕복 후 값이 보존된다', () {
      final original = take(id: 'x', comment: '메모', rating: 3, keep: true);
      final restored = RecordingTake.fromJson(original.toJson());
      expect(restored.id, 'x');
      expect(restored.comment, '메모');
      expect(restored.rating, 3);
      expect(restored.isKeep, isTrue);
      expect(restored.durationMs, 60000);
    });

    test('별점은 0~5로 제한한다', () {
      expect(RecordingTake.fromJson({'rating': 99}).rating, 5);
      expect(RecordingTake.fromJson({'rating': -3}).rating, 0);
    });

    test('필드가 없어도 안전하게 읽는다', () {
      final t = RecordingTake.fromJson({});
      expect(t.durationMs, 0);
      expect(t.isRated, isFalse);
      expect(t.hasComment, isFalse);
    });
  });
}

// ffmpeg 기반 녹음의 출력 파싱 — 실제 ffmpeg 출력 형태로 고정한다.
void _ffmpegRecordingTests() {
  group('parseRmsLevel', () {
    test('astats 메타데이터에서 RMS를 읽는다', () {
      expect(
        parseRmsLevel('lavfi.astats.Overall.RMS_level=-21.091524'),
        closeTo(-21.091524, 1e-6),
      );
    });

    test('앞에 다른 내용이 붙어도 읽는다', () {
      expect(
        parseRmsLevel('[Parsed_ametadata_1 @ 0x1] '
            'lavfi.astats.Overall.RMS_level=-30.5'),
        closeTo(-30.5, 1e-6),
      );
    });

    test('무음(-inf)은 매우 낮은 값으로 처리한다', () {
      expect(parseRmsLevel('lavfi.astats.Overall.RMS_level=-inf'), -100);
    });

    test('관계없는 줄은 null', () {
      expect(parseRmsLevel('out_time_us=1000000'), isNull);
      expect(parseRmsLevel(''), isNull);
    });
  });

  group('parseDshowAudioDevices', () {
    const sample = '''
[in#0 @ 0x1] "Code의 Z Fold4 (Windows 가상 카메라)" (video)
[in#0 @ 0x1]   Alternative name "@device_pnp_x"
[in#0 @ 0x1] "마이크(RØDE NT-USB Mini)" (audio)
[in#0 @ 0x1]   Alternative name "@device_cm_y"
[in#0 @ 0x1] "MAIN L/R(BEHRINGER FLOW 8 (Streaming))" (audio)
''';

    test('오디오 장치만 뽑는다 (비디오 제외)', () {
      final devices = parseDshowAudioDevices(sample);
      expect(devices, hasLength(2));
      expect(devices.first, '마이크(RØDE NT-USB Mini)');
      expect(devices.last, 'MAIN L/R(BEHRINGER FLOW 8 (Streaming))');
    });

    test('장치가 없으면 빈 목록', () {
      expect(parseDshowAudioDevices('nothing here'), isEmpty);
    });
  });

  group('buildRecordArgs', () {
    test('장치명과 출력 경로가 들어간다', () {
      final args = buildRecordArgs(
        deviceName: '마이크(RØDE NT-USB Mini)',
        outputPath: 'C:/out.wav',
      );
      expect(args, contains('dshow'));
      expect(args, contains('audio=마이크(RØDE NT-USB Mini)'));
      expect(args.last, 'C:/out.wav');
    });

    test('레벨 출력과 진행률을 함께 켠다', () {
      final args = buildRecordArgs(deviceName: 'mic', outputPath: 'o.wav');
      final filter = args[args.indexOf('-af') + 1];
      expect(filter, contains('astats'));
      expect(filter, contains('RMS_level'));
      expect(args, containsAllInOrder(['-progress', 'pipe:1']));
    });

    test('모노 48kHz로 캡처한다', () {
      final args = buildRecordArgs(deviceName: 'mic', outputPath: 'o.wav');
      expect(args[args.indexOf('-ac') + 1], '1');
      expect(args[args.indexOf('-ar') + 1], '48000');
    });
  });
}
