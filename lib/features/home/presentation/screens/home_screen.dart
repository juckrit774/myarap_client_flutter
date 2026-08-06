import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../shared/widgets/app_shell.dart';
import '../../../../shared/widgets/loading_overlay.dart';
import '../../../../shared/widgets/ticket_style.dart';
import '../../../notification/presentation/screens/notifications_section.dart';
import '../../../notification/presentation/view_models/notification_view_model.dart';
import '../../../problem/presentation/screens/tickets_section.dart';
import '../../../problem/presentation/view_models/problem_view_model.dart';
import '../../../report/presentation/screens/report_section.dart';
import '../../../report/presentation/view_models/report_view_model.dart';
import '../../../settings/presentation/screens/settings_section.dart';
import '../view_models/home_view_model.dart';
import 'device_section.dart';

/// หน้าหลักของ agent — **คอนโซลหน้าเดียว** (แบบ A)
///
/// view model ทั้ง 4 ตัวถูกสร้างที่ระดับนี้ ไม่ใช่ในแต่ละหน้า เพราะ badge ของเมนูซ้าย
/// ต้องรู้จำนวนเรื่องที่รอยืนยัน/แจ้งเตือนที่ยังไม่อ่าน **ตลอดเวลา** ไม่ใช่เฉพาะตอนเปิดหน้านั้น
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => HomeViewModel()..initialize()),
        ChangeNotifierProvider(create: (_) => ProblemViewModel()..loadProblems()),
        ChangeNotifierProvider(create: (_) => NotificationViewModel()..load()),
        ChangeNotifierProvider(create: (_) => ReportViewModel()..loadProblemTypes()),
      ],
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView();

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  AppSection _section = AppSection.device;
  String? _openTicketId;

  @override
  void initState() {
    super.initState();
    requestedSection.addListener(_onExternalRequest);
  }

  @override
  void dispose() {
    requestedSection.removeListener(_onExternalRequest);
    super.dispose();
  }

  /// เมนู Settings ของ OS / tray สั่งเปลี่ยนหน้าเข้ามา (ดู `requestedSection`)
  void _onExternalRequest() {
    final s = requestedSection.value;
    if (s == null || !mounted) return;
    requestedSection.value = null;
    _go(s);
  }

  void _go(AppSection s) {
    setState(() {
      _section = s;
      if (s != AppSection.tickets) _openTicketId = null;
    });
    // เข้าหน้าไหนก็ดึงข้อมูลของหน้านั้นใหม่ — ข้อมูลค้างจากรอบก่อนทำให้ผู้ใช้
    // เห็นสถานะเก่าและกดยืนยันซ้ำ
    if (s == AppSection.tickets) context.read<ProblemViewModel>().loadProblems();
    if (s == AppSection.notifications) context.read<NotificationViewModel>().load();
  }

  void _openTicket(String id) {
    setState(() {
      _section = AppSection.tickets;
      _openTicketId = id;
    });
    context.read<ProblemViewModel>().loadProblems();
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeViewModel>();
    final tickets = context.watch<ProblemViewModel>();
    final notifs = context.watch<NotificationViewModel>();

    final pending = tickets.problems
        .where((p) => TicketStyle.needsUserAction(p.currentStatus))
        .length;

    return Stack(children: [
      AppShell(
        current: _section,
        onSelect: _go,
        userName: home.ownerName.isNotEmpty ? home.ownerName : home.userName,
        userAccount: home.ownerAccount.isNotEmpty ? home.ownerAccount : home.assetNo,
        roleLabel: home.ownerRole,
        ticketBadge: pending,
        notifBadge: notifs.unreadCount,
        child: _body(home, pending),
      ),
      // โหลดครั้งแรกเท่านั้น (เก็บ hardware info + auth) — refresh ระหว่างใช้งาน
      // ไม่ต้องบังหน้าจอทั้งใบ
      if (home.isLoading && home.deviceDetail == null) const LoadingOverlay(),
    ]);
  }

  Widget _body(HomeViewModel home, int pending) => switch (_section) {
        AppSection.device => DeviceSection(
            vm: home,
            pendingCount: pending,
            onOpenPending: () => _go(AppSection.tickets),
          ),
        AppSection.report =>
          ReportSection(onSent: () => _go(AppSection.tickets)),
        AppSection.tickets => TicketsSection(initialTicketId: _openTicketId),
        AppSection.notifications =>
          NotificationsSection(onOpenTicket: _openTicket),
        AppSection.settings => SettingsSection(vm: home),
      };
}
