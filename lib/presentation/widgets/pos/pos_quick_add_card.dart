import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/medicine_packaging_helper.dart';
import '../../../data/models/batch_model.dart';
import '../../../data/models/export_cart_item.dart';
import '../../../data/models/medicine_model.dart';

class PosQuickAddCard extends StatefulWidget {
  final Map<String, dynamic>? matchingGlobalMedicine;
  final MedicineModel medicine;
  final ExportCartItem? initialEntry;
  final VoidCallback onCancel;
  final void Function(ExportCartItem entry) onConfirm;

  const PosQuickAddCard({
    super.key,
    this.matchingGlobalMedicine,
    required this.medicine,
    this.initialEntry,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  State<PosQuickAddCard> createState() => _PosQuickAddCardState();
}

class _PosQuickAddCardState extends State<PosQuickAddCard> {
  late final TextEditingController _qtyController;
  late final TextEditingController _rateController;

  late String _unitType;
  late int _quantity;
  late String _discountMode; // '%' or 'Cash'
  late double _discountPercent;
  late double _sellingRate; // Rate per selected unitType

  late int _pps;
  late int _spb;
  late double _baseMrp;
  late double _baseCost;
  BatchModel? _selectedBatch;

  @override
  void initState() {
    super.initState();

    final med = widget.medicine;
    final packInfo = MedicinePackagingHelper.getPackagingInfo(
      med: med,
      matchingGlobalMedicine: widget.matchingGlobalMedicine,
    );
    _pps = packInfo['pps'] ?? med.piecesPerStrip ?? 1;
    _spb = packInfo['spb'] ?? med.stripsPerBox ?? 1;

    // Pick active batch or primary batch
    _selectedBatch = widget.initialEntry?.batch ?? med.primaryActiveBatch;
    if (_selectedBatch == null && med.batches.isNotEmpty) {
      _selectedBatch = med.batches.first;
    }

    _baseMrp = _selectedBatch?.mrp ?? _selectedBatch?.sellingPrice ?? 0.0;
    if (_baseMrp <= 0) {
      // Check all batches or global
      for (final b in med.batches) {
        if (b.mrp > 0) {
          _baseMrp = b.mrp;
          break;
        }
      }
    }
    if (_baseMrp <= 0 && widget.matchingGlobalMedicine != null) {
      _baseMrp = double.tryParse(widget.matchingGlobalMedicine!['default_mrp']?.toString() ?? '') ?? 0.0;
    }

    _baseCost = _selectedBatch?.purchasePrice ?? 0.0;

    final entry = widget.initialEntry;
    if (entry != null) {
      _unitType = entry.unitType;
      _quantity = entry.quantity;
      _discountMode = entry.discountMode;
      _discountPercent = entry.discountPercent;
      _sellingRate = entry.unitSellingPrice;
      _rateController = TextEditingController(
        text: _discountMode == '%'
            ? _discountPercent.toStringAsFixed(_discountPercent.truncateToDouble() == _discountPercent ? 0 : 1)
            : _sellingRate.toStringAsFixed(2),
      );
    } else {
      final bool hasTwoTier = _pps > 1 && _spb > 1;
      final bool hasSingleTier = (_pps > 1) || (_spb > 1);
      final bool hasBox = hasTwoTier || hasSingleTier;
      _unitType = hasBox ? 'Box' : ((_pps > 1) ? 'Strip' : 'Unit');

      _quantity = 1;
      _discountMode = '%';
      _discountPercent = 0.0; // Default discount is 0% for export as requested

      final multiplier = _getMultiplierForUnit(_unitType);
      final currentUnitMrp = _baseMrp * multiplier;
      _sellingRate = currentUnitMrp;

      _rateController = TextEditingController(text: '0');
    }

    _qtyController = TextEditingController(text: _quantity.toString());
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  int _getMultiplierForUnit(String unit) {
    final bool hasTwoTier = _pps > 1 && _spb > 1;
    final int boxPcs = hasTwoTier
        ? (_spb * _pps)
        : (_pps > 1 ? _pps : (_spb > 1 ? _spb : 1));

    switch (unit) {
      case 'Strip':
        return _pps > 0 ? _pps : 1;
      case 'Box':
        return boxPcs > 0 ? boxPcs : 1;
      default:
        return 1;
    }
  }

  List<String> _getAvailableUnits() {
    final bool hasTwoTier = _pps > 1 && _spb > 1;
    final bool hasStrip = (hasTwoTier && _pps > 1) || (!hasTwoTier && _pps > 1 && _spb <= 1);
    final bool hasBox = hasTwoTier ? (_spb > 1) : (_pps > 1 || _spb > 1);

    final List<String> units = ['Unit'];
    if (hasStrip && !units.contains('Strip')) units.add('Strip');
    if (hasBox && !units.contains('Box')) units.add('Box');
    return units;
  }

  double get _currentUnitMrp => _baseMrp * _getMultiplierForUnit(_unitType);

  void _onUnitChanged(String newUnit) {
    if (newUnit == _unitType) return;
    setState(() {
      _unitType = newUnit;
      final currentMrp = _currentUnitMrp;
      if (_discountMode == '%') {
        _sellingRate = currentMrp > 0 ? currentMrp * (1 - (_discountPercent / 100)) : 0.0;
      } else {
        if (currentMrp > 0 && _discountPercent > 0) {
          _sellingRate = currentMrp * (1 - (_discountPercent / 100));
        } else {
          _sellingRate = currentMrp;
        }
        _rateController.text = _sellingRate.toStringAsFixed(2);
      }
    });
  }

  void _toggleDiscountMode(String mode) {
    if (_discountMode == mode) return;
    setState(() {
      _discountMode = mode;
      final currentMrp = _currentUnitMrp;
      if (mode == '%') {
        if (currentMrp > 0) {
          _discountPercent = (((currentMrp - _sellingRate) / currentMrp) * 100).clamp(0, 100);
        }
        _rateController.text = _discountPercent.toStringAsFixed(
            _discountPercent.truncateToDouble() == _discountPercent ? 0 : 1);
      } else {
        _rateController.text = _sellingRate.toStringAsFixed(2);
      }
    });
  }

  void _updateQuantity(int newQty) {
    final validQty = newQty < 1 ? 1 : newQty;
    setState(() {
      _quantity = validQty;
      _qtyController.text = validQty.toString();
    });
  }

  void _onRateInputChanged(String val) {
    final parsed = double.tryParse(val);
    if (parsed == null) return;
    setState(() {
      final currentMrp = _currentUnitMrp;
      if (_discountMode == '%') {
        _discountPercent = parsed.clamp(0, 100);
        _sellingRate = currentMrp > 0 ? currentMrp * (1 - (_discountPercent / 100)) : 0.0;
      } else {
        _sellingRate = parsed.clamp(0, double.infinity);
        if (currentMrp > 0) {
          _discountPercent = (((currentMrp - _sellingRate) / currentMrp) * 100).clamp(0, 100);
        }
      }
    });
  }

  void _stepRate(double delta) {
    setState(() {
      final currentMrp = _currentUnitMrp;
      if (_discountMode == '%') {
        _discountPercent = (_discountPercent + delta).clamp(0, 100);
        _rateController.text = _discountPercent.toStringAsFixed(
            _discountPercent.truncateToDouble() == _discountPercent ? 0 : 1);
        _sellingRate = currentMrp > 0 ? currentMrp * (1 - (_discountPercent / 100)) : 0.0;
      } else {
        _sellingRate = (_sellingRate + delta).clamp(0, double.infinity);
        _rateController.text = _sellingRate.toStringAsFixed(2);
        if (currentMrp > 0) {
          _discountPercent = (((currentMrp - _sellingRate) / currentMrp) * 100).clamp(0, 100);
        }
      }
    });
  }

  void _confirm() {
    final entry = ExportCartItem(
      medicine: widget.medicine,
      batch: _selectedBatch,
      quantity: _quantity,
      unitType: _unitType,
      singleUnitMrp: _baseMrp,
      singleUnitCost: _baseCost,
      unitSellingPrice: _sellingRate,
      piecesPerStrip: _pps,
      stripsPerBox: _spb,
      discountPercent: _discountPercent,
      discountMode: _discountMode,
    );

    widget.onConfirm(entry);
  }

  @override
  Widget build(BuildContext context) {
    final availableUnits = _getAvailableUnits();
    final bool isEditing = widget.initialEntry != null;
    final multiplier = _getMultiplierForUnit(_unitType);

    // Stock calculations
    final int totalStock = widget.medicine.totalStock;
    final int effectiveUsed = _quantity * multiplier;
    final int stockLeft = totalStock - effectiveUsed;
    final bool isStockExceeded = stockLeft < 0;

    // Fixed Metadata strings
    final String batchText = (_selectedBatch?.batchNumber ?? '').trim().isNotEmpty
        ? _selectedBatch!.batchNumber.trim()
        : 'N/A';

    final String expiryText = _selectedBatch?.expiryDate != null
        ? DateFormat('MM/yyyy').format(_selectedBatch!.expiryDate)
        : 'N/A';

    final String rackText = (widget.medicine.rackLocation ?? '').trim().isNotEmpty
        ? widget.medicine.rackLocation!.trim()
        : 'N/A';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isEditing ? AppColors.primary : const Color(0xFFCBD5E1),
          width: isEditing ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: (isEditing ? AppColors.primary : Colors.black).withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Brand, Dosage, Strength, Weight, Editing badge & Close button
          Row(
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 5,
                  runSpacing: 2,
                  children: [
                    if (isEditing)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Editing',
                          style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    Text(
                      widget.medicine.brandName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF0F172A)),
                    ),
                    if (widget.medicine.dosageForm.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          widget.medicine.dosageForm,
                          style: const TextStyle(color: AppColors.primary, fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    Builder(
                      builder: (context) {
                        final cleanStrWt = MedicinePackagingHelper.formatStrengthAndWeight(
                          rawStrength: widget.medicine.strength,
                          rawWeight: widget.medicine.weight,
                        );
                        if (cleanStrWt.isEmpty) return const SizedBox.shrink();
                        return Text(
                          cleanStrWt,
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                        );
                      },
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 17, color: Colors.grey),
                onPressed: widget.onCancel,
                tooltip: 'Cancel',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),

          const Divider(height: 12),

          // Row 1: Fixed Badges for Batch Number, Expiry Date, Rack No (Not Text Fields)
          LayoutBuilder(
            builder: (context, constraints) {
              final bool isNarrow = constraints.maxWidth < 440;

              Widget buildFixedPill({
                required IconData icon,
                required Color iconColor,
                required String label,
                required String value,
                Color? valueColor,
              }) {
                return Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 14, color: iconColor),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(fontSize: 9, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              value,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: valueColor ?? const Color(0xFF1E293B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              final batchCard = buildFixedPill(
                icon: Icons.qr_code_rounded,
                iconColor: AppColors.primary,
                label: 'Batch No.',
                value: batchText,
              );

              final expiryCard = buildFixedPill(
                icon: Icons.event_note_rounded,
                iconColor: AppColors.primary,
                label: 'Expiry Date',
                value: expiryText,
              );

              final rackCard = buildFixedPill(
                icon: Icons.shelves,
                iconColor: Colors.blue.shade700,
                label: 'Rack No.',
                value: rackText,
                valueColor: Colors.blue.shade800,
              );

              if (isNarrow) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: batchCard),
                        const SizedBox(width: 6),
                        Expanded(child: expiryCard),
                      ],
                    ),
                    const SizedBox(height: 6),
                    rackCard,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 4, child: batchCard),
                  const SizedBox(width: 6),
                  Expanded(flex: 3, child: expiryCard),
                  const SizedBox(width: 6),
                  Expanded(flex: 3, child: rackCard),
                ],
              );
            },
          ),

          const SizedBox(height: 8),

          // Row 2: Two Columns side-by-side (Packaging Unit + Qty & Retail Price + Discount Rate)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Column 1: Unit Selector & Quantity Stepper
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Unit select option (unit/strip/box)
                    Text(
                      'Packaging Unit',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: availableUnits.contains(_unitType) ? _unitType : availableUnits.first,
                          isExpanded: true,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF1E293B)),
                          items: availableUnits.map((u) {
                            final mult = _getMultiplierForUnit(u);
                            final label = u == 'Unit' ? 'Unit (1)' : '$u ($mult pcs)';
                            return DropdownMenuItem(value: u, child: Text(label, style: const TextStyle(fontSize: 11.5)));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) _onUnitChanged(val);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Row 2: Quantity selector with stepper & text box
                    Text(
                      'Quantity ($_unitType)',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove, size: 14),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 26, minHeight: 34),
                            onPressed: _quantity > 1 ? () => _updateQuantity(_quantity - 1) : null,
                          ),
                          Expanded(
                            child: TextField(
                              controller: _qtyController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 6),
                                border: InputBorder.none,
                              ),
                              onChanged: (val) {
                                final q = int.tryParse(val);
                                if (q != null && q > 0) {
                                  setState(() => _quantity = q);
                                }
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add, size: 14),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 26, minHeight: 34),
                            onPressed: () => _updateQuantity(_quantity + 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Column 2: Live MRP Box Card & Discount / Selling Rate (% / Cash)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: MRP Display Card
                    Text(
                      'Retail Price (MRP)',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          const Icon(Icons.sell_outlined, size: 13, color: Color(0xFF1D4ED8)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'MRP: ৳${_currentUnitMrp.toStringAsFixed(_currentUnitMrp.truncateToDouble() == _currentUnitMrp ? 0 : 2)} / $_unitType',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E40AF),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Row 2: Discount Rate with Stepper and % / Cash toggle (Defaults to 0%)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            _discountMode == '%' ? 'Discount' : 'Sell Rate',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // % / Cash Segment Toggle
                        Container(
                          height: 19,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () => _toggleDiscountMode('%'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: _discountMode == '%' ? AppColors.primary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '%',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: _discountMode == '%' ? Colors.white : Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _toggleDiscountMode('Cash'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: _discountMode == 'Cash' ? AppColors.primary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Cash',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: _discountMode == 'Cash' ? Colors.white : Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Container(
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove, size: 14),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 26, minHeight: 34),
                            onPressed: () => _stepRate(_discountMode == '%' ? -1.0 : -5.0),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _rateController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              decoration: InputDecoration(
                                isDense: true,
                                prefixText: _discountMode == '%' ? '' : '৳',
                                prefixStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                suffixText: _discountMode == '%' ? '%' : '',
                                suffixStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                                border: InputBorder.none,
                              ),
                              onChanged: _onRateInputChanged,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add, size: 14),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 26, minHeight: 34),
                            onPressed: () => _stepRate(_discountMode == '%' ? 1.0 : 5.0),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Row 3: Stock Left Now (Exact Export Design)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: isStockExceeded ? Colors.red.shade50 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isStockExceeded ? Colors.red.shade300 : Colors.grey.shade300,
              ),
            ),
            child: Row(
              children: [
                Text(
                  'Stock: ',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                ),
                Text(
                  '$totalStock ${widget.medicine.unit}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: totalStock > 0 ? Colors.blue.shade800 : Colors.red.shade700,
                  ),
                ),
                if (_quantity > 0) ...[
                  Text(
                    ' → Left: ',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  Text(
                    '${stockLeft > 0 ? stockLeft : 0} ${widget.medicine.unit}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isStockExceeded
                          ? Colors.red.shade700
                          : (stockLeft > 0 ? Colors.blue.shade700 : Colors.orange.shade700),
                    ),
                  ),
                ],
                if (isStockExceeded) ...[
                  const Spacer(),
                  Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 13),
                  const SizedBox(width: 2),
                  Text(
                    'Exceeded by ${stockLeft.abs()} pcs',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade700),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 6),

          // Row 4: Calculation Summary Line
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '$_quantity $_unitType × ৳${_sellingRate.toStringAsFixed(2)}${_discountPercent > 0 ? ' (${_discountPercent.toStringAsFixed(_discountPercent.truncateToDouble() == _discountPercent ? 0 : 1)}% off)' : ''}',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '৳${(_quantity * _sellingRate).toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Row 5: Action Buttons: Cancel and Add/Update (Bonus row omitted as requested)
          Row(
            children: [
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed: widget.onCancel,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: BorderSide(color: Colors.grey.shade400),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: _confirm,
                  icon: Icon(isEditing ? Icons.check_circle_outline_rounded : Icons.add_shopping_cart_rounded, size: 16),
                  label: Text(
                    isEditing ? 'Update Item' : 'Add to Cart',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isEditing ? const Color(0xFF0284C7) : AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 1,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
