import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/config/app_colors.dart';
import '../../../../shared/widgets/app_shell.dart';
import '../../../../shared/widgets/ticket_style.dart';
import '../../models/notification_model.dart';
import '../view_models/notification_view_model.dart';

/// หน้า "การแจ้งเตือน" — รายการซ้าย + เนื้อหาขวา
///
/// ของเดิมเป็น 2 หน้าซ้อน (`notification_screen` → push → `notification_detail_screen`)
/// ทั้งที่เนื้อหาแต่ละใบมีแค่ประโยคเดียว — กด Back ไปมาเพื่ออ่านข้อความสั้น ๆ
class NotificationsSection extends StatefulWidget {
  const NotificationsSection({super.key, this.onOpenTicket});

  /// กด "ดูเรื่องนี้" → ให้ shell สลับไปหน้า "ปัญหาที่แจ้ง" พร้อมเลือก ticket ให้
  final void Function(String ticketId)? onOpenTicket;

  @override
  State<NotificationsSection> createState() => _NotificationsSectionState();
}

class _NotificationsSectionState extends State<NotificationsSection> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NotificationViewModel>();
    final c = AppColors.of(context);
    final list = vm.notifications;

    NotificationModel? selected;
    if (list.isNotEmpty) {
      selected = list.firstWhere((n) => n.id == _selectedId, orElse: () => list.first);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(children: [
        SectionHeader(
          title: 'การแจ้งเตือน',
          subtitle: vm.unreadCount > 0 ? 'ยังไม่ได้อ่าน ${vm.unreadCount}' : null,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (vm.unreadCount > 0)
              GhostButton(
                label: 'อ่านทั้งหมด',
                icon: Icons.done_all,
                onPressed: vm.markAllAsRead,
              ),
            const SizedBox(width: 8),
            GhostButton(
              label: 'รีเฟรช',
              icon: Icons.refresh,
              onPressed: vm.isLoading ? null : vm.load,
            ),
          ]),
        ),
        Expanded(
          child: vm.isLoading && list.isEmpty
              ? Center(child: CircularProgressIndicator(color: c.violet))
              : list.isEmpty
                  ? EmptyState(
                      icon: Icons.notifications_none,
                      text: vm.errorMessage ?? 'ไม่มีการแจ้งเตือน',
                      hint: vm.errorMessage == null
                          ? 'ระบบจะแจ้งที่นี่เมื่อเรื่องที่คุณแจ้งมีความคืบหน้า'
                          : null,
                    )
                  : LayoutBuilder(builder: (_, box) {
                      return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                      SizedBox(
                        width: listPaneWidth(box.maxWidth),
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: list.length,
                          itemBuilder: (_, i) => _Row(
                            item: list[i],
                            selected: list[i].id == selected?.id,
                            onTap: () {
                              setState(() => _selectedId = list[i].id);
                              vm.markAsRead(list[i].id);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                          child: _Detail(
                              item: selected!, onOpenTicket: widget.onOpenTicket)),
                    ]);
                    }),
        ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.selected, required this.onTap});
  final NotificationModel item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: selected ? c.violet.withValues(alpha: c.isDark ? 0.16 : 0.09) : c.card,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: selected ? c.violet.withValues(alpha: 0.55) : c.line),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 5, right: 9),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: item.isRead ? c.line : c.crit,
                ),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: item.isRead ? FontWeight.w400 : FontWeight.w600,
                        color: selected ? c.violet : c.ink,
                      )),
                  const SizedBox(height: 3),
                  Text(item.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: c.dim, height: 1.35)),
                  const SizedBox(height: 5),
                  Text(_ago(item.at), style: TextStyle(fontSize: 10.5, color: c.dim)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.item, this.onOpenTicket});
  final NotificationModel item;
  final void Function(String ticketId)? onOpenTicket;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(item.title,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: c.ink)),
              ),
              Text(DateFormat('d MMM yyyy HH:mm').format(item.at),
                  style: TextStyle(fontSize: 11, color: c.dim)),
            ]),
            const SizedBox(height: 12),
            Text(item.message,
                style: TextStyle(fontSize: 13, color: c.ink, height: 1.6)),
            if (item.ticketNum.isNotEmpty) ...[
              const SizedBox(height: 14),
              // Wrap ไม่ใช่ Row — เลขที่เรื่องกับปุ่มต่อกันยาวเกินแผงตอนย่อหน้าต่าง
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusPill(item.ticketNum, color: c.cyan, dot: false),
                  if (item.ticketId.isNotEmpty && onOpenTicket != null)
                    GhostButton(
                      label: 'ดูเรื่องนี้',
                      icon: Icons.open_in_new,
                      color: c.violet,
                      onPressed: () => onOpenTicket!(item.ticketId),
                    ),
                ],
              ),
            ],
          ]),
        ),
      ],
    );
  }
}

String _ago(DateTime at) {
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return 'เมื่อสักครู่';
  if (d.inMinutes < 60) return '${d.inMinutes} นาทีที่แล้ว';
  if (d.inHours < 24) return '${d.inHours} ชม.ที่แล้ว';
  if (d.inDays < 7) return '${d.inDays} วันที่แล้ว';
  return DateFormat('d MMM yyyy').format(at);
}
