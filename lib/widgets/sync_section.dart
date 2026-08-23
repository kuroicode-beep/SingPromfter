// file: lib/widgets/sync_section.dart
//
// 곡 동기화 설정. PC와 폰에서 서로 다른 얼굴을 보여 준다.
//   PC  — 서버를 켜고, 폰이 입력할 주소와 페어링 코드를 크게 보여 준다.
//   폰  — PC 주소·코드를 입력하고 [지금 동기화]를 누른다.
//
// 방향은 PC → 폰 단방향이다. 폰에서 PC로 쓰는 UI는 만들지 않는다 —
// 없는 기능은 버튼도 없어야 헷갈리지 않는다.
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_constants.dart';
import '../models/prompter_settings.dart';
import '../services/sync_discovery.dart';
import '../services/sync_server_handler.dart';
import '../theme/app_theme.dart';
import '../utils/platform_capabilities.dart';

/// LAN에서 보이는 이 PC의 주소를 찾는다. 여러 개면 사설 대역을 우선한다.
Future<String?> findLanAddress({int port = 8772}) async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    final candidates = <String>[];
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        candidates.add(addr.address);
      }
    }
    if (candidates.isEmpty) return null;
    // 192.168.* / 10.* 를 먼저 — 가상 어댑터 주소가 앞에 오는 일이 잦다.
    candidates.sort((a, b) {
      int rank(String ip) {
        if (ip.startsWith('192.168.')) return 0;
        if (ip.startsWith('10.')) return 1;
        if (ip.startsWith('172.')) return 2;
        return 3;
      }

      return rank(a).compareTo(rank(b));
    });
    return '${candidates.first}:$port';
  } catch (_) {
    return null;
  }
}

/// PC 쪽 — 동기화 서버 켜기와 접속 정보 표시.
class SyncServerSection extends StatefulWidget {
  final PrompterSettings settings;
  final ValueChanged<PrompterSettings> onChanged;

  const SyncServerSection({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  State<SyncServerSection> createState() => _SyncServerSectionState();
}

class _SyncServerSectionState extends State<SyncServerSection> {
  String? _address;

  @override
  void initState() {
    super.initState();
    _refreshAddress();
  }

  Future<void> _refreshAddress() async {
    final addr = await findLanAddress();
    if (mounted) setState(() => _address = addr);
  }

  void _toggle(bool next) {
    if (!next) {
      widget.onChanged(widget.settings.copyWith(syncServerEnabled: false));
      return;
    }
    // 켤 때마다 코드를 새로 만든다 — 예전 코드를 아는 기기가 계속 붙지
    // 못하게. 사람이 손으로 옮겨 적는 값이라 6자리로 짧게 둔다.
    final rand = Random.secure();
    final code = SyncPairingCode.generate(rand.nextInt);
    widget.onChanged(
      widget.settings.copyWith(syncServerEnabled: true, syncPairingCode: code),
    );
    _refreshAddress();
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.settings.syncServerEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('폰으로 곡 보내기', style: AppTypography.listTitle),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('동기화 서버 켜기', style: AppTypography.body),
          subtitle: Text(
            on
                ? '켜짐 — 같은 와이파이의 폰이 이 PC에서 곡을 받아갈 수 있습니다'
                : '꺼짐 — 제어 API가 이 PC 안에서만 동작합니다',
            style: AppTypography.bodyMuted,
          ),
          value: on,
          onChanged: _toggle,
        ),
        if (on) ...[
          const SizedBox(height: 8),
          _CopyRow(
            label: 'PC 주소',
            value: _address ?? '네트워크를 찾는 중…',
            copyable: _address != null,
          ),
          const SizedBox(height: 8),
          _CopyRow(
            label: '페어링 코드',
            value: widget.settings.syncPairingCode,
            copyable: widget.settings.syncPairingCode.isNotEmpty,
            big: true,
          ),
          const SizedBox(height: 10),
          Text(
            '폰의 [설정 > 데이터 > PC에서 곡 받기]에 위 두 값을 입력하세요.\n'
            '곡·가사는 이 PC 것이 정본이고, 폰은 받기만 합니다.\n'
            '끄면 다시 이 PC 안에서만 동작합니다.',
            style: AppTypography.bodyMuted,
          ),
        ],
      ],
    );
  }
}

class _CopyRow extends StatelessWidget {
  final String label;
  final String value;
  final bool copyable;
  final bool big;

