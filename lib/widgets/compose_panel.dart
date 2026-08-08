// file: lib/widgets/compose_panel.dart
//
// 작곡 탭 — 생성 폼(BGM/보컬곡) + 진행 스트립 + 생성 목록.
// 보컬곡은 8774 게이트웨이(잡 폴링, 서버 detail 실표시), BGM은 8766(블로킹,
// 경과 타이머)이라 진행 표시가 다르다. 상태는 색이 아니라 글자로 전달한다.
import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../controllers/compose_job_controller.dart';
import '../models/composition.dart';
import '../services/bgm_compose_client.dart';
import '../theme/app_theme.dart';

/// 모드별 길이 선택지(초). 보컬곡은 게이트웨이 하드 제한이 3분부터다.
const bgmDurationChoices = [30, 60, 120, 180, 300];
const vocalDurationChoices = [180, 240, 300, 420, 600];

/// 보컬 타입 선택지 — 게이트웨이 계약값과 한국어 라벨.
const vocalTypeChoices = [
  ('', '지정 안 함'),
  ('female', '여성'),
  ('male', '남성'),
  ('duet', '듀엣'),
  ('choir', '합창'),
];

String formatDurationChoice(int seconds) {
  if (seconds < 60) return '$seconds초';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return s == 0 ? '$m분' : '$m분 $s초';
}

class ComposePanel extends StatefulWidget {
  final String composeStatusLabel;
  final String bgmStatusLabel;
  final List<ComposeJob> jobs;
  final List<Composition> compositions;
  final String? playingCompositionId;

  /// 다듬기 — 성공 시 영어 프롬프트, 실패 시 null(스낵바는 화면이 띄운다).
  final Future<String?> Function(String koreanPrompt) onPolishPrompt;

  /// 가사 구조 태깅 — 성공 시 태그가 붙은 가사, 실패 시 null.
  final Future<String?> Function(String lyrics) onTagLyrics;

  final void Function(ComposeRequest request) onGenerate;
  final void Function(ComposeRequest request, int count) onGenerateVariations;
  final ValueChanged<String> onCancelJob;
  final ValueChanged<String> onRetryJob;
  final VoidCallback onClearFinishedJobs;

  final ValueChanged<Composition> onPlay;
  final ValueChanged<Composition> onStopPlay;
  final void Function(Composition item, String newTitle) onRename;
  final void Function(Composition item, {bool karaokeSet}) onRegister;
  final ValueChanged<Composition> onAttachToSong;
  final ValueChanged<Composition> onExport;
  final ValueChanged<Composition> onDelete;

  /// BGM 프리셋(8766 /presets). 고급 섹션에서 지연 로드한다.
  final Future<List<BgmPreset>> Function() presetsLoader;

  const ComposePanel({
    super.key,
    required this.composeStatusLabel,
    required this.bgmStatusLabel,
    required this.jobs,
    required this.compositions,
    required this.playingCompositionId,
    required this.onPolishPrompt,
    required this.onTagLyrics,
    required this.onGenerate,
    required this.onGenerateVariations,
    required this.onCancelJob,
    required this.onRetryJob,
    required this.onClearFinishedJobs,
    required this.onPlay,
    required this.onStopPlay,
    required this.onRename,
    required this.onRegister,
    required this.onAttachToSong,
    required this.onExport,
    required this.onDelete,
    required this.presetsLoader,
  });

  @override
  State<ComposePanel> createState() => _ComposePanelState();
}

class _ComposePanelState extends State<ComposePanel> {
  final _titleController = TextEditingController();
  final _promptController = TextEditingController();
  final _polishedController = TextEditingController();
  final _lyricsController = TextEditingController();
  final _genreController = TextEditingController();
  final _bpmController = TextEditingController();
  final _seedController = TextEditingController(text: '-1');

  ComposeMode _mode = ComposeMode.bgm;
  int _durationSec = bgmDurationChoices[1];
  String _vocalType = '';
  String _preset = '';
  String _modelSize = 'medium';
  bool _polishing = false;
  bool _tagging = false;
  List<BgmPreset> _presets = const [];
  bool _presetsLoaded = false;

