import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/services/due_service.dart';

class DueCard extends StatefulWidget {
  final Map<String, dynamic> entry;
  final String filterType;
  final String pharmacyId;
  final bool isExpanded;
  final bool isSaving;
  final VoidCallback onTap;
  final Future<void> Function({
    required List<String> selectedInvoiceIds,
    required double payingAmount,
  }) onConfirm;

  const DueCard({
    super.key,
    required this.entry,
    required this.filterType,
    required this.pharmacyId,
    required this.isExpanded,
    required this.isSaving,
    required this.onTap,
    required this.onConfirm,
  });

  @override
  State<DueCard> createState() => _DueCardState();
}

class _DueCardState extends State<DueCard> {
  bool _isLoadingBills = false;
  List<Map<String, dynamic>> _pendingBills = [];
  List<Map<String, dynamic>> _paidBills = [];

  int _activeTab = 0; // 0: Pending Bills, 1: Paid History
  String _selectionMode = 'all'; // 'all' or 'select'
  final Set<String> _selectedBillIds = {};
  late final TextEditingController _payController;
  String? _loadedForId;

  String _fmt(double v) => v.toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    final netDue = (widget.entry['net_due'] as num?)?.toDouble() ?? 0.0;
    _payController = TextEditingController(text: _fmt(netDue));
    if (widget.isExpanded) {
      _loadBills();
    }
  }

  @override
  void didUpdateWidget(covariant DueCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded && (!oldWidget.isExpanded || _loadedForId != widget.entry['id'])) {
      _loadBills();
    }
    if (!widget.isExpanded && oldWidget.isExpanded) {
      _selectionMode = 'all';
    }
  }

  @override
  void dispose() {
    _payController.dispose();
    super.dispose();
  }

  Future<void> _loadBills() async {
    final entityId = widget.entry['id']?.toString() ?? '';
    if (widget.pharmacyId.isEmpty || entityId.isEmpty) return;

    setState(() {
      _isLoadingBills = true;
      _loadedForId = entityId;
    });

    try {
      Map<String, List<Map<String, dynamic>>> data;
      if (widget.filterType == 'Customer') {
        data = await DueService.fetchCustomerBills(
          pharmacyId: widget.pharmacyId,
          customerId: entityId,
        );
      } else {
        data = await DueService.fetchSupplierBills(
          pharmacyId: widget.pharmacyId,
          supplierId: entityId,
        );
      }

      if (mounted) {
        setState(() {
          _pendingBills = data['pending'] ?? [];
          _paidBills = data['paid'] ?? [];
          _isLoadingBills = false;

          _selectionMode = 'all';
          _selectedBillIds.clear();
          for (final b in _pendingBills) {
            final bId = b['id']?.toString() ?? '';
            if (bId.isNotEmpty) _selectedBillIds.add(bId);
          }

          final selTotal = _selectedTotal;
          final netDue = (widget.entry['net_due'] as num?)?.toDouble() ?? 0.0;
          _payController.text = _fmt(selTotal > 0 ? selTotal : netDue);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingBills = false);
      }
    }
  }

  double get _selectedTotal {
    if (_pendingBills.isEmpty) {
      return (widget.entry['net_due'] as num?)?.toDouble() ?? 0.0;
    }
    double sum = 0.0;
    for (final b in _pendingBills) {
      final bId = b['id']?.toString() ?? '';
      if (_selectedBillIds.contains(bId)) {
        sum += (b['due_amount'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return sum;
  }

  void _onToggleAll() {
    setState(() {
      _selectionMode = 'all';
      _selectedBillIds.clear();
      for (final b in _pendingBills) {
        final bId = b['id']?.toString() ?? '';
        if (bId.isNotEmpty) _selectedBillIds.add(bId);
      }
      _payController.text = _fmt(_selectedTotal);
    });
  }

  void _onToggleSelect() {
    setState(() {
      _selectionMode = 'select';
      _selectedBillIds.clear();
      _payController.text = _fmt(0.0);
    });
  }

  void _onToggleBillItem(String billId) {
    setState(() {
      if (_selectedBillIds.contains(billId)) {
        _selectedBillIds.remove(billId);
        _selectionMode = 'select';
      } else {
        _selectedBillIds.add(billId);
        if (_selectedBillIds.length == _pendingBills.length) {
          _selectionMode = 'all';
        } else {
          _selectionMode = 'select';
        }
      }
      _payController.text = _fmt(_selectedTotal);
    });
  }

  String _formatDateTime(dynamic dateVal) {
    if (dateVal == null) return '';
    try {
      final dt = DateTime.parse(dateVal.toString()).toLocal();
      return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
    } catch (_) {
      return dateVal.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.entry['name'] as String? ?? 'Unknown';
    final phone = widget.entry['phone'] as String? ?? '';
    final netDue = (widget.entry['net_due'] as num?)?.toDouble() ?? 0.0;
    final totalPaid = (widget.entry['total_paid'] as num?)?.toDouble() ?? 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header (Card Row) ─────────────────────────────────────────────
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Name & phone
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.5,
                            color: Color(0xFF1A1A2E),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (phone.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(Icons.phone, size: 12, color: Colors.grey),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  phone,
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Net Due & Total Paid
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 115),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'TK ${_fmt(netDue)}',
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                        if (totalPaid > 0) ...[
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Paid: TK ${_fmt(totalPaid)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: widget.isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded Multi-Invoice Bill Settlement Panel ───────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: widget.isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: _buildExpandedPanel(netDue),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedPanel(double netDue) {
    if (_isLoadingBills) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Tabs: Pending Bills vs Paid History ────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _activeTab = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _activeTab == 0 ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: _activeTab == 0
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.receipt_long,
                            size: 15,
                            color: _activeTab == 0 ? AppColors.primary : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Pending Bills (${_pendingBills.length})',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: _activeTab == 0 ? FontWeight.bold : FontWeight.w500,
                              color: _activeTab == 0 ? AppColors.primary : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _activeTab = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _activeTab == 1 ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: _activeTab == 1
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 15,
                            color: _activeTab == 1 ? Colors.green.shade700 : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Paid History (${_paidBills.length})',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: _activeTab == 1 ? FontWeight.bold : FontWeight.w500,
                              color: _activeTab == 1 ? Colors.green.shade700 : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Body based on selected Tab ─────────────────────────────────────
          if (_activeTab == 0)
            _buildPendingBillsSection(netDue)
          else
            _buildPaidHistorySection(),
        ],
      ),
    );
  }

  // ── Pending Bills Tab ───────────────────────────────────────────────────────
  Widget _buildPendingBillsSection(double netDue) {
    final selTotal = _selectedTotal;
    final payingNow = double.tryParse(_payController.text) ?? 0.0;
    final remainingAfter = (selTotal - payingNow).clamp(0.0, double.infinity);
    final canConfirm = payingNow > 0 && (_pendingBills.isEmpty || _selectedBillIds.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_pendingBills.isNotEmpty) ...[
          // Top row: Header & [Select] | [All] toggle buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Select invoices to pay:',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),

              // Segmented Toggle: Select | All
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: _onToggleSelect,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _selectionMode == 'select' ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Select',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: _selectionMode == 'select' ? Colors.white : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: _onToggleAll,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: _selectionMode == 'all' ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'All',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: _selectionMode == 'all' ? Colors.white : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Invoices List
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _pendingBills.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
              itemBuilder: (context, index) {
                final bill = _pendingBills[index];
                final billId = bill['id']?.toString() ?? '';
                final isSelected = _selectedBillIds.contains(billId);
                final invNo = bill['purchase_number'] ?? bill['invoice_number'] ?? '#${billId.substring(0, 6)}';
                final dateStr = _formatDateTime(bill['created_at'] ?? bill['purchase_date']);
                final dueAmt = (bill['due_amount'] as num?)?.toDouble() ?? 0.0;

                return InkWell(
                  onTap: () => _onToggleBillItem(billId),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        // Checkbox
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: isSelected,
                            activeColor: AppColors.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            onChanged: (_) => _onToggleBillItem(billId),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Invoice number & date/time
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$invNo',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: isSelected ? Colors.black87 : Colors.grey.shade600,
                                ),
                              ),
                              if (dateStr.isNotEmpty)
                                Text(
                                  dateStr,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Due amount
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Due: ৳ ${_fmt(dueAmt)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isSelected ? Colors.redAccent : Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ] else ...[
          // No individual pending invoices found, fallback to general balance
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.amber.shade900),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'General Ledger Balance: ৳ ${_fmt(netDue)}',
                    style: TextStyle(fontSize: 12, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Summary & Payment Area ───────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
          ),
          child: Column(
            children: [
              // Row: Selected Total
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Selected Total:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
                  ),
                  Text(
                    '৳ ${_fmt(selTotal)}',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Row: Paying Amount input
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Paying Amount:',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _payController.text = _fmt(selTotal);
                      });
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Pay Full',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 105,
                    child: TextField(
                      controller: _payController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                      ],
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                        prefixText: '৳ ',
                        prefixStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const Divider(height: 18),

              // Row(s): Due After Payment
              if (_selectionMode == 'select' && _selectedBillIds.length < _pendingBills.length) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Selected Due After:',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                    ),
                    Text(
                      '৳ ${_fmt(remainingAfter)}',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: remainingAfter > 0 ? Colors.orange.shade800 : Colors.green.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.filterType == 'Customer' ? 'Total Customer Due After:' : 'Total Company Due After:',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87),
                    ),
                    Text(
                      '৳ ${_fmt((netDue - payingNow).clamp(0.0, double.infinity))}',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: (netDue - payingNow) > 0 ? Colors.red.shade600 : Colors.green.shade600,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Due After Payment:',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                    Text(
                      '৳ ${_fmt(remainingAfter)}',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: remainingAfter > 0 ? Colors.red.shade600 : Colors.green.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Confirm Payment button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (!canConfirm || widget.isSaving)
                ? null
                : () {
                    widget.onConfirm(
                      selectedInvoiceIds: _selectedBillIds.toList(),
                      payingAmount: payingNow,
                    );
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 1,
            ),
            child: widget.isSaving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : Text(
                    payingNow > 0 ? 'Confirm Payment (৳ ${_fmt(payingNow)})' : 'Enter Amount to Pay',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ],
    );
  }

  // ── Paid History Tab ────────────────────────────────────────────────────────
  Widget _buildPaidHistorySection() {
    if (_paidBills.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(Icons.history, size: 36, color: Colors.grey.shade400),
            const SizedBox(height: 6),
            Text(
              'No settled invoices yet.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _paidBills.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
        itemBuilder: (context, index) {
          final bill = _paidBills[index];
          final billId = bill['id']?.toString() ?? '';
          final invNo = bill['purchase_number'] ?? bill['invoice_number'] ?? '#${billId.substring(0, 6)}';
          final dateStr = _formatDateTime(bill['created_at'] ?? bill['purchase_date']);
          final grandTotal = (bill['grand_total'] as num?)?.toDouble() ?? 0.0;
          final paidAmt = (bill['paid_amount'] as num?)?.toDouble() ?? grandTotal;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check, size: 14, color: Colors.green.shade700),
                ),
                const SizedBox(width: 10),

                // Invoice no & date
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$invNo',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                      ),
                      if (dateStr.isNotEmpty)
                        Text(
                          dateStr,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                    ],
                  ),
                ),

                // Paid amount badge
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Paid: ৳ ${_fmt(paidAmt)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.green.shade700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'PAID',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}