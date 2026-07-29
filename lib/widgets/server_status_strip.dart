// file: lib/widgets/server_status_strip.dart
//
// AI 분리 서버(SAW separator) 상태 표시. 상태를 주기적으로 확인해
// 텍스트로 보여준다 — 색만으로 구분하지 않는다.
//
// v2.5.0에서 전용 줄을 없애고 현재 재생 바 안에 들어가는 칩으로 바꿨다.
// 상시 표시 스트립이 세로 공간을 한 줄씩 먹어 목록·프롬퍼터가 좁아졌기 때문이다.
import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../services/vocal_separation_client.dart';
import '../theme/app_theme.dart';

class ServerStatusChip extends StatefulWidget {
  /// 꺼져 있을 때 누르면 서버를 켠다. null이면 예전처럼 새로고침만 한다.
  final Future<bool> Function()? onStartServer;

  const ServerStatusChip({super.key, this.onStartServer});

  @override
  State<ServerStatusChip> createState() => _ServerStatusChipState();
}

class _ServerStatusChipState extends State<ServerStatusChip> {
  final _client = VocalSeparationClient();
  Timer? _timer;
  SeparationServerStatus _status = const SeparationServerStatus(online: false);
  bool _checking = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    // 폴링은 가볍게 — 상태 조회는 3초 타임아웃의 GET 하나다.
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _client.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_checking) return;
    _checking = true;
    final status = await _client.status();
    _checking = false;
    if (!mounted) return;
    setState(() => _status = status);
  }

  /// 꺼져 있고 켤 수단이 있으면 켠다. 아니면 상태만 다시 확인한다.
  Future<void> _onTap() async {
    if (_starting) return;
    final start = widget.onStartServer;
    if (!_status.online && start != null) {
      setState(() => _starting = true);
      await start();
      if (!mounted) return;
      setState(() => _starting = false);
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final online = _status.online;
    final canStart = !online && widget.onStartServer != null;
    final label = _starting ? '분리 서버 켜는 중…' : _status.label;
    return Semantics(
      label: label,
      button: true,
      child: Tooltip(
        message: _starting
            ? '분리 서버를 켜는 중입니다 (최대 2분)'
            : canStart
            ? '$label (눌러서 서버 켜기)'
            : '$label (눌러서 새로고침)',
        child: InkWell(
          borderRadius: AppShapes.controlRadius,
          onTap: _onTap,
          child: Container(
            height: AppConstants.minTouchTarget,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _starting
                      ? Icons.cloud_sync_outlined
                      : online
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  size: 15,
                  color: online ? AppColors.positive : AppColors.textMuted,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: AppTypography.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
