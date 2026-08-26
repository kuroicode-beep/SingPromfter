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

/// 프롬프트 권장 최대 길이. ACE-Step 텍스트 인코더가 앞부분 위주로
/// 반영하므로 이보다 길면 뒷부분이 무시될 수 있다 — 차단하지 않고 경고만.
const promptMaxChars = 300;

/// 가사 권장 최대 길이(구조 태그 포함). 10분 곡 기준 현실 상한.
const lyricsMaxChars = 2000;

/// 검증된 코드진행 별칭 — 게이트웨이 KNOWN_PROGRESSIONS 와 같은 값.
/// 보컬곡은 코드진행이 필수다(고정 제작 포맷, 2026-08-25) — 코드 락이
/// 반주 음이탈을 막는 핵심 장치라 비우고 생성할 수 없다.
const chordPresetChoices = [
  ('ballad4536', '왕도진행 (발라드)'),
  ('kballad2165', '감성 발라드'),
  ('minor6415', '단조 발라드'),
  ('kpop1465', 'K-pop 몽환'),
  ('pop1645', '팝 스탠다드'),
  ('canon', '캐논'),
  ('royal', '로열로드'),
];

/// 템포 느낌 선택지 — 조합 프롬프트에 들어갈 한국어 표현.
const tempoFeelChoices = [
  ('', '지정 안 함'),
  ('slow', '느리게'),
  ('medium', '보통'),
  ('fast', '빠르게'),
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
  final _instrumentsController = TextEditingController();
  final _chordsController = TextEditingController();
  final _bpmController = TextEditingController();
  final _seedController = TextEditingController(text: '-1');

  ComposeMode _mode = ComposeMode.bgm;
  int _durationSec = bgmDurationChoices[1];
  String _vocalType = 'female'; // 기본 여성 (2026-08-26 청취 판정)
  // 전속 가수 참조 — 2026-08-26 보류(기본 꺼짐): 참조 전사가 보컬 드리프트 용의자.
  bool _useSinger = false;
  String _tempoFeel = '';
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
    _instrumentsController.dispose();
    _chordsController.dispose();
    _bpmController.dispose();
    _seedController.dispose();
    super.dispose();
  }

  ComposeRequest _buildRequest() {
    return ComposeRequest(
      title: _titleController.text.trim(),
      mode: _mode,
      stylePromptKo: _assembledPrompt(),
      stylePromptEn: _polishedController.text.trim(),
      lyrics: _mode == ComposeMode.vocal ? _lyricsController.text.trim() : '',
      vocalType: _mode == ComposeMode.vocal ? _vocalType : '',
      genre: _mode == ComposeMode.vocal ? _genreController.text.trim() : '',
      chords: _mode == ComposeMode.vocal ? _chordsController.text.trim() : '',
      singer: _mode == ComposeMode.vocal && _useSinger ? 'auto' : 'off',
      bpm: int.tryParse(_bpmController.text.trim()),
      durationSec: _durationSec,
      seed: int.tryParse(_seedController.text.trim()) ?? -1,
      preset: _mode == ComposeMode.bgm ? _preset : '',
      modelSize: _modelSize,
    );
  }

  /// 구조화 입력(장르·보컬·악기·템포·코드·기타)을 하나의 프롬프트로 조합한다.
  /// 우측 미리보기와 다듬기·생성이 전부 이 문자열을 쓴다 — 조립 경로는 하나다.
  String _assembledPrompt() {
    final parts = <String>[];
    final genre = _genreController.text.trim();
    if (genre.isNotEmpty) parts.add(genre);
    if (_mode == ComposeMode.vocal && _vocalType.isNotEmpty) {
      parts.add(switch (_vocalType) {
        'female' => '여성 보컬',
        'male' => '남성 보컬',
        'duet' => '남녀 듀엣',
        'choir' => '합창',
        _ => '',
      });
    }
    final instruments = _instrumentsController.text.trim();
    if (instruments.isNotEmpty) parts.add(instruments);
    final tempoWord = switch (_tempoFeel) {
      'slow' => '느린 템포',
      'medium' => '보통 템포',
      'fast' => '빠른 템포',
      _ => '',
    };
    if (tempoWord.isNotEmpty) parts.add(tempoWord);
    final bpm = _bpmController.text.trim();
    if (bpm.isNotEmpty) parts.add('${bpm}BPM');
    final chords = _chordsController.text.trim();
    if (chords.isNotEmpty) parts.add('코드진행 $chords');
    final extra = _promptController.text.trim();
    if (extra.isNotEmpty) parts.add(extra);
    return parts.where((p) => p.isNotEmpty).join(', ');
  }

  /// 가사 커서 위치에 구조 태그 한 줄을 끼워 넣는다.
  void _insertLyricsTag(String tag) {
    final c = _lyricsController;
    final text = c.text;
    final sel = c.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final needsNewlineBefore = start > 0 && text[start - 1] != '\n';
    final insert = '${needsNewlineBefore ? '\n' : ''}$tag\n';
    c.value = TextEditingValue(
      text: text.replaceRange(start, end, insert),
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
    setState(() {});
  }

  Future<void> _polish() async {
    final source = _assembledPrompt();
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
          'SAW의 ACE-Step 1.5 XL(보컬곡)과 MusicGen(BGM)으로 곡을 만듭니다. '
          '보컬곡은 음역·화성 관문과 금지 스타일 차단이 서버에서 자동 적용됩니다.',
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 넓으면 좌측 입력 + 우측 전체 프롬프트 미리보기 2열.
          final wide = constraints.maxWidth >= 860;
          final fields = _buildFormFields(isVocal, durations);
          final preview = _buildPromptPreview();
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: fields,
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(width: 350, child: preview),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [...fields, const SizedBox(height: 16), preview],
          );
        },
      ),
    );
  }

  List<Widget> _buildFormFields(bool isVocal, List<int> durations) {
    return [
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
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _genreController,
              style: AppTypography.body,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '장르',
                hintText: '예: 발라드, k-pop, 재즈',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _instrumentsController,
              style: AppTypography.body,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '악기',
                hintText: '예: 피아노, 현악, 어쿠스틱 기타',
              ),
            ),
          ),
        ],
      ),
      if (isVocal) ...[
        const SizedBox(height: 12),
        Text('보컬색', style: AppTypography.bodyMuted),
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
        const SizedBox(height: 8),
        // 전속 가수 참조 — SVIL 고정 남/녀 목소리(reference_audio)를 서버가 자동 첨부.
        // 색 있는 패널 컨테이너 안이라 잉크 표면을 따로 깔아야 한다.
        Material(
          type: MaterialType.transparency,
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _useSinger,
            onChanged: (v) => setState(() => _useSinger = v ?? false),
            title: Text('전속 가수 목소리 사용', style: AppTypography.body),
            subtitle: Text(
              '곡마다 같은 남/녀 가수 목소리로 부릅니다 (보컬색 따라 자동 선택)',
              style: AppTypography.bodyMuted,
            ),
          ),
        ),
      ],
      const SizedBox(height: 12),
      Text('템포', style: AppTypography.bodyMuted),
      const SizedBox(height: 6),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tempoFeelChoices.map((choice) {
                final (value, label) = choice;
                return ChoiceChip(
                  label: Text(label, style: AppTypography.body),
                  selected: _tempoFeel == value,
                  onSelected: (_) => setState(() => _tempoFeel = value),
                );
              }).toList(growable: false),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: TextField(
              controller: _bpmController,
              style: AppTypography.body,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'BPM (선택)'),
            ),
          ),
        ],
      ),
      if (isVocal) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _lyricsController,
          style: AppTypography.body,
          minLines: 4,
          maxLines: 10,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: '가사 (한국어 그대로)',
            hintText: '[verse]/[chorus] 구조 태그는 아래 버튼으로 붙일 수 있습니다',
            counterText:
                '${_lyricsController.text.length}/$lyricsMaxChars자',
            counterStyle: _lyricsController.text.length > lyricsMaxChars
                ? AppTypography.bodyMuted.copyWith(color: AppColors.danger)
                : AppTypography.bodyMuted,
          ),
        ),
        if (_lyricsController.text.length > lyricsMaxChars)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '가사가 깁니다 — $lyricsMaxChars자 이내를 권장합니다. '
              '너무 길면 생성이 실패하거나 뒷부분이 잘릴 수 있습니다.',
              style: AppTypography.body.copyWith(color: AppColors.danger),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in ['[verse]', '[chorus]', '[bridge]'])
              SizedBox(
                height: AppConstants.minTouchTarget,
                child: OutlinedButton(
                  onPressed: () => _insertLyricsTag(tag),
                  child: Text('$tag 넣기'),
                ),
              ),
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
                label: Text(_tagging ? '태그 붙이는 중...' : 'AI 구조 태그'),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: _chordsController,
        style: AppTypography.body,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: isVocal ? '코드진행 (보컬곡 필수)' : '코드진행 (선택)',
          hintText: '예: C - G - Am - F, 또는 아래 검증된 진행 선택',
        ),
      ),
      if (isVocal) ...[
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: chordPresetChoices.map((choice) {
            final (alias, label) = choice;
            return ChoiceChip(
              label: Text(label, style: AppTypography.body),
              selected: _chordsController.text.trim() == alias,
              onSelected: (_) => setState(() {
                _chordsController.text = alias;
              }),
            );
          }).toList(growable: false),
        ),
        if (_chordsController.text.trim().isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '보컬곡은 코드진행이 필수입니다 — 코드 락이 반주 음이탈을 막습니다. '
              '위에서 하나를 고르거나 직접 입력해 주세요.',
              style: AppTypography.body.copyWith(color: AppColors.danger),
            ),
          ),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: _promptController,
        style: AppTypography.body,
        minLines: 2,
        maxLines: 4,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: '기타 (자유 서술)',
          hintText: '예: 새벽 감성, 비 오는 날, 후렴에서 웅장하게',
        ),
      ),
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
        // 색 있는 패널 컨테이너 안이라 잉크 표면을 따로 깔아야 한다.
        child: Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          title: Text('고급', style: AppTypography.body),
          iconColor: AppColors.primary,
          collapsedIconColor: AppColors.onSurfaceVariant,
          onExpansionChanged: (open) {
            if (open && _mode == ComposeMode.bgm) {
              unawaited(_loadPresetsOnce());
            }
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
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          // 보컬곡은 코드진행 없이는 생성 불가 (고정 제작 포맷) — 버튼을 잠근다.
          FilledButton.icon(
            onPressed:
                isVocal && _chordsController.text.trim().isEmpty
                    ? null
                    : () => widget.onGenerate(_buildRequest()),
            icon: const Icon(Icons.play_circle_fill),
            label: const Text('생성 시작'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryContainer,
              foregroundColor: AppColors.onPrimaryContainer,
              minimumSize: const Size(140, AppConstants.minTouchTarget),
            ),
          ),
          OutlinedButton.icon(
            onPressed:
                isVocal && _chordsController.text.trim().isEmpty
                    ? null
                    : () => widget.onGenerateVariations(_buildRequest(), 3),
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
    ];
  }

  /// 우측 미리보기 — 조합된 전체 프롬프트와 다듬은 영문, 길이 카운터/경고.
  Widget _buildPromptPreview() {
    final assembled = _assembledPrompt();
    final assembledOver = assembled.length > promptMaxChars;
    final polishedLen = _polishedController.text.length;
    final polishedOver = polishedLen > promptMaxChars;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('전체 프롬프트', style: AppTypography.listTitle),
              ),
              Text(
                '${assembled.length}/$promptMaxChars자',
                style: assembledOver
                    ? AppTypography.mono.copyWith(color: AppColors.danger)
                    : AppTypography.monoMuted,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '왼쪽 입력을 조합한 원문입니다. 이 내용이 다듬기·생성에 쓰입니다.',
            style: AppTypography.bodyMuted,
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.outline),
            ),
            child: SelectableText(
              assembled.isEmpty ? '아직 입력이 없습니다' : assembled,
              style: assembled.isEmpty
                  ? AppTypography.bodyMuted
                  : AppTypography.body,
            ),
          ),
          if (assembledOver)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '프롬프트가 깁니다 — $promptMaxChars자 이내를 권장합니다. '
                '너무 길면 뒷부분이 생성에 반영되지 않을 수 있습니다.',
                style: AppTypography.body.copyWith(color: AppColors.danger),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
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
              label: Text(_polishing ? '다듬는 중...' : 'AI 다듬기 (영문 변환)'),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _polishedController,
            style: AppTypography.body,
            minLines: 3,
            maxLines: 8,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '다듬은 프롬프트 (영문, 비우면 원문으로 생성)',
              counterText: '$polishedLen/$promptMaxChars자',
              counterStyle: polishedOver
                  ? AppTypography.bodyMuted.copyWith(color: AppColors.danger)
                  : AppTypography.bodyMuted,
            ),
          ),
          if (polishedOver)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '다듬은 프롬프트가 $promptMaxChars자를 넘습니다 — 뒷부분이 '
                '생성에 반영되지 않을 수 있으니 줄여 주세요.',
                style: AppTypography.body.copyWith(color: AppColors.danger),
              ),
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
