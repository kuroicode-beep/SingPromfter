import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/controllers/compose_job_controller.dart';
import 'package:singpromfter_app/models/composition.dart';

ComposeJob job(String id, ComposeJobStatus status) => ComposeJob(
  id: id,
  status: status,
  request: const ComposeRequest(
    title: 't',
    mode: ComposeMode.bgm,
    durationSec: 60,
  ),
);

void main() {
  group('ComposeJobQueueLogic — 동시성 1', () {
    test('진행 중이 있으면 다음을 꺼내지 않는다', () {
      final jobs = [
        job('a', ComposeJobStatus.running),
        job('b', ComposeJobStatus.queued),
      ];
      expect(ComposeJobQueueLogic.nextRunnable(jobs), isNull);
    });

    test('대기 중 첫 작업을 꺼낸다', () {
      final jobs = [
        job('a', ComposeJobStatus.done),
        job('b', ComposeJobStatus.queued),
        job('c', ComposeJobStatus.queued),
      ];
      expect(ComposeJobQueueLogic.nextRunnable(jobs)?.id, 'b');
    });

    test('대기가 없으면 null', () {
      expect(
        ComposeJobQueueLogic.nextRunnable([job('a', ComposeJobStatus.done)]),
        isNull,
      );
    });

    test('replace는 같은 id만 바꾼다', () {
      final jobs = [
        job('a', ComposeJobStatus.queued),
        job('b', ComposeJobStatus.queued),
      ];
      final replaced = ComposeJobQueueLogic.replace(
        jobs,
        job('b', ComposeJobStatus.running),
      );
      expect(replaced[0].status, ComposeJobStatus.queued);
      expect(replaced[1].status, ComposeJobStatus.running);
    });

    test('clearFinished는 끝난 작업만 지운다', () {
      final jobs = [
        job('a', ComposeJobStatus.done),
        job('b', ComposeJobStatus.failed),
        job('c', ComposeJobStatus.cancelled),
        job('d', ComposeJobStatus.running),
        job('e', ComposeJobStatus.queued),
      ];
      final remaining = ComposeJobQueueLogic.clearFinished(jobs);
      expect(remaining.map((j) => j.id), ['d', 'e']);
    });
  });

  group('ComposeJobStatus 라벨', () {
    test('색이 아닌 글자로 상태를 전달한다', () {
      expect(ComposeJobStatus.queued.label, '대기 중');
      expect(ComposeJobStatus.running.label, '진행 중');
      expect(ComposeJobStatus.done.label, '완료');
      expect(ComposeJobStatus.failed.label, '실패');
      expect(ComposeJobStatus.cancelled.label, '취소됨');
    });

    test('isFinished 판정', () {
      expect(ComposeJobStatus.done.isFinished, isTrue);
      expect(ComposeJobStatus.failed.isFinished, isTrue);
      expect(ComposeJobStatus.cancelled.isFinished, isTrue);
      expect(ComposeJobStatus.running.isFinished, isFalse);
      expect(ComposeJobStatus.queued.isFinished, isFalse);
    });
  });

  group('ComposeRequest', () {
    test('effectivePrompt — 다듬은 영문 우선', () {
      const r = ComposeRequest(
        title: 't',
        mode: ComposeMode.vocal,
        durationSec: 210,
        stylePromptKo: '잔잔한 발라드',
        stylePromptEn: 'calm ballad',
      );
      expect(r.effectivePrompt, 'calm ballad');
      const raw = ComposeRequest(
        title: 't',
        mode: ComposeMode.vocal,
        durationSec: 210,
        stylePromptKo: '잔잔한 발라드',
      );
      expect(raw.effectivePrompt, '잔잔한 발라드');
    });
  });
}