  // BGM 잡의 경과 표시용 — 진행 중 잡이 있을 때만 1초 틱.
  Timer? _elapsedTimer;

  @override
  void didUpdateWidget(covariant ComposePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncElapsedTimer();
  }

  @override
  void initState() {
    super.initState();
    _syncElapsedTimer();
  }

  void _syncElapsedTimer() {
    final hasRunning =
        widget.jobs.any((j) => j.status == ComposeJobStatus.running);
    if (hasRunning && _elapsedTimer == null) {
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!hasRunning && _elapsedTimer != null) {
      _elapsedTimer?.cancel();
      _elapsedTimer = null;
    }
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _titleController.dispose();
    _promptController.dispose();
    _polishedController.dispose();
    _lyricsController.dispose();
    _genreController.dispose();
    _bpmController.dispose();
    _seedController.dispose();
    super.dispose();
  }

  ComposeRequest _buildRequest() {
    return ComposeRequest(
      title: _titleController.text.trim(),
      mode: _mode,
      stylePromptKo: _promptController.text.trim(),
      stylePromptEn: _polishedController.text.trim(),
      lyrics: _mode == ComposeMode.vocal ? _lyricsController.text.trim() : '',
      vocalType: _mode == ComposeMode.vocal ? _vocalType : '',
      genre: _mode == ComposeMode.vocal ? _genreController.text.trim() : '',
      bpm: int.tryParse(_bpmController.text.trim()),
      durationSec: _durationSec,
      seed: int.tryParse(_seedController.text.trim()) ?? -1,
      preset: _mode == ComposeMode.bgm ? _preset : '',
      modelSize: _modelSize,
    );
  }

  Future<void> _polish() async {
    final source = _promptController.text.trim();
    if (source.isEmpty) return;
    setState(() => _polishing = true);
    final result = await widget.onPolishPrompt(source);
    if (!mounted) return;
    setState(() {
      _polishing = false;
      if (result != null) _polishedController.text = result;
    });
  }

  Future<void> _tagLyrics() async {
    final source = _lyricsController.text.trim();
    if (source.isEmpty) return;
    setState(() => _tagging = true);
    final result = await widget.onTagLyrics(source);
    if (!mounted) return;
    setState(() {
      _tagging = false;
      if (result != null) _lyricsController.text = result;
    });
  }

  Future<void> _loadPresetsOnce() async {
    if (_presetsLoaded) return;
    _presetsLoaded = true;
    final presets = await widget.presetsLoader();
    if (!mounted) return;
    setState(() => _presets = presets);
  }

