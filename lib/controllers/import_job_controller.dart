// file: lib/controllers/import_job_controller.dart
//
// 가져오기 작업 큐. 동시 실행은 1건으로 제한한다 —
// 데스크톱에서 ffmpeg를 여러 개 돌리면 서로 자원을 뺏기만 한다.
import 'package:flutter/foundation.dart';

import '../models/mr_source_mode.dart';
import '../services/process/tool_progress_parsers.dart';

enum ImportJobStatus { queued, running, done, failed, cancelled }

extension ImportJobStatusInfo on ImportJobStatus {
  /// 색만으로 상태를 구분하지 않도록 항상 텍스트 라벨을 함께 쓴다.
  String get label => switch (this) {
    ImportJobStatus.queued => '대기 중',
    ImportJobStatus.running => '진행 중',
    ImportJobStatus.done => '완료',
    ImportJobStatus.failed => '실패',
    ImportJobStatus.cancelled => '취소됨',
  };

  bool get isFinished =>
      this == ImportJobStatus.done ||
      this == ImportJobStatus.failed ||
      this == ImportJobStatus.cancelled;
}

@immutable
class ImportJob {
  final String id;
  final String url;
  final MrSourceMode mode;
  final ImportJobStatus status;
  final String title;
  final double? ratio;
  final String? statusDetail;
  final String? resultAudioPath;

  /// 가사도 자동으로 찾아 붙일지.
  final bool fetchLyrics;

  /// 등록 완료된 곡 id — 완료 후 바로 선택하기 위해 들고 있는다.
  final String? songId;

  const ImportJob({
    required this.id,
    required this.url,
    required this.mode,
    this.status = ImportJobStatus.queued,
    this.title = '',
    this.ratio,
    this.statusDetail,
    this.resultAudioPath,
    this.fetchLyrics = true,
    this.songId,
  });

  ImportJob copyWith({
    ImportJobStatus? status,
    String? title,
    double? ratio,
    String? statusDetail,
    String? resultAudioPath,
    String? songId,
    bool clearRatio = false,
  }) {
    return ImportJob(
      id: id,
      url: url,
      mode: mode,
      status: status ?? this.status,
      title: title ?? this.title,
      ratio: clearRatio ? null : (ratio ?? this.ratio),
      statusDetail: statusDetail ?? this.statusDetail,
      resultAudioPath: resultAudioPath ?? this.resultAudioPath,
      fetchLyrics: fetchLyrics,
      songId: songId ?? this.songId,
    );
  }

  /// 화면에 보여줄 이름. 제목을 아직 모르면 링크를 쓴다.
  String get displayName => title.trim().isEmpty ? url : title;
}

/// 큐 조작 순수 로직. (테스트 대상)
class ImportJobQueueLogic {
  ImportJobQueueLogic._();

  /// 다음에 실행할 작업을 고른다. 이미 진행 중이면 null.
  static ImportJob? nextRunnable(List<ImportJob> jobs) {
    final hasRunning = jobs.any((j) => j.status == ImportJobStatus.running);
    if (hasRunning) return null;
    for (final job in jobs) {
      if (job.status == ImportJobStatus.queued) return job;
    }
    return null;
  }

  static List<ImportJob> replace(List<ImportJob> jobs, ImportJob updated) {
    return jobs
        .map((j) => j.id == updated.id ? updated : j)
        .toList(growable: false);
  }

  /// 끝난 작업만 걸러낸다.
  static List<ImportJob> clearFinished(List<ImportJob> jobs) {
    return jobs.where((j) => !j.status.isFinished).toList(growable: false);
  }
}

class ImportJobController extends ChangeNotifier {
  final List<ImportJob> _jobs = [];
  final Map<String, void Function()> _cancels = {};

  /// 작업 1건을 실제로 수행하는 함수. 서비스 의존을 밖에서 주입한다.
  final Future<void> Function(
    ImportJob job, {
    required void Function(JobProgress progress) onProgress,
    required void Function(void Function() cancel) onCancel,
  })
  runner;

  ImportJobController({required this.runner});

  List<ImportJob> get jobs => List.unmodifiable(_jobs);

  bool get hasActiveJob => _jobs.any(
    (j) => j.status == ImportJobStatus.running ||
        j.status == ImportJobStatus.queued,
  );

  ImportJob enqueue({
    required String url,
    required MrSourceMode mode,
    required String id,
    bool fetchLyrics = true,
  }) {
    final job = ImportJob(
      id: id,
      url: url,
      mode: mode,
      fetchLyrics: fetchLyrics,
    );
    _jobs.insert(0, job);
    notifyListeners();
    _pump();
    return job;
  }

  void update(ImportJob job) {
    final index = _jobs.indexWhere((j) => j.id == job.id);
    if (index < 0) return;
    _jobs[index] = job;
    notifyListeners();
  }

  ImportJob? jobById(String id) {
    for (final job in _jobs) {
      if (job.id == id) return job;
    }
    return null;
  }

  void cancel(String id) {
    _cancels[id]?.call();
    final job = jobById(id);
    if (job == null) return;
    update(
      job.copyWith(
        status: ImportJobStatus.cancelled,
        statusDetail: '사용자가 취소했습니다.',
        clearRatio: true,
      ),
    );
    _cancels.remove(id);
    _pump();
  }

  void clearFinished() {
    final remaining = ImportJobQueueLogic.clearFinished(_jobs);
    _jobs
      ..clear()
      ..addAll(remaining);
    notifyListeners();
  }

  Future<void> _pump() async {
    final next = ImportJobQueueLogic.nextRunnable(_jobs);
    if (next == null) return;

    update(next.copyWith(status: ImportJobStatus.running, statusDetail: '준비 중'));

    try {
      await runner(
        next,
        onProgress: (progress) {
          final current = jobById(next.id);
          if (current == null) return;
          if (current.status != ImportJobStatus.running) return;
          update(
            current.copyWith(
              ratio: progress.ratio,
              statusDetail: progress.label ?? current.statusDetail,
            ),
          );
        },
        onCancel: (cancel) => _cancels[next.id] = cancel,
      );
    } catch (e) {
      final current = jobById(next.id);
      if (current != null && current.status == ImportJobStatus.running) {
        update(
          current.copyWith(
            status: ImportJobStatus.failed,
            statusDetail: '$e',
            clearRatio: true,
          ),
        );
      }
    } finally {
      _cancels.remove(next.id);
    }

    // 남은 대기 작업을 이어서 처리한다.
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
