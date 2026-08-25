// file: lib/controllers/compose_job_controller.dart
//
// 작곡 작업 큐. ImportJobController와 같은 구조지만 필드가 전혀 달라
// 재사용하지 않고 미러로 둔다. 동시 실행 1건 — 생성 서버가 블로킹이고
// GPU 하나를 분리 서버와 나눠 쓴다(순번은 게이트웨이 VRAM lease가 처리).
import 'package:flutter/foundation.dart';

import '../models/composition.dart';

enum ComposeJobStatus { queued, running, done, failed, cancelled }

extension ComposeJobStatusInfo on ComposeJobStatus {
  /// 색만으로 상태를 구분하지 않도록 항상 텍스트 라벨을 함께 쓴다.
  String get label => switch (this) {
    ComposeJobStatus.queued => '대기 중',
    ComposeJobStatus.running => '진행 중',
    ComposeJobStatus.done => '완료',
    ComposeJobStatus.failed => '실패',
    ComposeJobStatus.cancelled => '취소됨',
  };

  bool get isFinished =>
      this == ComposeJobStatus.done ||
      this == ComposeJobStatus.failed ||
      this == ComposeJobStatus.cancelled;
}

/// 생성 요청 스냅샷 — 재시도 시 재입력이 필요 없도록 잡에 전부 담는다.
@immutable
class ComposeRequest {
  final String title;
  final ComposeMode mode;
  final String stylePromptKo;
  final String stylePromptEn;
  final String lyrics;
  final String vocalType; // female | male | duet | choir | ''
  final String genre;
  // 코드 진행 — 게이트웨이가 캡션 맨 앞에 락으로 박는다(반주 음이탈 대책, 2026-08-24).
  // 프롬프트 문장에 접는 것과 별개로 필드로도 보내야 락이 확정 발동한다.
  final String chords;
  // 전속 가수 참조 — 'auto'(보컬 성별 따라 자동, 기본) | 'off'. (2026-08-25 워크플로우)
  final String singer;
  final int? bpm;
  final int durationSec;
  final int seed;
  final String preset; // BGM 전용
  final String modelSize; // BGM 전용
  final String? batchId; // seed 변주 묶음

  const ComposeRequest({
    required this.title,
    required this.mode,
    this.stylePromptKo = '',
    this.stylePromptEn = '',
    this.lyrics = '',
    this.vocalType = '',
    this.genre = '',
    this.chords = '',
    this.singer = 'auto',
    this.bpm,
    required this.durationSec,
    this.seed = -1,
    this.preset = '',
    this.modelSize = 'medium',
    this.batchId,
  });

  /// 생성에 실제로 보낼 프롬프트 — 다듬은 영문이 있으면 그것, 없으면 원문.
  String get effectivePrompt =>
      stylePromptEn.trim().isNotEmpty ? stylePromptEn.trim() : stylePromptKo.trim();

  /// 변주 생성용 — 같은 요청에 제목·seed·묶음 id만 바꾼다.
  ComposeRequest copyWith({String? title, int? seed, String? batchId}) {
    return ComposeRequest(
      title: title ?? this.title,
      mode: mode,
      stylePromptKo: stylePromptKo,
      stylePromptEn: stylePromptEn,
      lyrics: lyrics,
      vocalType: vocalType,
      genre: genre,
      chords: chords,
      singer: singer,
      bpm: bpm,
      durationSec: durationSec,
      seed: seed ?? this.seed,
      preset: preset,
      modelSize: modelSize,
      batchId: batchId ?? this.batchId,
    );
  }
}

@immutable
class ComposeJob {
  final String id;
  final ComposeRequest request;
  final ComposeJobStatus status;
  final String? statusDetail;

  /// 실행 시작 시각 — 경과 시간 표시용(블로킹 API라 진행률이 없다).
  final DateTime? startedAt;

  /// 완료 시 만들어진 Composition id.
  final String? resultCompositionId;

  const ComposeJob({
    required this.id,
    required this.request,
    this.status = ComposeJobStatus.queued,
    this.statusDetail,
    this.startedAt,
    this.resultCompositionId,
  });

  ComposeJob copyWith({
    ComposeJobStatus? status,
    String? statusDetail,
    DateTime? startedAt,
    String? resultCompositionId,
    bool clearStatusDetail = false,
  }) {
    return ComposeJob(
      id: id,
      request: request,
      status: status ?? this.status,
      statusDetail:
          clearStatusDetail ? null : (statusDetail ?? this.statusDetail),
      startedAt: startedAt ?? this.startedAt,
      resultCompositionId: resultCompositionId ?? this.resultCompositionId,
    );
  }