  void _switchMode(ComposeMode mode) {
    setState(() {
      _mode = mode;
      final choices =
          mode == ComposeMode.bgm ? bgmDurationChoices : vocalDurationChoices;
      if (!choices.contains(_durationSec)) {
        _durationSec = choices[mode == ComposeMode.bgm ? 1 : 0];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Row(
          children: [
            Text('작곡', style: AppTypography.screenTitle),
            const Spacer(),
            _StatusChip(label: widget.composeStatusLabel),
            const SizedBox(width: 8),
            _StatusChip(label: widget.bgmStatusLabel),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'SAW의 ACE-Step 1.5 터보(보컬곡)와 MusicGen(BGM)으로 곡을 만듭니다.',
          style: AppTypography.bodyMuted,
        ),
        const SizedBox(height: 16),
        _buildForm(),
        const SizedBox(height: 16),
        ..._buildJobStrip(),
        _buildListHeader(),
        const SizedBox(height: 8),
        if (widget.compositions.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '아직 생성한 곡이 없습니다.\n위에서 프롬프트를 입력하고 생성을 시작해 보세요.',
              style: AppTypography.bodyMuted,
              textAlign: TextAlign.center,
            ),
          )
        else
          ..._buildCompositionRows(),
      ],
    );
  }

  Widget _buildForm() {
    final isVocal = _mode == ComposeMode.vocal;
    final durations =
        isVocal ? vocalDurationChoices : bgmDurationChoices;
    return Container(
      decoration: AppShapes.panel(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titleController,
            style: AppTypography.body,
            decoration: const InputDecoration(
              labelText: '제목',
              hintText: '비우면 "AI 작곡 날짜 시간"으로 저장됩니다',
            ),
          ),
          const SizedBox(height: 12),
          Text('생성 모드', style: AppTypography.bodyMuted),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text('BGM (반주만)', style: AppTypography.body),
                selected: !isVocal,
                onSelected: (_) => _switchMode(ComposeMode.bgm),
              ),
              ChoiceChip(
                label: Text('보컬곡 (가사 포함)', style: AppTypography.body),
                selected: isVocal,
                onSelected: (_) => _switchMode(ComposeMode.vocal),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _promptController,
            style: AppTypography.body,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '스타일 프롬프트',
              hintText: '예: 잔잔한 발라드, 피아노와 현악, 느린 템포 — 한국어로 적으면 AI가 다듬어 줍니다',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                height: AppConstants.minTouchTarget,
                child: OutlinedButton.icon(
                  onPressed: _polishing ? null : _polish,
                  icon: _polishing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_fix_high),
                  label: Text(_polishing ? '다듬는 중...' : 'AI 다듬기'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '다듬은 결과는 아래 칸에 채워지고, 직접 고칠 수 있습니다.',
                  style: AppTypography.bodyMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _polishedController,
            style: AppTypography.body,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '다듬은 프롬프트 (영문, 비우면 원문으로 생성)',
            ),
          ),
          if (isVocal) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _lyricsController,
              style: AppTypography.body,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: '가사 (한국어 그대로)',
                hintText: '[verse]/[chorus] 구조 태그는 아래 버튼으로 자동으로 붙일 수 있습니다',
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: AppConstants.minTouchTarget,
              child: OutlinedButton.icon(
                onPressed: _tagging ? null : _tagLyrics,
                icon: _tagging
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.format_list_bulleted),
                label: Text(_tagging ? '태그 붙이는 중...' : '가사 구조 태그 자동 붙이기'),
              ),
            ),
            const SizedBox(height: 12),
            Text('보컬 타입', style: AppTypography.bodyMuted),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: vocalTypeChoices.map((choice) {
                final (value, label) = choice;
                return ChoiceChip(
                  label: Text(label, style: AppTypography.body),
                  selected: _vocalType == value,
                  onSelected: (_) => setState(() => _vocalType = value),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _genreController,
                    style: AppTypography.body,
                    decoration: const InputDecoration(
                      labelText: '장르 태그 (선택, 영문 권장)',
                      hintText: '예: k-ballad, acoustic',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _bpmController,
                    style: AppTypography.body,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'BPM (선택)',
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text('길이', style: AppTypography.bodyMuted),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: durations.map((seconds) {
              return ChoiceChip(
                label: Text(
                  formatDurationChoice(seconds),
                  style: AppTypography.body,
                ),
                selected: _durationSec == seconds,
                onSelected: (_) => setState(() => _durationSec = seconds),
              );
            }).toList(growable: false),
          ),
          if (isVocal)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '보컬곡은 3분(180초)부터 만들 수 있습니다. 짧은 곡은 BGM 모드를 써 주세요.',
                style: AppTypography.bodyMuted,
              ),
            ),
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text('고급', style: AppTypography.body),
              iconColor: AppColors.primary,
              collapsedIconColor: AppColors.onSurfaceVariant,
              onExpansionChanged: (open) {
                if (open && !isVocal) unawaited(_loadPresetsOnce());
              },
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: _seedController,
                        style: AppTypography.body,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'seed (-1=랜덤)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (!isVocal) ...[
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _preset.isEmpty ? null : _preset,
                          hint: Text('프리셋 (선택)', style: AppTypography.bodyMuted),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('프리셋 없음'),
                            ),
                            ..._presets.map(
                              (p) => DropdownMenuItem(
                                value: p.name,
                                child: Text(
                                  p.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) => setState(() {
                            _preset = value ?? '';
                            // 프리셋 추천 길이를 자동 반영한다(수동 변경 가능).
                            final preset = _presets
                                .where((p) => p.name == _preset)
                                .toList();
                            final rec = preset.isEmpty
                                ? null
                                : preset.first.recommendedDuration?.round();
                            if (rec != null) {
                              var closest = bgmDurationChoices.first;
                              for (final c in bgmDurationChoices) {
                                if ((c - rec).abs() < (closest - rec).abs()) {
                                  closest = c;
                                }
                              }
                              _durationSec = closest;
                            }
                          }),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 140,
                        child: DropdownButtonFormField<String>(
                          initialValue: _modelSize,
                          items: const [
                            DropdownMenuItem(
                              value: 'small',
                              child: Text('빠름 (small)'),
                            ),
                            DropdownMenuItem(
                              value: 'medium',
                              child: Text('표준 (medium)'),
                            ),
                            DropdownMenuItem(
                              value: 'large',
                              child: Text('정밀 (large)'),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _modelSize = value ?? 'medium'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => widget.onGenerate(_buildRequest()),
                icon: const Icon(Icons.play_circle_fill),
                label: const Text('생성 시작'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryContainer,
                  foregroundColor: AppColors.onPrimaryContainer,
                  minimumSize: const Size(140, AppConstants.minTouchTarget),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    widget.onGenerateVariations(_buildRequest(), 3),
                icon: const Icon(Icons.shuffle),
                label: const Text('변주 3개 생성'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(140, AppConstants.minTouchTarget),
                  side: const BorderSide(
                    color: AppColors.borderStrong,
                    width: 2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildJobStrip() {
    final visible = widget.jobs
        .where((j) => !j.status.isFinished || j.status == ComposeJobStatus.failed)
        .toList();
    if (visible.isEmpty) return const [];
    return [
      ...visible.map((job) => _JobRow(
            job: job,
            onCancel: () => widget.onCancelJob(job.id),
            onRetry: () => widget.onRetryJob(job.id),
          )),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: widget.onClearFinishedJobs,
          child: const Text('끝난 작업 지우기'),
        ),
      ),
      const SizedBox(height: 8),
    ];
  }

  Widget _buildListHeader() {
    return Row(
      children: [
        Text('생성된 곡', style: AppTypography.listTitle),
        const Spacer(),
        Text('${widget.compositions.length}개', style: AppTypography.monoMuted),
      ],
    );
  }

  List<Widget> _buildCompositionRows() {
    final rows = <Widget>[];
    String? lastBatch;
    for (final item in widget.compositions) {
      if (item.batchId != null && item.batchId != lastBatch) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              '변주 묶음 ${item.batchId!.substring(0, 8)}',
              style: AppTypography.monoMuted,
            ),
          ),
        );
      }
      lastBatch = item.batchId;
      rows.add(
        _CompositionRow(
          item: item,
          playing: widget.playingCompositionId == item.id,
          onPlay: () => widget.onPlay(item),
          onStopPlay: () => widget.onStopPlay(item),
          onRename: () => _showRenameDialog(item),
          onRegister: () => _showRegisterDialog(item),
          onAttachToSong: () => widget.onAttachToSong(item),
          onExport: () => widget.onExport(item),
          onDelete: () => widget.onDelete(item),
        ),
      );
      rows.add(const Divider(height: 1, thickness: 1));
    }
    return rows;
  }

  Future<void> _showRenameDialog(Composition item) async {
    final controller = TextEditingController(text: item.title);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이름 바꾸기'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppTypography.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved != null && saved.isNotEmpty) {
      widget.onRename(item, saved);
    }
  }

  Future<void> _showRegisterDialog(Composition item) async {
    var karaokeSet = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('곡으로 등록'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"${item.title}"을(를) 곡 목록에 등록합니다.',
                style: AppTypography.body,
              ),
              if (item.mode == ComposeMode.vocal) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: karaokeSet,
                  onChanged: (v) =>
                      setDialogState(() => karaokeSet = v ?? false),
                  title: Text(
                    '노래방 세트 만들기',
                    style: AppTypography.body,
                  ),
                  subtitle: Text(
                    'AI 분리로 MR(슬롯2)을 만들고 가사 싱크까지 맞춥니다 (수십 초 추가)',
                    style: AppTypography.bodyMuted,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('등록'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      widget.onRegister(item, karaokeSet: karaokeSet);
    }
  }
}

class _StatusChip extends StatelessWidget {
  final String label;

  const _StatusChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: AppShapes.controlRadius,
        border: Border.all(color: AppColors.outline),
      ),
      child: Text(label, style: AppTypography.bodyMuted),
    );
  }
}

