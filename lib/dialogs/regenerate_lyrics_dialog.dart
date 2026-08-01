// file: lib/dialogs/regenerate_lyrics_dialog.dart
//
// '가사 다시 생성' 옵션 다이얼로그 — 정밀 받아쓰기 파이프라인의 입구.
// 정답 가사를 붙여넣으면 타이밍은 받아쓰기, 텍스트는 정답으로 만든다.
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class RegenerateLyricsOptions {
  final bool useVocalStem;
  final bool useDeepSeek;
  final bool useYoutubeSubs;
  final String? referenceLyrics;

  const RegenerateLyricsOptions({
    required this.useVocalStem,
    required this.useDeepSeek,
    this.useYoutubeSubs = true,
    this.referenceLyrics,
  });
}

class RegenerateLyricsDialog {
  RegenerateLyricsDialog._();

  static Future<RegenerateLyricsOptions?> show(
    BuildContext context, {
    required bool hasExistingLyrics,
    required bool deepSeekAvailable,
    bool hasSourceUrl = false,
  }) {
    final refController = TextEditingController();
    var useVocalStem = true;
    var useDeepSeek = deepSeekAvailable;
    var useYoutubeSubs = hasSourceUrl;

    return showDialog<RegenerateLyricsOptions>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.elevated,
          title: const Text(
            '가사 다시 생성',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '노래에서 보컬만 뽑아 다시 받아쓰고, 환청으로 생긴 줄을 '
                    '자동으로 정리합니다.',
                    style: AppTypography.body.copyWith(height: 1.5),
                  ),
                  if (hasExistingLyrics) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.tertiary),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '⚠ 지금 싱크 가사를 완전히 새로 만듭니다 — 손으로 '
                        '고친 줄·타이밍도 함께 사라져요.',
                        style: AppTypography.body.copyWith(
                          color: AppColors.tertiary,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    '정답 가사 붙여넣기 (선택)',
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '멜론 등에서 가사를 복사해 붙여넣으면 받아쓰기 오탈자 없이 '
                    '정답 텍스트로 만들어요. 타이밍은 받아쓰기에서 가져옵니다.',
                    style: AppTypography.bodyMuted.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: refController,
                    maxLines: 6,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      height: 1.5,
                    ),
                    decoration: const InputDecoration(
                      hintText: '여기에 가사 전문을 붙여넣으세요 (비워 두면 받아쓴 텍스트 사용)',
                      hintStyle: TextStyle(color: AppColors.textMuted),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (hasSourceUrl)
                    _OptionRow(
                      value: useYoutubeSubs,
                      onChanged: (v) => setLocal(() => useYoutubeSubs = v),
                      title: '유튜브 자막 우선 (있으면)',
                      subtitle: '업로더가 단 수동 자막은 타이밍까지 있는 정답이라 '
                          '받아쓰기를 건너뛰어요',
                    ),
                  _OptionRow(
                    value: useVocalStem,
                    onChanged: (v) => setLocal(() => useVocalStem = v),
                    title: '보컬 분리 사용 (권장)',
                    subtitle: '수십 초 더 걸리지만 반주 환청이 크게 줄어요',
                  ),
                  _OptionRow(
                    value: useDeepSeek,
                    onChanged: deepSeekAvailable
                        ? (v) => setLocal(() => useDeepSeek = v)
                        : null,
                    title: 'AI 텍스트 검증 (DeepSeek)',
                    subtitle: deepSeekAvailable
                        ? '비문·무의미한 줄을 한 번 더 걸러요'
                        : '환경변수 DEEPSEEK_API_KEY가 없어 사용할 수 없어요',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                ctx,
                RegenerateLyricsOptions(
                  useVocalStem: useVocalStem,
                  useDeepSeek: useDeepSeek,
                  useYoutubeSubs: useYoutubeSubs,
                  referenceLyrics: refController.text.trim().isEmpty
                      ? null
                      : refController.text,
                ),
              ),
              child: const Text('다시 생성'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 체크박스 + 제목/설명 한 벌 — 터치 타깃 50px 이상.
class _OptionRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String title;
  final String subtitle;

  const _OptionRow({
    required this.value,
    required this.onChanged,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return InkWell(
      onTap: enabled ? () => onChanged!(!value) : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value && enabled,
              onChanged: enabled ? (v) => onChanged!(v ?? false) : null,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.body.copyWith(
                      color: enabled
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: AppTypography.bodyMuted.copyWith(height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