  String get displayName =>
      request.title.trim().isEmpty ? '(제목 없음)' : request.title;
}

/// 큐 조작 순수 로직. (테스트 대상 — ImportJobQueueLogic 미러)
class ComposeJobQueueLogic {
  ComposeJobQueueLogic._();

  /// 다음에 실행할 작업. 이미 진행 중이면 null — 동시성 1.
  static ComposeJob? nextRunnable(List<ComposeJob> jobs) {
    final hasRunning = jobs.any((j) => j.status == ComposeJobStatus.running);
    if (hasRunning) return null;
    for (final job in jobs) {
      if (job.status == ComposeJobStatus.queued) return job;
    }
    return null;
  }

  static List<ComposeJob> replace(List<ComposeJob> jobs, ComposeJob updated) {
    return jobs
        .map((j) => j.id == updated.id ? updated : j)
        .toList(growable: false);
  }

  static List<ComposeJob> clearFinished(List<ComposeJob> jobs) {
    return jobs.where((j) => !j.status.isFinished).toList(growable: false);
  }
}

class ComposeJobController extends ChangeNotifier {
  final List<ComposeJob> _jobs = [];
  final Map<String, void Function()> _cancels = {};

  /// 작업 1건을 실제로 수행하는 함수. 서비스 의존을 밖에서 주입한다.
  final Future<void> Function(
    ComposeJob job, {
    required void Function(String detail) onProgress,
    required void Function(void Function() cancel) onCancel,
  })
  runner;

  ComposeJobController({required this.runner});

  List<ComposeJob> get jobs => List.unmodifiable(_jobs);

  bool get hasActiveJob => _jobs.any(
    (j) =>
        j.status == ComposeJobStatus.running ||
        j.status == ComposeJobStatus.queued,
  );

  ComposeJob enqueue({required String id, required ComposeRequest request}) {
    final job = ComposeJob(id: id, request: request);
    _jobs.insert(0, job);
    notifyListeners();
    _pump();
    return job;
  }

  void update(ComposeJob job) {
    final index = _jobs.indexWhere((j) => j.id == job.id);
    if (index < 0) return;
    _jobs[index] = job;
    notifyListeners();
  }

  ComposeJob? jobById(String id) {
    for (final job in _jobs) {
      if (job.id == id) return job;
    }
    return null;
  }

  /// 취소 — 보컬곡은 폴링을 끊고, BGM은 도착할 응답을 무시한다.
  /// 서버 쪽 작업은 계속될 수 있다(UI 문구로 알린다).
  void cancel(String id) {
    _cancels[id]?.call();
    final job = jobById(id);
    if (job == null) return;
    update(
      job.copyWith(
        status: ComposeJobStatus.cancelled,
        statusDetail: '사용자가 취소했습니다. 서버 작업은 계속될 수 있습니다.',
      ),
    );
    _cancels.remove(id);
    _pump();
  }

  /// 실패/취소 작업을 같은 요청으로 다시 실행한다.
  void retry(String id) {
    final job = jobById(id);
    if (job == null) return;
    if (job.status != ComposeJobStatus.failed &&
        job.status != ComposeJobStatus.cancelled) {
      return;
    }
    update(
      job.copyWith(status: ComposeJobStatus.queued, clearStatusDetail: true),
    );
    _pump();
  }

  void clearFinished() {
    final remaining = ComposeJobQueueLogic.clearFinished(_jobs);
    _jobs
      ..clear()
      ..addAll(remaining);
    notifyListeners();
  }

  Future<void> _pump() async {
    final next = ComposeJobQueueLogic.nextRunnable(_jobs);
    if (next == null) return;

    update(
      next.copyWith(
        status: ComposeJobStatus.running,
        statusDetail: '준비 중',
        startedAt: DateTime.now(),
      ),
    );

    try {
      await runner(
        next,
        onProgress: (detail) {
          final current = jobById(next.id);
          if (current == null) return;
          if (current.status != ComposeJobStatus.running) return;
          update(current.copyWith(statusDetail: detail));
        },
        onCancel: (cancel) => _cancels[next.id] = cancel,
      );
    } catch (e) {
      final current = jobById(next.id);
      if (current != null && current.status == ComposeJobStatus.running) {
        update(
          current.copyWith(
            status: ComposeJobStatus.failed,
            statusDetail: '$e',
          ),
        );
      }
    } finally {
      _cancels.remove(next.id);
    }

    await _pump();
  }

  @override
  void dispose() {
    for (final cancel in _cancels.values) {
      cancel();
    }
    _cancels.clear();
    super.dispose();
  }
}
