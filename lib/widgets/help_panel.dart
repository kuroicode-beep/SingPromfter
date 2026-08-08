// file: lib/widgets/help_panel.dart
//
// 도움말 탭 — 단축키를 텍스트 표 + TTS 음성으로 안내한다.
// 행별 ▶ 재생과 [전체 듣기]를 제공하고, 탭을 떠나면(dispose) 낭독을 멈춘다.
// 음성은 앱에 내장된 사전 생성 클립(female_calm)만 사용한다 — 서버 무의존.
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../constants/app_shortcuts.dart';
import '../services/guide_audio_service.dart';
import '../theme/app_theme.dart';
import 'snack_message.dart';

class HelpPanel extends StatefulWidget {
  /// 테스트에서 실제 오디오 플러그인을 피하려고 주입 가능하게 둔다.
  final GuideAudio Function()? audioFactory;

  const HelpPanel({super.key, this.audioFactory});

  @override
  State<HelpPanel> createState() => _HelpPanelState();
}

class _HelpPanelState extends State<HelpPanel> {
  late final GuideAudio _audio =
      (widget.audioFactory ?? GuideAudioService.new)();

  /// 지금 낭독 중인 클립 id (전체 듣기는 'all').
  String? _playingId;

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }

  /// 클립 하나 낭독. 재생 실패(에셋 누락 등)는 토스트로 알린다.
  Future<void> _playOne(String clipId) async {
    await _audio.stopAll();
    setState(() => _playingId = clipId);
    try {
      await _audio.playVoice(clipId);
    } catch (_) {
      if (mounted) SnackMessage.show(context, '음성 파일을 재생하지 못했습니다.');
    }
    if (mounted && _playingId == clipId) setState(() => _playingId = null);
  }

  /// 전체 듣기 — 인트로 → 재생 화면 단축키 → 트레이닝 단축키 → 마침.
  Future<void> _playAll() async {
    await _audio.stopAll();
    setState(() => _playingId = 'all');
    final ids = <String>[
      'help_intro',
      for (final e in AppShortcuts.entries) e.clipId,
      'help_training_intro',
      for (final e in AppShortcuts.trainingEntries) e.clipId,
      'help_done',
    ];
    try {
      await _audio.playVoiceSequence(
        ids,
        cancelled: () => !mounted || _playingId != 'all',
      );
    } catch (_) {
      if (mounted) SnackMessage.show(context, '음성 파일을 재생하지 못했습니다.');
    }
    if (mounted && _playingId == 'all') setState(() => _playingId = null);
  }

  Future<void> _stop() async {
    setState(() => _playingId = null);
    await _audio.stopAll();
  }

  @override
  Widget build(BuildContext context) {
    final playingAll = _playingId == 'all';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('도움말 — 단축키', style: AppTypography.screenTitle),
            ),
            FilledButton.icon(
              onPressed: playingAll ? _stop : _playAll,
              icon: Icon(playingAll ? Icons.stop : Icons.volume_up),
              label: Text(playingAll ? '정지' : '전체 듣기'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, AppConstants.minTouchTarget),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '항목의 스피커 버튼을 누르면 음성으로 읽어 줍니다. '
          '재생 단축키는 홈·즐겨찾기·전체화면에서 동작하고, 글자를 입력하는 중에는 꺼집니다.',
          style: AppTypography.bodyMuted,
        ),
        const SizedBox(height: 12),
        Text('재생 화면', style: AppTypography.listTitle),
        const SizedBox(height: 4),
        for (final entry in AppShortcuts.entries) _entryRow(entry),
        const SizedBox(height: 16),
        Text('트레이닝 따라하기 중', style: AppTypography.listTitle),
        const SizedBox(height: 4),
        for (final entry in AppShortcuts.trainingEntries) _entryRow(entry),
      ],
    );
  }

  /// 단축키 한 줄 — [▶] 키 설명.
  Widget _entryRow(ShortcutHelpEntry entry) {
    final playing = _playingId == entry.clipId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            onPressed: playing ? _stop : () => _playOne(entry.clipId),
            icon: Icon(
              playing ? Icons.stop : Icons.volume_up_outlined,
              color: playing ? AppColors.accent : null,
            ),
            tooltip: playing ? '정지' : '음성으로 듣기',
            constraints: const BoxConstraints(
              minWidth: AppConstants.minTouchTarget,
              minHeight: AppConstants.minTouchTarget,
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(entry.keys, style: AppTypography.mono),
          ),
          Expanded(
            child: Text(entry.description, style: AppTypography.body),
          ),
        ],
      ),
    );
  }
}
