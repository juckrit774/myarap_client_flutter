import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/app_colors.dart';
import '../../../../core/services/network_manager.dart';
import '../../../../shared/widgets/app_header.dart';
import '../../models/problem_model.dart';

class ProblemDetailScreen extends StatefulWidget {
  final ProblemModel problem;
  const ProblemDetailScreen({super.key, required this.problem});

  @override
  State<ProblemDetailScreen> createState() => _ProblemDetailScreenState();
}

class _ProblemDetailScreenState extends State<ProblemDetailScreen> {
  ProblemModel? _detail;
  bool _loading = true;

  // Close action state
  bool _showCloseForm = false;
  final _remarkCtrl = TextEditingController();
  bool _closing = false;
  String? _closeErr;

  // Comment state
  final _commentCtrl = TextEditingController();
  bool _commenting = false;
  String? _commentErr;

  // CSAT state
  String? _csatToken;
  bool _showCsat = false;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  @override
  void dispose() {
    _remarkCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    if (widget.problem.id.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!_loading) setState(() => _loading = true);
    try {
      final data = await NetworkManager.instance
          .getV3('/v3/api/tickets/${widget.problem.id}');
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

  ProblemModel get _effective => _detail ?? widget.problem;

  bool get _isClosed =>
      ['closed', 'cancelled'].contains(_effective.currentStatus);

  // ── Actions ──────────────────────────────────────────────

  Future<void> _submitClose() async {
    setState(() { _closing = true; _closeErr = null; });
    try {
      final data = await NetworkManager.instance.postV3(
        '/v3/api/tickets/${_effective.id}/close',
        {'remark': _remarkCtrl.text.trim()},
      );
      if (mounted) {
        final token = data['csatToken'] as String?;
        setState(() {
          _detail = ProblemModel.fromJson(data);
          _showCloseForm = false;
          _remarkCtrl.clear();
          _closing = false;
          if (token != null && token.isNotEmpty) {
            _csatToken = token;
            _showCsat = true;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() { _closeErr = e.toString(); _closing = false; });
    }
  }

  Future<void> _submitComment() async {
    final body = _commentCtrl.text.trim();
    if (body.isEmpty) return;
    setState(() { _commenting = true; _commentErr = null; });
    try {
      final data = await NetworkManager.instance.postV3(
        '/v3/api/tickets/${_effective.id}/comments',
        {'body': body},
      );
      if (mounted) {
        setState(() {
          _detail = ProblemModel.fromJson(data);
          _commentCtrl.clear();
          _commenting = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _commentErr = e.toString(); _commenting = false; });
    }
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgColor,
      appBar: const AppHeader(
        showBackButton: true,
        title: Text(
          'รายละเอียด Ticket',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                RefreshIndicator(
              onRefresh: _loadDetail,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusHeader(ticket: _effective),
                    const SizedBox(height: 12),
                    _InfoCard(ticket: _effective),
                    // ── Status History ──
                    if (_effective.statusLogs.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _TimelineCard(logs: _effective.statusLogs),
                    ],
                    // ── Work Log ──
                    const SizedBox(height: 12),
                    _WorkLogCard(
                      comments: _effective.comments,
                      isClosed: _isClosed,
                      commentCtrl: _commentCtrl,
                      commenting: _commenting,
                      error: _commentErr,
                      onSubmit: _submitComment,
                    ),
                    // ── Confirm & Close (resolved only — ล่างสุด เหมือน Actions บน web) ──
                    if (_effective.currentStatus == 'resolved') ...[
                      const SizedBox(height: 12),
                      _CloseCard(
                        showForm: _showCloseForm,
                        remarkCtrl: _remarkCtrl,
                        closing: _closing,
                        error: _closeErr,
                        onOpen: () => setState(() { _showCloseForm = true; _closeErr = null; }),
                        onCancel: () => setState(() { _showCloseForm = false; _remarkCtrl.clear(); _closeErr = null; }),
                        onSubmit: _submitClose,
                      ),
                    ],
                    if (_effective.imageList.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _ImagesCard(images: _effective.imageList),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
                // ── CSAT overlay ──
                if (_showCsat && _csatToken != null)
                  _CsatOverlay(
                    token: _csatToken!,
                    ticketNumber: _effective.problemNo,
                    ticketTitle: _effective.problemList.isNotEmpty
                        ? _effective.problemList.first
                        : '',
                    onDismiss: () => setState(() => _showCsat = false),
                  ),
              ],
            ),
    );
  }
}

// ── Status header card ──────────────────────────────────────

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.ticket});
  final ProblemModel ticket;

  @override
  Widget build(BuildContext context) {
    final statusInfo = _statusInfo(ticket.currentStatus);
    final priorityInfo = _priorityInfo(ticket.priority);

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Badge(label: statusInfo.label, color: statusInfo.color, filled: true),
                const SizedBox(width: 8),
                _Badge(label: priorityInfo.label, color: priorityInfo.color, filled: false),
              ],
            ),
            const SizedBox(height: 16),
            Icon(Icons.confirmation_number_outlined,
                size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 6),
            Text(
              ticket.problemNo,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.deepPurple,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              ticket.problemList.join(', '),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Info card ───────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.ticket});
  final ProblemModel ticket;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            if (ticket.assetNo.isNotEmpty) _Row('เครื่อง / Asset', ticket.assetNo),
            if (ticket.reporter.isNotEmpty) ...[
              const _Divider(),
              _Row('ผู้แจ้ง', ticket.reporter),
            ],
            if (ticket.assigneeId.isNotEmpty) ...[
              const _Divider(),
              _Row('ช่างที่รับงาน', ticket.assigneeId),
            ],
            const _Divider(),
            _Row('วันที่แจ้ง', ticket.formattedDate),
            if (ticket.remark.isNotEmpty) ...[
              const _Divider(),
              _Row('รายละเอียด', ticket.remark),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Confirm & Close card ─────────────────────────────────────

class _CloseCard extends StatelessWidget {
  const _CloseCard({
    required this.showForm,
    required this.remarkCtrl,
    required this.closing,
    required this.error,
    required this.onOpen,
    required this.onCancel,
    required this.onSubmit,
  });
  final bool showForm;
  final TextEditingController remarkCtrl;
  final bool closing;
  final String? error;
  final VoidCallback onOpen;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.green.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 18, color: Colors.green.shade600),
                const SizedBox(width: 6),
                Text(
                  'ช่างแก้ไขปัญหาแล้ว',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.green.shade700),
                ),
              ],
            ),
            if (!showForm) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.done_all, size: 18),
                  label: const Text('ยืนยันรับงาน / ปิด Ticket'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              const Text('บันทึกเพิ่มเติม (ถ้ามี)',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 6),
              TextField(
                controller: remarkCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'ข้อความเพิ่มเติม...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              if (error != null) ...[
                const SizedBox(height: 6),
                Text(error!,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.red)),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: closing ? null : onSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: closing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white))
                          : const Text('ยืนยัน'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: closing ? null : onCancel,
                    child: const Text('ยกเลิก'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Status timeline card ────────────────────────────────────

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.logs});
  final List<StatusLogEntry> logs;

  @override
  Widget build(BuildContext context) {
    final reversed = logs.reversed.toList();
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header — same style as Work Log header
            Row(
              children: [
                Icon(Icons.history, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 6),
                Text(
                  'ประวัติสถานะ',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Timeline body with vertical line
            Stack(
              children: [
                // vertical line
                Positioned(
                  left: 3,
                  top: 8,
                  bottom: 8,
                  child: Container(
                    width: 1,
                    color: Colors.grey.shade200,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: reversed.asMap().entries.map((entry) {
                      final isLast = entry.key == reversed.length - 1;
                      return _TimelineRow(log: entry.value, isLast: isLast);
                    }).toList(),
                  ),
                ),
                // dots column (on top of line)
                Column(
                  children: reversed.map((log) {
                    final toInfo = _statusInfo(log.to);
                    return _TimelineDot(color: toInfo.color);
                  }).toList(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Dot widget — hollow circle with colored border (like web `w-2 h-2 rounded-full border`)
class _TimelineDot extends StatelessWidget {
  const _TimelineDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52, // approximate row height for alignment
      child: Align(
        alignment: Alignment.topLeft,
        child: Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
            border: Border.all(color: color.withValues(alpha: 0.7), width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.log, required this.isLast});
  final StatusLogEntry log;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final fromInfo = _statusInfo(log.from);
    final toInfo = _statusInfo(log.to);
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. datetime first (muted, xs)
          Text(
            _fmtDateTime(log.at),
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          ),
          const SizedBox(height: 4),
          // 2. [FROM badge] → [TO badge] + "โดย [name]"
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              _Badge(label: fromInfo.label, color: fromInfo.color, filled: true, small: true),
              Icon(Icons.arrow_forward, size: 10, color: Colors.grey[400]),
              _Badge(label: toInfo.label, color: toInfo.color, filled: true, small: true),
              Text(
                'โดย ${log.by.isEmpty ? '—' : log.by}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
          // 3. remark (if any) with left border indent
          if (log.remark.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: Colors.grey.shade300, width: 2),
                ),
              ),
              child: Text(
                log.remark,
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Work Log card ───────────────────────────────────────────

class _WorkLogCard extends StatelessWidget {
  const _WorkLogCard({
    required this.comments,
    required this.isClosed,
    required this.commentCtrl,
    required this.commenting,
    required this.error,
    required this.onSubmit,
  });
  final List<CommentEntry> comments;
  final bool isClosed;
  final TextEditingController commentCtrl;
  final bool commenting;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final reversed = comments.reversed.toList();
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.chat_bubble_outline,
                    size: 14, color: Colors.grey[500]),
                const SizedBox(width: 6),
                Text(
                  comments.isNotEmpty
                      ? 'Work Log (${comments.length})'
                      : 'Work Log',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Comment list
            if (reversed.isNotEmpty) ...[
              ...reversed.map((c) => _CommentRow(comment: c)),
              const SizedBox(height: 4),
            ] else ...[
              Text('ยังไม่มีบันทึก',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400])),
              const SizedBox(height: 12),
            ],
            // Add input (hidden when closed/cancelled)
            if (!isClosed) ...[
              TextField(
                controller: commentCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'เพิ่มบันทึกการทำงาน...',
                  hintStyle:
                      TextStyle(fontSize: 13, color: Colors.grey[400]),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: AppColors.mainPurple.withValues(alpha: 0.5))),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              if (error != null) ...[
                const SizedBox(height: 4),
                Text(error!,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.red)),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: commenting ? null : onSubmit,
                  icon: commenting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.mainPurple))
                      : const Icon(Icons.send, size: 14),
                  label: Text(
                      commenting ? 'กำลังบันทึก...' : 'บันทึก',
                      style: const TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.mainPurple,
                    side: BorderSide(
                        color: AppColors.mainPurple.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment});
  final CommentEntry comment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author + datetime
          Row(
            children: [
              Text(
                comment.by.isEmpty ? '—' : comment.by,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700]),
              ),
              const SizedBox(width: 8),
              Text(
                _fmtDateTime(comment.at),
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Body with left border indent
          Container(
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: Colors.grey.shade300, width: 2),
              ),
            ),
            child: Text(
              comment.body,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Images card ─────────────────────────────────────────────

class _ImagesCard extends StatelessWidget {
  const _ImagesCard({required this.images});
  final List<String> images;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'รูปภาพ',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.deepPurple),
            ),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: images
                  .map((url) => ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(url, fit: BoxFit.cover),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── CSAT Overlay ────────────────────────────────────────────

class _CsatOverlay extends StatefulWidget {
  const _CsatOverlay({
    required this.token,
    required this.ticketNumber,
    required this.ticketTitle,
    required this.onDismiss,
  });
  final String token;
  final String ticketNumber;
  final String ticketTitle;
  final VoidCallback onDismiss;

  @override
  State<_CsatOverlay> createState() => _CsatOverlayState();
}

class _CsatOverlayState extends State<_CsatOverlay> {
  int _score = 0;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;
  bool _done = false;
  String? _err;

  static const _starColors = [
    Colors.red,
    Colors.orange,
    Colors.amber,
    Colors.teal,
    Colors.green,
  ];
  static const _starLabels = ['แย่มาก', 'แย่', 'พอใช้', 'ดี', 'ดีมาก'];

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_score == 0) {
      setState(() => _err = 'กรุณาเลือกระดับความพึงพอใจ');
      return;
    }
    setState(() { _submitting = true; _err = null; });
    try {
      await NetworkManager.instance.postV3Public(
        '/api/v1/csat/survey',
        {'token': widget.token, 'score': _score, 'comment': _commentCtrl.text.trim()},
      );
      if (mounted) {
        setState(() { _done = true; _submitting = false; });
        await Future.delayed(const Duration(milliseconds: 2500));
        if (mounted) widget.onDismiss();
      }
    } catch (e) {
      if (mounted) setState(() { _err = e.toString(); _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onDismiss,
      child: Container(
        color: Colors.black.withValues(alpha: 0.5),
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () {}, // ป้องกัน dismiss เมื่อแตะใน dialog
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(24),
            child: _done ? _thankYouState() : _formState(),
          ),
        ),
      ),
    );
  }

  Widget _thankYouState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, size: 56, color: Colors.green),
        const SizedBox(height: 12),
        const Text(
          'ขอบคุณสำหรับความคิดเห็น!',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _formState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            const Icon(Icons.star_rate_rounded, size: 20, color: Colors.amber),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'ประเมินความพึงพอใจ',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            GestureDetector(
              onTap: widget.onDismiss,
              child: const Icon(Icons.close, size: 20, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // ticket ref
        Text(
          '${widget.ticketNumber}${widget.ticketTitle.isNotEmpty ? ' — ${widget.ticketTitle}' : ''}',
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 16),
        // Stars
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final active = i < _score;
            final color = _starColors[i];
            return GestureDetector(
              onTap: () => setState(() => _score = i + 1),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  active ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 40,
                  color: active ? color : Colors.grey.shade300,
                ),
              ),
            );
          }),
        ),
        if (_score > 0) ...[
          const SizedBox(height: 4),
          Center(
            child: Text(
              _starLabels[_score - 1],
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _starColors[_score - 1],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        // Comment
        TextField(
          controller: _commentCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'ความคิดเห็นเพิ่มเติม (ถ้ามี)',
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          style: const TextStyle(fontSize: 13),
        ),
        if (_err != null) ...[
          const SizedBox(height: 6),
          Text(_err!, style: const TextStyle(fontSize: 12, color: Colors.red)),
        ],
        const SizedBox(height: 16),
        // Buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.mainPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('ส่งคะแนน', style: TextStyle(fontSize: 14)),
              ),
            ),
            const SizedBox(width: 10),
            TextButton(
              onPressed: _submitting ? null : widget.onDismiss,
              child: Text('ข้ามไปก่อน',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Shared helpers ───────────────────────────────────────────

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 16);
}

class _Badge extends StatelessWidget {
  const _Badge(
      {required this.label,
      required this.color,
      required this.filled,
      this.small = false});
  final String label;
  final Color color;
  final bool filled;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 8 : 12, vertical: small ? 2 : 5),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.12) : Colors.transparent,
        border: filled ? null : Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: small ? 11 : 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

String _fmtDateTime(DateTime dt) =>
    DateFormat('dd MMM yyyy HH:mm').format(dt.toLocal());

// ── Status / Priority info ────────────────────────────────────

class _StatusInfo {
  final String label;
  final Color color;
  const _StatusInfo(this.label, this.color);
}

_StatusInfo _statusInfo(String status) => switch (status) {
      'new' => _StatusInfo('รอดำเนินการ', Colors.red),
      'assigned' => _StatusInfo('มอบหมายแล้ว', AppColors.orange),
      'in_progress' => _StatusInfo('กำลังดำเนินการ', AppColors.opaPurple),
      'resolved' => _StatusInfo('แก้ไขแล้ว', Colors.teal),
      'closed' => _StatusInfo('ปิดแล้ว', Colors.green),
      'cancelled' => _StatusInfo('ยกเลิก', Colors.grey),
      'Open' || 'Opened' => _StatusInfo('เปิด', Colors.red),
      'In Progress' || 'Processing' =>
        _StatusInfo('กำลังดำเนินการ', AppColors.orange),
      'Resolved' => _StatusInfo('แก้ไขแล้ว', Colors.teal),
      'Closed' => _StatusInfo('ปิดแล้ว', Colors.green),
      _ => _StatusInfo(status, Colors.grey),
    };

_StatusInfo _priorityInfo(String priority) => switch (priority) {
      'critical' => _StatusInfo('วิกฤต', Colors.red),
      'high' => _StatusInfo('สูง', AppColors.orange),
      'medium' => _StatusInfo('ปานกลาง', Colors.amber),
      'low' => _StatusInfo('ต่ำ', Colors.grey),
      _ => _StatusInfo(priority, Colors.grey),
    };
