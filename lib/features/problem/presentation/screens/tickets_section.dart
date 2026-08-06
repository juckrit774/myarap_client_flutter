import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/config/app_colors.dart';
import '../../../../core/services/network_manager.dart';
import '../../../../shared/widgets/app_shell.dart';
import '../../../../shared/widgets/ticket_style.dart';
import '../../models/problem_model.dart';
import '../view_models/problem_view_model.dart';
import 'csat_dialog.dart';

/// หน้า "ปัญหาที่แจ้ง" — **รายการซ้าย + รายละเอียดขวา ในหน้าเดียว**
///
/// ของเดิมเป็น 2 หน้าซ้อนกัน (`problem_screen` → `Navigator.push` → `problem_detail_screen`)
/// อยากดูเรื่องถัดไปต้องกด Back แล้วเลือกใหม่ทุกครั้ง ทั้งที่จอกว้างพอจะวางคู่กันได้สบาย
class TicketsSection extends StatefulWidget {
  const TicketsSection({super.key, this.initialTicketId});

  /// เปิดมาจากการ์ด "ต้องทำ" หรือการแจ้งเตือน → เลือกเรื่องนี้ให้เลย
  final String? initialTicketId;

  @override
  State<TicketsSection> createState() => _TicketsSectionState();
}

class _TicketsSectionState extends State<TicketsSection> {
  String? _selectedId;

  @override
  void didUpdateWidget(TicketsSection old) {
    super.didUpdateWidget(old);
    if (widget.initialTicketId != null &&
        widget.initialTicketId != old.initialTicketId) {
      setState(() => _selectedId = widget.initialTicketId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProblemViewModel>();
    final c = AppColors.of(context);

    // เลือกเรื่องแรกให้อัตโนมัติ — แผงขวาที่ว่างเปล่าตอนเปิดหน้ามาไม่ได้บอกอะไรเลย
    final list = vm.problems;
    var selected = _selectedId ?? widget.initialTicketId;
    if (list.isNotEmpty && !list.any((p) => p.id == selected)) {
      selected = list.first.id;
    }

    final waiting = list.where((p) => TicketStyle.needsUserAction(p.currentStatus)).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(children: [
        SectionHeader(
          title: 'ปัญหาที่แจ้ง',
          subtitle: list.isEmpty
              ? null
              : '${list.length} เรื่อง${waiting > 0 ? ' · รอคุณยืนยัน $waiting' : ''}',
          trailing: GhostButton(
            label: 'รีเฟรช',
            icon: Icons.refresh,
            onPressed: vm.isLoading ? null : vm.loadProblems,
          ),
        ),
        Expanded(
          child: vm.isLoading && list.isEmpty
              ? Center(child: CircularProgressIndicator(color: c.violet))
              : list.isEmpty
                  ? EmptyState(
                      icon: Icons.check_circle_outline,
                      text: vm.errorMessage ?? 'ยังไม่มีเรื่องที่แจ้ง',
                      hint: vm.errorMessage == null
                          ? 'แจ้งเรื่องใหม่ได้ที่เมนู “แจ้งปัญหา”'
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
                          itemBuilder: (_, i) => _ListRow(
                            problem: list[i],
                            selected: list[i].id == selected,
                            onTap: () => setState(() => _selectedId = list[i].id),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _TicketDetail(
                          key: ValueKey(selected),
                          summary: list.firstWhere((p) => p.id == selected),
                          onChanged: vm.loadProblems,
                        ),
                      ),
                    ]);
                    }),
        ),
      ]),
    );
  }
}

// ── รายการซ้าย ────────────────────────────────────────────

