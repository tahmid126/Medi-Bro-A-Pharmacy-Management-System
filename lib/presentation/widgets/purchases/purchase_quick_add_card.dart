import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/date_picker_helper.dart';
import '../../../../core/utils/medicine_packaging_helper.dart';
import '../../../data/models/medicine_model.dart';
import '../../../data/models/purchase_cart_item.dart';

class PurchaseQuickAddCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final MedicineModel medicine;
  final CartItemEntry? initialEntry;
  final List<String> availableRacks;
  final VoidCallback onCancel;
  final void Function(CartItemEntry entry) onConfirm;

  const PurchaseQuickAddCard({
    super.key,
    required this.item,
    required this.medicine,
    this.initialEntry,
    this.availableRacks = const [],
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  State<PurchaseQuickAddCard> createState() => _PurchaseQuickAddCardState();
}

class _PurchaseQuickAddCardState extends State<PurchaseQuickAddCard> {
  late final TextEditingController _batchController;
  late final TextEditingController _rackController;
  late final TextEditingController _qtyController;
  late final TextEditingController _bonusController;
  late final TextEditingController _rateController;

  late DateTime _expiryDate;
  late String _unitType;
  late String _bonusUnitType;
  late int _quantity;
  late int _bonusQuantity;
  late String _discountMode; // '%' or 'Cash'
  late double _discountPercent;
  late double _buyRate; // Rate per selected unitType

  late int _pps;
  late int _spb;
  late double _baseMrp;

  @override
  void initState() {
    super.initState();

    final med = widget.medicine;
    final packInfo = MedicinePackagingHelper.getPackagingInfo(
      med: med,
      matchingGlobalMedicine: widget.item,
    );
    _pps = packInfo['pps'] ?? 0;
    _spb = packInfo['spb'] ?? 0;
    _baseMrp = (widget.item['mrp'] as num?)?.toDouble() ??
        double.tryParse(widget.item['mrp']?.toString() ?? '') ??
        0.0;

    final entry = widget.initialEntry;
    if (entry != null) {
      _batchController = TextEditingController(text: entry.batchNumber);
      _expiryDate = entry.expiryDate;
      _rackController = TextEditingController(text: entry.rackLocation ?? '');
      _unitType = entry.unitType;
      _bonusUnitType = entry.bonusUnitType;
      _quantity = entry.quantity;
      _bonusQuantity = entry.bonusQuantity;
      _discountMode = entry.discountMode;
      _discountPercent = entry.discountPercent;
      _buyRate = entry.unitPurchasePrice;
      _rateController = TextEditingController(
        text: _discountMode == '%'
            ? _discountPercent.toStringAsFixed(_discountPercent.truncateToDouble() == _discountPercent ? 0 : 1)
            : _buyRate.toStringAsFixed(2),
      );
    } else {
      _batchController = TextEditingController(
        text: 'B-${DateFormat('yyyyMM').format(DateTime.now())}-01',
      );
      _expiryDate = DateTime.now().add(const Duration(days: 365));
      _rackController = TextEditingController(
        text: (widget.item['rack'] ?? med.rackLocation ?? '').toString(),
      );

      final bool hasTwoTier = _pps > 0 && _spb > 0;
      final bool hasSingleTier = (_pps > 1) || (_spb > 1);
      final bool hasBox = hasTwoTier || hasSingleTier;
      _unitType = hasBox ? 'Box' : ((_pps > 1) ? 'Strip' : 'Unit');
      _bonusUnitType = _unitType;

      _quantity = 1;
      _bonusQuantity = 0;
      _discountMode = '%';
      _discountPercent = 12.0;

      final multiplier = _getMultiplierForUnit(_unitType);
      final currentUnitMrp = _baseMrp * multiplier;

      final lastBuy = (widget.item['purchase_price'] as num?)?.toDouble() ?? 0.0;
      if (lastBuy > 0) {
        _buyRate = lastBuy * multiplier;
        if (currentUnitMrp > 0) {
          _discountPercent = (((currentUnitMrp - _buyRate) / currentUnitMrp) * 100).clamp(0, 100);
        }
      } else if (currentUnitMrp > 0) {
        _buyRate = currentUnitMrp * (1 - (_discountPercent / 100));
      } else {
        _buyRate = 0.0;
      }

      _rateController = TextEditingController(
        text: _discountPercent.toStringAsFixed(_discountPercent.truncateToDouble() == _discountPercent ? 0 : 1),
      );
    }

    _qtyController = TextEditingController(text: _quantity.toString());
    _bonusController = TextEditingController(text: _bonusQuantity.toString());
  }

  @override
  void dispose() {
    _batchController.dispose();
    _rackController.dispose();
    _qtyController.dispose();
    _bonusController.dispose();
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
      if (_bonusQuantity == 0) {
        _bonusUnitType = newUnit;
      }
      final currentMrp = _currentUnitMrp;
      if (_discountMode == '%') {
        _buyRate = currentMrp > 0 ? currentMrp * (1 - (_discountPercent / 100)) : 0.0;
      } else {
        if (currentMrp > 0 && _discountPercent > 0) {
          _buyRate = currentMrp * (1 - (_discountPercent / 100));
        } else {
          _buyRate = currentMrp * 0.88;
        }
        _rateController.text = _buyRate.toStringAsFixed(2);
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
          _discountPercent = (((currentMrp - _buyRate) / currentMrp) * 100).clamp(0, 100);
        }
        _rateController.text = _discountPercent.toStringAsFixed(
            _discountPercent.truncateToDouble() == _discountPercent ? 0 : 1);
      } else {
        _rateController.text = _buyRate.toStringAsFixed(2);
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

  void _updateBonus(int newBonus) {
    final validBonus = newBonus < 0 ? 0 : newBonus;
    setState(() {
      _bonusQuantity = validBonus;
      _bonusController.text = validBonus.toString();
    });
  }

  void _onRateInputChanged(String val) {
    final parsed = double.tryParse(val);
    if (parsed == null) return;
    setState(() {
      final currentMrp = _currentUnitMrp;
      if (_discountMode == '%') {
        _discountPercent = parsed;
        _buyRate = currentMrp > 0 ? currentMrp * (1 - (_discountPercent / 100)) : 0.0;
      } else {
        _buyRate = parsed;
        if (currentMrp > 0) {
          _discountPercent = (((currentMrp - _buyRate) / currentMrp) * 100).clamp(0, 100);
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
        _buyRate = currentMrp > 0 ? currentMrp * (1 - (_discountPercent / 100)) : 0.0;
      } else {
        _buyRate = (_buyRate + delta).clamp(0, double.infinity);
        _rateController.text = _buyRate.toStringAsFixed(2);
        if (currentMrp > 0) {
          _discountPercent = (((currentMrp - _buyRate) / currentMrp) * 100).clamp(0, 100);
        }
      }
    });
  }

  void _confirm() {
    final batchNo = _batchController.text.trim().isNotEmpty
        ? _batchController.text.trim()
        : 'B-${DateFormat('yyyyMM').format(DateTime.now())}-01';

    final entry = CartItemEntry(
      medicine: widget.medicine,
      batchNumber: batchNo,
      expiryDate: _expiryDate,
      quantity: _quantity,
      bonusQuantity: _bonusQuantity,
      unitType: _unitType,
      bonusUnitType: _bonusUnitType,
      unitPurchasePrice: _buyRate,
      mrp: _baseMrp,
      discountPercent: _discountPercent,
      discountMode: _discountMode,
      piecesPerStrip: _pps,
      stripsPerBox: _spb,
      rackLocation: _rackController.text.trim().isNotEmpty
          ? _rackController.text.trim()
          : widget.medicine.rackLocation,
    );

    widget.onConfirm(entry);
  }

  Widget _buildRackField(BuildContext context) {
    return SizedBox(
      height: 34,
      child: TextField(
        controller: _rackController,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          labelText: 'Rack No.',
          hintText: 'e.g. A-1',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          prefixIcon: const Icon(Icons.shelves, size: 14, color: Colors.orange),
          suffixIcon: widget.availableRacks.isNotEmpty
              ? PopupMenuButton<String>(
                  icon: const Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey),
                  tooltip: 'Select Existing Rack',
                  padding: EdgeInsets.zero,
                  onSelected: (val) {
                    _rackController.text = val;
                  },
                  itemBuilder: (ctx) => widget.availableRacks
                      .map(
                        (r) => PopupMenuItem(
                          value: r,
                          height: 30,
                          child: Text(r, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                        ),
                      )
                      .toList(),
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final availableUnits = _getAvailableUnits();
    final bool isEditing = widget.initialEntry != null;
    final multiplier = _getMultiplierForUnit(_unitType);

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
                      widget.item['brand_name'] ?? widget.medicine.brandName,
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

          // Row 1: Batch Number, Expiry Date, Rack No (Compact & Responsive)
          LayoutBuilder(
            builder: (context, constraints) {
              final bool isNarrow = constraints.maxWidth < 440;

              final batchField = SizedBox(
                height: 34,
                child: TextField(
                  controller: _batchController,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Batch No.',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    prefixIcon: const Icon(Icons.qr_code_rounded, size: 14, color: AppColors.primary),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
              );

              final expiryPicker = InkWell(
                onTap: () {
                  DatePickerHelper.pickMonthYear(
                    context: context,
                    initialDate: _expiryDate,
                    onSelected: (date) {
                      setState(() {
                        _expiryDate = date;
                      });
                    },
                  );
                },
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event_note_rounded, size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          DateFormat('MM/yyyy').format(_expiryDate),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
              );

              if (isNarrow) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: batchField),
                        const SizedBox(width: 6),
                        Expanded(child: expiryPicker),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildRackField(context),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 4, child: batchField),
                  const SizedBox(width: 6),
                  Expanded(flex: 3, child: expiryPicker),
                  const SizedBox(width: 6),
                  Expanded(flex: 3, child: _buildRackField(context)),
                ],
              );
            },
          ),

          const SizedBox(height: 8),

          // Row 2: Two Columns side-by-side (Packaging Unit + Qty & Retail Price + Buying Rate)
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

              // Column 2: Live MRP Box Card & Buying Rate (% / Cash)
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

                    // Row 2: Buying Rate with Stepper and % / Cash toggle
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            _discountMode == '%' ? 'Discount' : 'Buy Rate',
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

          // Row 3: Calculation Summary Line
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
                    '$_quantity $_unitType × ৳${_buyRate.toStringAsFixed(2)}${_discountPercent > 0 ? ' (${_discountPercent.toStringAsFixed(_discountPercent.truncateToDouble() == _discountPercent ? 0 : 1)}% off)' : ''}',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '৳${(_quantity * _buyRate).toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // Row 4: Bonus / Offer Items (Free Products)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: _bonusQuantity > 0 ? Colors.green.shade50 : Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _bonusQuantity > 0 ? Colors.green.shade200 : Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final bool isCompact = constraints.maxWidth < 340;
                    return Row(
                      children: [
                        Icon(
                          Icons.card_giftcard_rounded,
                          size: 14,
                          color: _bonusQuantity > 0 ? Colors.green.shade700 : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            isCompact ? 'Bonus:' : 'Bonus / Free:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _bonusQuantity > 0 ? Colors.green.shade800 : const Color(0xFF1E293B),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          height: 26,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: _bonusQuantity > 0 ? Colors.green.shade300 : Colors.grey.shade300,
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: availableUnits.contains(_bonusUnitType) ? _bonusUnitType : availableUnits.first,
                              isDense: true,
                              icon: const Icon(Icons.arrow_drop_down, size: 16),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF1E293B)),
                              items: availableUnits.map((u) {
                                return DropdownMenuItem(
                                  value: u,
                                  child: Text(u, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _bonusUnitType = val);
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 22, minHeight: 24),
                          color: Colors.grey.shade600,
                          onPressed: _bonusQuantity > 0 ? () => _updateBonus(_bonusQuantity - 1) : null,
                        ),
                        SizedBox(
                          width: 34,
                          height: 26,
                          child: TextField(
                            controller: _bonusController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 3),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                            onChanged: (val) {
                              final b = int.tryParse(val);
                              if (b != null && b >= 0) {
                                setState(() => _bonusQuantity = b);
                              }
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 22, minHeight: 24),
                          color: Colors.green.shade700,
                          onPressed: () => _updateBonus(_bonusQuantity + 1),
                        ),
                      ],
                    );
                  },
                ),
                if (_bonusQuantity > 0) ...[
                  const SizedBox(height: 2),
                  Builder(
                    builder: (context) {
                      final bonusMultiplier = _getMultiplierForUnit(_bonusUnitType);
                      final totalBonusPcs = _bonusQuantity * bonusMultiplier;
                      final totalPurchasedPcs = _quantity * multiplier;
                      final totalStockPcs = totalPurchasedPcs + totalBonusPcs;
                      final double lineTotal = _buyRate * _quantity;
                      final double avgPerBase = totalStockPcs > 0 ? (lineTotal / totalStockPcs) : 0.0;
                      final double avgPerUnit = avgPerBase * multiplier;

                      final String text = _unitType == _bonusUnitType
                          ? 'Total stock: ${_quantity + _bonusQuantity} $_unitType ($totalStockPcs pcs) • Avg: ৳${avgPerUnit.toStringAsFixed(2)}/$_unitType'
                          : 'Total: $_quantity $_unitType + $_bonusQuantity $_bonusUnitType ($totalStockPcs pcs) • Avg: ৳${avgPerUnit.toStringAsFixed(2)}/$_unitType';

                      return Text(
                        text,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.green.shade700),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Action Buttons: Cancel and Add/Update
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