  const _CopyRow({
    required this.label,
    required this.value,
    required this.copyable,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 96, child: Text(label, style: AppTypography.bodyMuted)),
        Expanded(
          child: SelectableText(
            value,
            style: big
                ? AppTypography.mono.copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  )
                : AppTypography.mono,
          ),
        ),
        if (copyable)
          IconButton(
            tooltip: '복사',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('$label 복사됨')));
            },
          ),
      ],
    );
  }
}

/// 폰 쪽 — PC 주소·코드를 입력하고 받아온다.
class SyncPullDialog extends StatefulWidget {
  final String initialAddress;

  /// 실제 수신은 화면이 넘겨준다(테스트에서 가짜를 넣는다).
  final Future<String> Function(String address, String code) onPull;

  const SyncPullDialog({
    super.key,
    required this.initialAddress,
    required this.onPull,
  });

  static Future<void> show(
    BuildContext context, {
    required String initialAddress,
    required Future<String> Function(String address, String code) onPull,
  }) => showDialog<void>(
    context: context,
    builder: (_) =>
        SyncPullDialog(initialAddress: initialAddress, onPull: onPull),
  );

  @override
  State<SyncPullDialog> createState() => _SyncPullDialogState();
}

class _SyncPullDialogState extends State<SyncPullDialog> {
  late final TextEditingController _addr = TextEditingController(
    text: widget.initialAddress,
  );
  final TextEditingController _code = TextEditingController();
  bool _busy = false;
  bool _scanning = false;
  String? _result;

  /// 같은 와이파이의 PC를 찾아 주소를 채운다 — IP를 외워 적지 않게.
  /// 하나면 바로 채우고, 여럿이면 골라 달라고 한다.
  Future<void> _findPc() async {
    setState(() {
      _scanning = true;
      _result = null;
    });
    final found = await const SyncDiscoveryScanner().scan();
    if (!mounted) return;
    setState(() => _scanning = false);

    if (found.isEmpty) {
      setState(() {
        _result =
            'PC를 찾지 못했습니다. PC에서 [폰으로 곡 보내기]를 켰는지, '
            '같은 와이파이인지 확인해 주세요.';
      });
      return;
    }
    if (found.length == 1) {
      setState(() {
        _addr.text = found.first.address;
        _result = '${found.first.name} 을(를) 찾았습니다.';
      });
      return;
    }
    final picked = await showDialog<DiscoveredPc>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('PC 고르기'),
        children: [
          for (final pc in found)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(pc),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  '${pc.name}\n${pc.address}',
                  style: AppTypography.body,
                ),
              ),
            ),
        ],
      ),
    );
    if (picked != null && mounted) {
      setState(() => _addr.text = picked.address);
    }
  }

  @override
  void dispose() {
    _addr.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    final message = await widget.onPull(_addr.text, _code.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('PC에서 곡 받기'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PC의 [설정 > 데이터 > 폰으로 곡 보내기]를 켜면 주소와 코드가 나옵니다.\n'
              '같은 와이파이에 있어야 합니다.',
              style: AppTypography.bodyMuted,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addr,
                    enabled: !_busy && !_scanning,
                    decoration: const InputDecoration(
                      labelText: 'PC 주소',
                      hintText: '192.168.0.5:8772',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: (_busy || _scanning) ? null : _findPc,
                  icon: _scanning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_find),
                  label: Text(_scanning ? '찾는 중' : 'PC 찾기'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(110, AppConstants.minTouchTarget),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _code,
              enabled: !_busy,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: '페어링 코드',
                hintText: '6자리',
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text('받는 중… 반주 파일이 크면 시간이 걸립니다', style: AppTypography.bodyMuted),
            ],
            if (_result != null) ...[
              const SizedBox(height: 14),
              Text(_result!, style: AppTypography.body),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
        FilledButton(
          onPressed: _busy ? null : _run,
          style: FilledButton.styleFrom(
            minimumSize: const Size(120, AppConstants.minTouchTarget),
          ),
          child: const Text('지금 동기화'),
        ),
      ],
    );
  }
}

/// 이 플랫폼에서 동기화 서버(보내는 쪽)를 보여 줄지.
bool get showSyncServerSection => PlatformCapabilities.hasControlServer;

/// 이 플랫폼에서 받기 UI를 보여 줄지.
bool get showSyncPullTile => PlatformCapabilities.isMobile;