class _ListRow extends StatelessWidget {
  const _ListRow({required this.problem, required this.selected, required this.onTap});
  final ProblemModel problem;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final sc = TicketStyle.statusColor(c, problem.currentStatus);
    final needsAction = TicketStyle.needsUserAction(problem.currentStatus);
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(problem.problemNo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected ? c.violet : c.ink)),
                ),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: sc, shape: BoxShape.circle),
                ),
              ]),
              const SizedBox(height: 5),
              Text(
                problem.problemList.isEmpty ? '—' : problem.problemList.first,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c.dim, height: 1.35),
              ),
              const SizedBox(height: 7),
              Row(children: [
                Text(TicketStyle.statusLabel(problem.currentStatus),
                    style: TextStyle(
                        fontSize: 10.5, fontWeight: FontWeight.w600, color: sc)),
                const Spacer(),
                Text(DateFormat('d MMM').format(problem.created),
                    style: TextStyle(fontSize: 10.5, color: c.dim)),
              ]),
              if (needsAction) ...[
                const SizedBox(height: 6),
                Text('รอคุณยืนยันปิดงาน',
                    style: TextStyle(
                        fontSize: 10.5, fontWeight: FontWeight.w600, color: c.warn)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

// ── รายละเอียดขวา ─────────────────────────────────────────

class _TicketDetail extends StatefulWidget {
  const _TicketDetail({super.key, required this.summary, required this.onChanged});
  final ProblemModel summary;

  /// เรื่องเปลี่ยนสถานะแล้ว → ให้รายการซ้ายโหลดใหม่ (badge เมนูจะได้ตรง)
  final VoidCallback onChanged;

  @override
  State<_TicketDetail> createState() => _TicketDetailState();
}

class _TicketDetailState extends State<_TicketDetail> {
  ProblemModel? _detail;
  bool _loading = true;

  final _remarkCtrl = TextEditingController();
  bool _showCloseForm = false;
  bool _closing = false;
  String? _closeErr;

  final _commentCtrl = TextEditingController();
  bool _commenting = false;
  String? _commentErr;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _remarkCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  ProblemModel get _t => _detail ?? widget.summary;

  Future<void> _load() async {
    if (widget.summary.id.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final data = await NetworkManager.instance
          .getV3('/v3/api/tickets/${widget.summary.id}');
      if (mounted) {
        setState(() {
          _detail = ProblemModel.fromJson(data);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitClose() async {
    setState(() {
      _closing = true;
      _closeErr = null;
    });
    try {
      final data = await NetworkManager.instance
          .postV3('/v3/api/tickets/${_t.id}/close', {'remark': _remarkCtrl.text.trim()});
      if (!mounted) return;
      final token = data['csatToken'] as String?;
      setState(() {
        _detail = ProblemModel.fromJson(data);
        _showCloseForm = false;
        _remarkCtrl.clear();
        _closing = false;
      });
      widget.onChanged();
      if (token != null && token.isNotEmpty) {
        // แบบสำรวจเป็นชั้นที่ 2 จริง ๆ (ตอบแล้วจบไป) — ใช้ dialog ได้ตามกติกา
        showCsatDialog(context,
            token: token, ticketNumber: _t.problemNo, ticketTitle: _title);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _closeErr = e.toString();
          _closing = false;
        });
      }
    }
  }

  Future<void> _submitComment() async {
    final body = _commentCtrl.text.trim();
    if (body.isEmpty) return;
    setState(() {
      _commenting = true;
      _commentErr = null;
    });
    try {
      final data = await NetworkManager.instance
          .postV3('/v3/api/tickets/${_t.id}/comments', {'body': body});
      if (mounted) {
        setState(() {
          _detail = ProblemModel.fromJson(data);
          _commentCtrl.clear();
          _commenting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _commentErr = e.toString();
          _commenting = false;
        });
      }
    }
  }

  String get _title => _t.problemList.isEmpty ? '—' : _t.problemList.join(', ');

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: c.violet));
    }
    final t = _t;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _header(c, t),
        const SizedBox(height: 11),
        // งานที่ช่างแก้เสร็จแล้วอยู่บนสุด — เป็นสิ่งเดียวในหน้านี้ที่ต้องให้ผู้ใช้ลงมือทำ
        if (TicketStyle.needsUserAction(t.currentStatus)) ...[
          _closeCard(c),
          const SizedBox(height: 11),
        ],
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _infoCard(c, t)),
          const SizedBox(width: 11),
          Expanded(child: _timelineCard(c, t)),
        ]),
        const SizedBox(height: 11),
        _workLogCard(c, t),
        if (t.imageList.isNotEmpty) ...[
          const SizedBox(height: 11),
          _imagesCard(c, t),
        ],
      ],
    );
  }

  Widget _header(AppPalette c, ProblemModel t) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ป้าย 2 ใบ + เลขที่เรื่อง ยาวเกินแผงตอนย่อหน้าต่าง — Wrap ให้ตกบรรทัดได้
          Wrap(
            spacing: 7,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(t.problemNo,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
              const SizedBox(width: 4),
              StatusPill(TicketStyle.statusLabel(t.currentStatus),
                  color: TicketStyle.statusColor(c, t.currentStatus)),
              StatusPill(TicketStyle.priorityLabel(t.priority),
                  color: TicketStyle.priorityColor(c, t.priority), dot: false),
            ],
          ),
          const SizedBox(height: 6),
          Text(_title, style: TextStyle(fontSize: 13, color: c.dim, height: 1.4)),
        ]),
      );

  Widget _infoCard(AppPalette c, ProblemModel t) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CardTitle('ข้อมูลเรื่อง'),
          if (t.assetNo.isNotEmpty) KvRow('เครื่อง', t.assetNo),
          if (t.reporter.isNotEmpty) KvRow('ผู้แจ้ง', t.reporter),
          KvRow('ช่างที่รับงาน', t.assigneeId.isEmpty ? 'ยังไม่มอบหมาย' : t.assigneeId,
              valueColor: t.assigneeId.isEmpty ? c.dim : null),
          KvRow('วันที่แจ้ง', t.formattedDate),
          if (t.remark.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('รายละเอียดที่แจ้ง', style: TextStyle(fontSize: 11, color: c.dim)),
            const SizedBox(height: 4),
            Text(t.remark, style: TextStyle(fontSize: 12.5, color: c.ink, height: 1.5)),
          ],
        ]),
      );

  Widget _timelineCard(AppPalette c, ProblemModel t) {
    final logs = t.statusLogs.reversed.toList();
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CardTitle('ความคืบหน้า'),
        if (logs.isEmpty)
          Text('ยังไม่มีการเปลี่ยนสถานะ',
              style: TextStyle(fontSize: 12, color: c.dim))
        else
          for (var i = 0; i < logs.length; i++)
            _timelineRow(c, logs[i], last: i == logs.length - 1),
      ]),
    );
  }

  Widget _timelineRow(AppPalette c, StatusLogEntry log, {required bool last}) {
    final col = TicketStyle.statusColor(c, log.to);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.tint(col),
              border: Border.all(color: col, width: 1.5),
            ),
          ),
          if (!last)
            Expanded(child: Container(width: 1, color: c.line)),
        ]),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(TicketStyle.statusLabel(log.to),
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: col)),
                ),
                Text(DateFormat('d MMM HH:mm').format(log.at.toLocal()),
                    style: TextStyle(fontSize: 10.5, color: c.dim)),
              ]),
              const SizedBox(height: 2),
              Text('โดย ${log.by.isEmpty ? '—' : log.by}',
                  style: TextStyle(fontSize: 11, color: c.dim)),
              if (log.remark.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: c.line, width: 2))),
                  child: Text(log.remark,
                      style: TextStyle(fontSize: 11.5, color: c.dim, height: 1.4)),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _workLogCard(AppPalette c, ProblemModel t) {
    final comments = t.comments.reversed.toList();
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CardTitle(comments.isEmpty ? 'บันทึกการทำงาน' : 'บันทึกการทำงาน (${comments.length})'),
        if (comments.isEmpty)
          Text('ยังไม่มีบันทึก', style: TextStyle(fontSize: 12, color: c.dim))
        else
          for (final cm in comments)
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(cm.by.isEmpty ? '—' : cm.by,
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500, color: c.ink)),
                  const SizedBox(width: 8),
                  Text(DateFormat('d MMM yyyy HH:mm').format(cm.at.toLocal()),
                      style: TextStyle(fontSize: 10.5, color: c.dim)),
                ]),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.only(left: 9),
                  decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: c.line, width: 2))),
                  child: Text(cm.body,
                      style: TextStyle(fontSize: 12.5, color: c.dim, height: 1.45)),
                ),
              ]),
            ),
        if (!TicketStyle.isFinal(t.currentStatus)) ...[
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: TextField(
                controller: _commentCtrl,
                minLines: 1,
                maxLines: 4,
                style: TextStyle(fontSize: 12.5, color: c.ink),
                decoration: appInput(c, 'เพิ่มข้อมูล / ตอบกลับช่าง...'),
              ),
            ),
            const SizedBox(width: 8),
            GhostButton(
              label: _commenting ? 'กำลังส่ง' : 'ส่ง',
              icon: Icons.send,
              color: c.violet,
              onPressed: _commenting ? null : _submitComment,
            ),
          ]),
          if (_commentErr != null) ...[
            const SizedBox(height: 5),
            Text(_commentErr!, style: TextStyle(fontSize: 11, color: c.crit)),
          ],
        ],
      ]),
    );
  }

  Widget _closeCard(AppPalette c) => AppCard(
        accent: c.warn,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.task_alt, size: 16, color: c.warn),
            const SizedBox(width: 7),
            Expanded(
              child: Text('ช่างแจ้งว่าแก้ไขเสร็จแล้ว',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: c.warn)),
            ),
          ]),
          const SizedBox(height: 5),
          Text('ตรวจดูว่าใช้งานได้ปกติแล้วกดยืนยันเพื่อปิดเรื่อง — ถ้ายังมีปัญหา เขียนบอกในบันทึกการทำงานด้านล่างได้',
              style: TextStyle(fontSize: 11.5, color: c.dim, height: 1.45)),
          const SizedBox(height: 11),
          if (!_showCloseForm)
            PrimaryButton(
              label: 'ยืนยันปิดเรื่อง',
              icon: Icons.done_all,
              onPressed: () => setState(() {
                _showCloseForm = true;
                _closeErr = null;
              }),
            )
          else ...[
            TextField(
              controller: _remarkCtrl,
              minLines: 2,
              maxLines: 4,
              style: TextStyle(fontSize: 12.5, color: c.ink),
              decoration: appInput(c, 'บันทึกเพิ่มเติม (ไม่บังคับ)'),
            ),
            if (_closeErr != null) ...[
              const SizedBox(height: 5),
              Text(_closeErr!, style: TextStyle(fontSize: 11, color: c.crit)),
            ],
            const SizedBox(height: 9),
            Row(children: [
              PrimaryButton(
                label: 'ยืนยัน',
                busy: _closing,
                onPressed: _closing ? null : _submitClose,
              ),
              const SizedBox(width: 8),
              GhostButton(
                label: 'ยกเลิก',
                onPressed: _closing
                    ? null
                    : () => setState(() {
                          _showCloseForm = false;
                          _remarkCtrl.clear();
                          _closeErr = null;
                        }),
              ),
            ]),
          ],
        ]),
      );

  Widget _imagesCard(AppPalette c, ProblemModel t) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CardTitle('รูปที่แนบมา'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final url in t.imageList)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(url,
                      width: 128,
                      height: 96,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                            width: 128,
                            height: 96,
                            color: c.soft,
                            alignment: Alignment.center,
                            child: Icon(Icons.broken_image_outlined,
                                size: 18, color: c.dim),
                          )),
                ),
            ],
          ),
        ]),
      );
}
