import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/controllers/import_job_controller.dart';
import 'package:singpromfter_app/models/mr_source_mode.dart';
import 'package:singpromfter_app/services/youtube_import_service.dart';

ImportJob job(String id, ImportJobStatus status) => ImportJob(
  id: id,
  url: 'https://youtu.be/$id',
  mode: MrSourceMode.asIs,
  status: status,
);

void main() {
  group('ImportJobQueueLogic.nextRunnable (동시 1건)', () {
    test('진행 중인 작업이 있으면 새로 시작하지 않는다', () {
      final jobs = [
        job('a', ImportJobStatus.running),
        job('b', ImportJobStatus.queued),
      ];
      expect(ImportJobQueueLogic.nextRunnable(jobs), isNull);
    });

    test('대기 중 가장 앞 작업을 고른다', () {
      final jobs = [
        job('done', ImportJobStatus.done),
        job('b', ImportJobStatus.queued),
        job('c', ImportJobStatus.queued),
      ];
      expect(ImportJobQueueLogic.nextRunnable(jobs)!.id, 'b');
    });

    test('대기 작업이 없으면 null', () {
      final jobs = [
        job('a', ImportJobStatus.done),
        job('b', ImportJobStatus.failed),
      ];
      expect(ImportJobQueueLogic.nextRunnable(jobs), isNull);
    });

    test('빈 큐는 null', () {
      expect(ImportJobQueueLogic.nextRunnable(const []), isNull);
    });
  });

  group('ImportJobQueueLogic.clearFinished', () {
    test('끝난 작업만 걸러내고 진행/대기는 남긴다', () {
      final jobs = [
        job('done', ImportJobStatus.done),
        job('run', ImportJobStatus.running),
        job('fail', ImportJobStatus.failed),
        job('wait', ImportJobStatus.queued),
        job('cancel', ImportJobStatus.cancelled),
      ];
      final remaining = ImportJobQueueLogic.clearFinished(jobs);
      expect(remaining.map((j) => j.id), ['run', 'wait']);
    });
  });

  group('ImportJobQueueLogic.replace', () {
    test('같은 id만 교체한다', () {
      final jobs = [job('a', ImportJobStatus.queued), job('b', ImportJobStatus.queued)];
      final updated = jobs.first.copyWith(status: ImportJobStatus.done);
      final result = ImportJobQueueLogic.replace(jobs, updated);
      expect(result.first.status, ImportJobStatus.done);
      expect(result.last.status, ImportJobStatus.queued);
    });
  });

  group('ImportJobStatus 라벨', () {
    test('모든 상태에 한국어 텍스트 라벨이 있다 (색만으로 구분 금지)', () {
      for (final status in ImportJobStatus.values) {
        expect(status.label, isNotEmpty);
      }
    });

    test('종료 상태를 구분한다', () {
      expect(ImportJobStatus.done.isFinished, isTrue);
      expect(ImportJobStatus.failed.isFinished, isTrue);
      expect(ImportJobStatus.cancelled.isFinished, isTrue);
      expect(ImportJobStatus.running.isFinished, isFalse);
      expect(ImportJobStatus.queued.isFinished, isFalse);
    });
  });

  group('looksLikeYoutubeUrl', () {
    test('유튜브 주소를 받아들인다', () {
      expect(looksLikeYoutubeUrl('https://www.youtube.com/watch?v=abc'), isTrue);
      expect(looksLikeYoutubeUrl('https://youtu.be/abc'), isTrue);
      expect(looksLikeYoutubeUrl('https://music.youtube.com/watch?v=abc'), isTrue);
      expect(looksLikeYoutubeUrl('  https://m.youtube.com/watch?v=abc  '), isTrue);
    });

    test('그 외 주소는 거른다', () {
      expect(looksLikeYoutubeUrl('https://vimeo.com/123'), isFalse);
      expect(looksLikeYoutubeUrl('not a url'), isFalse);
      expect(looksLikeYoutubeUrl(''), isFalse);
      expect(looksLikeYoutubeUrl('ftp://youtube.com/x'), isFalse);
      // 호스트를 사칭한 주소도 거른다
      expect(looksLikeYoutubeUrl('https://youtube.com.evil.test/x'), isFalse);
    });
  });

  _metadataTests();

  group('MrSourceMode', () {
    test('모든 방식에 라벨과 설명이 있다', () {
      for (final mode in MrSourceMode.values) {
        expect(mode.label, isNotEmpty);
        expect(mode.description, isNotEmpty);
      }
    });

    test('저장값 왕복, 알 수 없는 값은 기본값', () {
      for (final mode in MrSourceMode.values) {
        expect(MrSourceModeInfo.fromStorage(mode.storageValue), mode);
      }
      expect(MrSourceModeInfo.fromStorage('bogus'), MrSourceMode.asIs);
      expect(MrSourceModeInfo.fromStorage(null), MrSourceMode.asIs);
    });
  });
}

// yt-dlp --dump-single-json 의 실제 필드 형태를 고정해 둔다.
void _metadataTests() {
  group('YoutubeMetadata.fromJson', () {
    test('실제 yt-dlp JSON 필드를 읽는다', () {
      final meta = YoutubeMetadata.fromJson({
        'id': 'dQw4w9WgXcQ',
        'title': '  테스트 곡  ',
        'uploader': '테스트 채널',
        'duration': 213.0,
      });
      expect(meta.id, 'dQw4w9WgXcQ');
      expect(meta.title, '테스트 곡'); // 앞뒤 공백 제거
      expect(meta.uploader, '테스트 채널');
      expect(meta.duration, const Duration(seconds: 213));
    });

    test('uploader가 없으면 channel로 대체한다', () {
      final meta = YoutubeMetadata.fromJson({
        'id': 'x',
        'title': 't',
        'channel': '채널명',
        'duration': 10,
      });
      expect(meta.uploader, '채널명');
    });

    test('필드가 없어도 빈 값으로 안전하게 읽는다', () {
      final meta = YoutubeMetadata.fromJson({});
      expect(meta.id, '');
      expect(meta.title, '');
      expect(meta.duration, Duration.zero);
    });

    test('소수 duration을 반올림한다', () {
      final meta = YoutubeMetadata.fromJson({'duration': 212.7});
      expect(meta.duration, const Duration(seconds: 213));
    });
  });
}
