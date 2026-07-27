// file: lib/widgets/server_status_strip.dart
//
// 홈 대시보드의 서버 상태 표시줄. AI 분리 서버(SAW separator) 상태를
// 주기적으로 확인해 텍스트로 보여준다. 색만으로 구분하지 않는다.
import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../services/vocal_separation_client.dart';
import '../theme/app_theme.dart';

class ServerStatusStrip extends StatefulWidget {
  const ServerStatusStrip({super.key});

  @override
  State<ServerStatusStrip> createState() => _ServerStatusStripState();
}

class _ServerStatusStripState extends State<ServerStatusStrip> {
  final _client = VocalSeparationClient();
  Timer? _timer;
  SeparationServerStatus _status = const SeparationServerStatus(online: false);
  bool _checking = false;

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

  @override
  Widget build(BuildContext context) {
    final online = _status.online;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.outline)),
      ),
      child: Row(
        children: [
          Icon(
            online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            size: 20,
            color: online ? AppColors.positive : AppColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _status.label,
              style: AppTypography.bodyMuted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Semantics(
            label: '서버 상태 새로고침',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: '서버 상태 새로고침',
              constraints: const BoxConstraints(
                minWidth: AppConstants.minTouchTarget,
                minHeight: 40,
              ),
              onPressed: _refresh,
            ),
          ),
        ],
      ),
    );
  }
}
