// file: lib/widgets/center_alert.dart
//
// 화면 가운데 **큰 글씨** 경고 오버레이.
//
// 토스트(SnackMessage)와 다르다. 토스트는 「알리고 지나가는」 것이고 이건
// 「여기서 멈추는」 것이다 — 그대로 진행하면 결과물을 통째로 잃는 상황에만 쓴다.
//
// 만든 계기: 녹음 입력이 죽어 있는데 헤드폰으로는 정상으로 들려서, 무음 조각을
// 여섯 개나 쌓고 나서야 알았다(2026-09-21). 귀로 확인이 안 되는 실패는
// 화면이 막아 줘야 한다.
//
// 🔴 이 오버레이는 접근성(시맨틱스) 노드를 만들지 않는다.
//
// 2026-09-22 실사고: 녹음 고정·R·스페이스를 누르면 앱이 통째로 죽었다.
// 덤프 5건을 엔진 PDB로 풀어 보니 전부 Flutter 접근성 브리지였다 —
//   AXNodeData::HasIntAttribute            <- AXPlatformNodeWin::get_accState
//   std::terminate                         <- AXPlatformNodeWin::get_accRole
//   FlutterPlatformNodeDelegate::GetParent <- get_accParent
// 키를 누르면 Windows 입력 스택(한글 IME)이 MSAA/UIA로 화면 요소를 잡는데,
// 그 요소가 곧바로 사라지면(토스트·경고·녹음 표시) 엔진이 해제된 노드를
// 읽다 죽는다. 떴다 사라지는 UI는 노드를 아예 만들지 않거나(이 파일·토스트),
// 노드를 계속 둔 채 값만 바꾼다(녹음·잠금 배지).
import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../theme/app_theme.dart';

class CenterAlert {
  CenterAlert._();

  static OverlayEntry? _entry;
  static Timer? _timer;

  /// 큰 경고를 띄운다. 아무 데나 누르거나 [확인]으로 닫는다.
  ///
  /// 자동으로도 사라지지만(기본 20초) 시간은 넉넉히 둔다 — 노래하다 보면
  /// 화면을 늦게 본다. 읽기 전에 사라지면 없는 것과 같다.
  static void show(
    BuildContext context, {
    required String title,
    required String detail,
    Duration duration = const Duration(seconds: 20),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    dismiss();
    final entry = OverlayEntry(
      builder: (_) => _CenterAlertOverlay(title: title, detail: detail),
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(duration, dismiss);
  }

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  @visibleForTesting
  static bool get isShowing => _entry != null;
}

class _CenterAlertOverlay extends StatelessWidget {
  final String title;
  final String detail;

  const _CenterAlertOverlay({required this.title, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      // 맨 바깥에서 막는다 — 안쪽에 두면 InkWell이 탭 노드를 따로 만든다.
      child: ExcludeSemantics(
        child: Material(
          color: Colors.black.withValues(alpha: 0.82),
          child: InkWell(
            // 어디를 눌러도 닫힌다 — 급할 때 버튼을 찾게 두지 않는다.
            onTap: CenterAlert.dismiss,
            child: Center(
              child: SizedBox(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 28,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      // 색만으로 알리지 않지만, 테두리로 심각도를 한 번 더 준다.
                      border: Border.all(color: AppColors.danger, width: 3),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: AppFonts.lineSeed,
                            fontSize: 40,
                            height: 1.25,
                            color: AppColors.danger,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          detail,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: AppFonts.lineSeed,
                            fontSize: 20,
                            height: 1.6,
                            color: AppColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: AppConstants.minTouchTarget,
                          child: FilledButton(
                            onPressed: CenterAlert.dismiss,
                            child: const Text(
                              '확인',
                              style: TextStyle(
                                fontFamily: AppFonts.lineSeed,
                                fontSize: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
