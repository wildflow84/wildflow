import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/image_save.dart';
import '../../data/store.dart';
import '../../ui/palette.dart';
import '../../ui/snack.dart';
import 'coupon.dart';
import 'image_prep.dart';

/// 쿠폰 판매: 민아가 쿠폰 스크린샷을 올리면 번호를 읽어 저장하고 대희 아빠의 오늘 할 일로 만든다.
/// 그 할 일을 완료하면 판매 완료. 이미 판매한 번호는 다시 등록할 수 없다.
class CouponScreen extends StatefulWidget {
  const CouponScreen({super.key});

  @override
  State<CouponScreen> createState() => _CouponScreenState();
}

class _CouponScreenState extends State<CouponScreen> {
  final _picker = ImagePicker();
  bool _busy = false;
  String _busyText = '';
  List<Coupon> _coupons = const [];

  Future<void> _add() async {
    final s = context.read<Store>();
    final messenger = ScaffoldMessenger.of(context);
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() {
      _busy = true;
      _busyText = '스크린샷을 준비하는 중…';
    });
    Uint8List? image;
    try {
      image = await prepareCouponImage(await picked.readAsBytes());
    } catch (_) {}
    if (image == null) {
      if (mounted) setState(() => _busy = false);
      showTimedSnack(messenger, '이미지를 읽지 못했어. 다른 스크린샷으로 해줘');
      return;
    }
    setState(() => _busyText = '쿠폰번호를 읽는 중…');
    CouponScan scan;
    try {
      scan = await s.repo.scanCoupon(s.spaceId!, image);
    } catch (_) {
      scan = const CouponScan([], 'error');
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final number = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConfirmDialog(image: image!, scan: scan),
    );
    if (number == null || !mounted) return;
    final normalized = normalizeCouponNumber(number);
    if (normalized == null) {
      showTimedSnack(messenger, '쿠폰번호를 확인해줘 (영문/숫자 6~32자)');
      return;
    }
    // 서버에 묻기 전에 목록에서 먼저 확인 (서버도 한 번 더 막는다)
    final dup = _coupons.where((c) => c.number == normalized).firstOrNull;
    if (dup != null) {
      await _showAlready(sold: dup.sold, number: normalized);
      return;
    }
    setState(() {
      _busy = true;
      _busyText = '등록하는 중…';
    });
    try {
      await s.repo.registerCoupon(s.spaceId!, normalized, image);
      showTimedSnack(messenger, '등록했어. 오늘 할 일로 올라갔어', seconds: 4);
    } on CouponAlreadyException catch (e) {
      if (mounted) await _showAlready(sold: e.sold, number: normalized);
    } catch (_) {
      showTimedSnack(messenger, '등록하지 못했어. 잠시 뒤에 다시 해줘');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showAlready({required bool sold, required String number}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(sold ? Icons.block : Icons.hourglass_top, color: sold ? kRed : kAccent),
        title: Text(sold ? '이미 판매한 쿠폰이야' : '이미 등록된 쿠폰이야'),
        content: Text(sold
            ? '${formatCouponNumber(number)}\n이 쿠폰은 판매 완료라서 다시 등록할 수 없어.'
            : '${formatCouponNumber(number)}\n이미 등록돼서 판매를 기다리고 있어.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    return Scaffold(
      appBar: AppBar(title: const Text('쿠폰 판매')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _add,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('쿠폰 등록'),
      ),
      body: Stack(children: [
        StreamBuilder<List<Coupon>>(
          stream: s.spaceId == null ? const Stream.empty() : s.repo.watchCoupons(s.spaceId!),
          builder: (context, snap) {
            final list = [...?snap.data]..sort((a, b) {
                if (a.sold != b.sold) return a.sold ? 1 : -1; // 판매 대기가 위
                final ta = (a.sold ? a.soldAt : a.requestedAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
                final tb = (b.sold ? b.soldAt : b.requestedAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
                return tb.compareTo(ta);
              });
            _coupons = list;
            if (snap.connectionState == ConnectionState.waiting && list.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (list.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('아직 등록한 쿠폰이 없어.\n아래 "쿠폰 등록"으로 스크린샷을 올리면\n번호를 읽어서 대희 아빠의 할 일로 올려줘.',
                      textAlign: TextAlign.center, style: TextStyle(color: kMuted, height: 1.5)),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _CouponTile(list[i], onTap: () => _showDetail(list[i])),
            );
          },
        ),
        if (_busy)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0x66000000),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(_busyText),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  void _showDetail(Coupon c) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CouponDetail(coupon: c),
    );
  }
}

class _CouponTile extends StatelessWidget {
  final Coupon c;
  final VoidCallback onTap;
  const _CouponTile(this.c, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('M월 d일', 'ko');
    final when = c.sold
        ? (c.soldAt == null ? '판매 완료' : '${df.format(c.soldAt!)} 판매 완료')
        : (c.requestedAt == null ? '판매 대기' : '${df.format(c.requestedAt!)} 등록');
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(c.sold ? Icons.check_circle : Icons.local_activity_outlined, color: c.sold ? kMuted : kAccent),
        title: Text(c.display, style: TextStyle(fontWeight: FontWeight.w600, decoration: c.sold ? TextDecoration.lineThrough : null)),
        subtitle: Text('${c.requestedByName.isEmpty ? '' : '${c.requestedByName} · '}$when'),
        trailing: Chip(
          label: Text(c.sold ? '판매 완료' : '판매 대기'),
          visualDensity: VisualDensity.compact,
          backgroundColor: c.sold ? kFill : kAccentSoft,
        ),
      ),
    );
  }
}

/// 쿠폰 상세: 스크린샷 보기와 저장
class _CouponDetail extends StatefulWidget {
  final Coupon coupon;
  const _CouponDetail({required this.coupon});

  @override
  State<_CouponDetail> createState() => _CouponDetailState();
}

class _CouponDetailState extends State<_CouponDetail> {
  late final Future<Uint8List?> _image;

  @override
  void initState() {
    super.initState();
    final s = context.read<Store>();
    _image = s.repo.couponImage(s.spaceId!, widget.coupon.number).catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.coupon;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(c.display, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(c.sold ? '판매 완료' : '판매 대기 (대희 아빠의 할 일을 완료하면 판매 완료가 돼)', style: TextStyle(color: kMuted)),
          const SizedBox(height: 12),
          Flexible(
            child: FutureBuilder<Uint8List?>(
              future: _image,
              builder: (_, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
                }
                final bytes = snap.data;
                if (bytes == null) return const SizedBox(height: 120, child: Center(child: Text('스크린샷이 없어')));
                return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Flexible(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(bytes, fit: BoxFit.contain))),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () async {
                      final err = await saveImageToDevice(bytes, 'coupon_${c.number}');
                      if (context.mounted) showOverlayToast(context, err ?? '스크린샷을 저장했어');
                    },
                    icon: const Icon(Icons.download),
                    label: const Text('스크린샷 저장'),
                  ),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// 읽은 번호를 확인/고치는 창. 후보 중에서 고르거나 직접 입력한다. 취소하면 null.
class _ConfirmDialog extends StatefulWidget {
  final Uint8List image;
  final CouponScan scan;
  const _ConfirmDialog({required this.image, required this.scan});

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  late final _ctrl = TextEditingController(text: widget.scan.candidates.isEmpty ? '' : formatCouponNumber(widget.scan.candidates.first));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _hint {
    switch (widget.scan.ocr) {
      case 'ok':
        return '스크린샷에서 읽은 번호야. 맞는지 확인해줘.';
      case 'empty':
        return '스크린샷에서 번호를 못 찾았어. 직접 입력해줘.';
      case 'unavailable':
        return '글자 읽기 기능이 아직 꺼져 있어서 직접 입력해줘.';
      default:
        return '번호를 읽지 못했어. 직접 입력해줘.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('쿠폰번호 확인'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(widget.image, height: 200, fit: BoxFit.contain)),
          const SizedBox(height: 12),
          Text(_hint, style: TextStyle(color: kMuted, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: '쿠폰번호', border: OutlineInputBorder()),
          ),
          if (widget.scan.candidates.length > 1) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in widget.scan.candidates)
                ActionChip(label: Text(formatCouponNumber(c)), onPressed: () => setState(() => _ctrl.text = formatCouponNumber(c))),
            ]),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('등록')),
      ],
    );
  }
}

/// 쿠폰 판매 할 일에서 스크린샷을 바로 저장한다 (할 일 편집 창의 버튼).
Future<void> saveCouponImage(BuildContext context, String couponId) async {
  final s = context.read<Store>();
  try {
    final bytes = await s.repo.couponImage(s.spaceId!, couponId);
    if (bytes == null) {
      if (context.mounted) showOverlayToast(context, '스크린샷을 찾지 못했어');
      return;
    }
    final err = await saveImageToDevice(bytes, 'coupon_$couponId');
    if (context.mounted) showOverlayToast(context, err ?? '스크린샷을 저장했어');
  } catch (_) {
    if (context.mounted) showOverlayToast(context, '스크린샷을 불러오지 못했어');
  }
}