class _JobRow extends StatelessWidget {
  final ComposeJob job;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  const _JobRow({
    required this.job,
    required this.onCancel,
    required this.onRetry,
  });

  String _elapsedText() {
    final started = job.startedAt;
    if (started == null) return '';
    final elapsed = DateTime.now().difference(started);
    final mm = elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '경과 $mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final running = job.status == ComposeJobStatus.running;
    final failed = job.status == ComposeJobStatus.failed;
    final detail = job.statusDetail ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: AppShapes.panel(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${job.displayName} · ${job.request.mode.label}',
                  style: AppTypography.body,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(job.status.label, style: AppTypography.emphasis),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (detail.isNotEmpty) detail,
              if (running && !detail.contains('경과')) _elapsedText(),
            ].join(' · '),
            style: AppTypography.bodyMuted,
          ),
          if (running) ...[
            const SizedBox(height: 8),
            const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(4)),
              child: LinearProgressIndicator(minHeight: 6),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(88, AppConstants.minTouchTarget),
                    side: const BorderSide(
                      color: AppColors.borderStrong,
                      width: 2,
                    ),
                  ),
                  child: const Text('취소'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '취소해도 서버 작업은 계속될 수 있습니다.',
                    style: AppTypography.bodyMuted,
                  ),
                ),
              ],
            ),
          ],
          if (failed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 시도'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(110, AppConstants.minTouchTarget),
                  side: const BorderSide(
                    color: AppColors.borderStrong,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CompositionRow extends StatelessWidget {
  final Composition item;
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback onStopPlay;
  final VoidCallback onRename;
  final VoidCallback onRegister;
  final VoidCallback onAttachToSong;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  const _CompositionRow({
    required this.item,
    required this.playing,
    required this.onPlay,
    required this.onStopPlay,
    required this.onRename,
    required this.onRegister,
    required this.onAttachToSong,
    required this.onExport,
    required this.onDelete,
  });

  static String _formatDate(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final meta =
        '${item.mode.label} · ${formatDurationChoice(item.durationSec)} · '
        'seed ${item.seed}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: AppTypography.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (item.isRegistered)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('등록됨', style: AppTypography.emphasis),
                ),
              Text(_formatDate(item.createdAt), style: AppTypography.monoMuted),
            ],
          ),
          const SizedBox(height: 4),
          Text(meta, style: AppTypography.monoMuted),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: playing ? onStopPlay : onPlay,
                icon: Icon(playing ? Icons.stop : Icons.play_arrow),
                label: Text(playing ? '정지' : '듣기'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(96, AppConstants.minTouchTarget),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onRename,
                icon: const Icon(Icons.edit),
                label: const Text('이름 바꾸기'),
                style: _outlineStyle(110),
              ),
              if (!item.isRegistered)
                OutlinedButton.icon(
                  onPressed: onRegister,
                  icon: const Icon(Icons.library_add),
                  label: const Text('곡으로 등록'),
                  style: _outlineStyle(120),
                ),
              OutlinedButton.icon(
                onPressed: onAttachToSong,
                icon: const Icon(Icons.playlist_add),
                label: const Text('기존 곡에 반주로'),
                style: _outlineStyle(140),
              ),
              OutlinedButton.icon(
                onPressed: onExport,
                icon: const Icon(Icons.drive_file_move_outline),
                label: const Text('내보내기'),
                style: _outlineStyle(110),
              ),
              OutlinedButton(
                onPressed: onDelete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  minimumSize: const Size(80, AppConstants.minTouchTarget),
                  side: const BorderSide(color: AppColors.danger, width: 2),
                ),
                child: const Text('삭제'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static ButtonStyle _outlineStyle(double width) => OutlinedButton.styleFrom(
    minimumSize: Size(width, AppConstants.minTouchTarget),
    side: const BorderSide(color: AppColors.borderStrong, width: 2),
  );
}
