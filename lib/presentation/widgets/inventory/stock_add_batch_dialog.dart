import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/date_picker_helper.dart';
import '../../../../core/utils/medicine_packaging_helper.dart';
import '../../../../data/models/medicine_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/inventory_provider.dart';

class StockAddBatchDialog extends StatefulWidget {
  final MedicineModel medicine;
  final Map<String, dynamic> matchingGlobalMedicine;
  final VoidCallback onSuccess;

  const StockAddBatchDialog({
    super.key,
    required this.medicine,
    this.matchingGlobalMedicine = const {},
    required this.onSuccess,
  });

  @override
  State<StockAddBatchDialog> createState() => _StockAddBatchDialogState();
}

class _StockAddBatchDialogState extends State<StockAddBatchDialog> {
  late TextEditingController _batchNumCtrl;
  late TextEditingController _purchasePriceCtrl;
  late TextEditingController _mrpCtrl;
  late TextEditingController _sellingPriceCtrl;
  late TextEditingController _qtyCtrl;
  DateTime _selectedExpDate = DateTime.now().add(const Duration(days: 365));
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final med = widget.medicine;
    final gm = widget.matchingGlobalMedicine;
    final packInfo = MedicinePackagingHelper.getPackagingInfo(
      med: med,
      matchingGlobalMedicine: gm,
    );
    final double libraryMrp = packInfo['libraryMrp'] ?? 0.0;

    _batchNumCtrl = TextEditingController(
      text: 'B-${DateFormat('yyyyMM').format(DateTime.now())}-01',
    );
    _purchasePriceCtrl = TextEditingController(
      text: (med.primaryActiveBatch != null && med.primaryActiveBatch!.purchasePrice > 0)
          ? med.primaryActiveBatch!.purchasePrice.toStringAsFixed(2)
          : '',
    );
    _mrpCtrl = TextEditingController(
      text: libraryMrp > 0
          ? libraryMrp.toStringAsFixed(2)
          : (med.primaryActiveBatch != null && med.primaryActiveBatch!.mrp > 0
              ? med.primaryActiveBatch!.mrp.toStringAsFixed(2)
              : ''),
    );
    _sellingPriceCtrl = TextEditingController(
      text: _mrpCtrl.text.isNotEmpty
          ? _mrpCtrl.text
          : (med.primaryActiveBatch != null && med.primaryActiveBatch!.sellingPrice > 0
              ? med.primaryActiveBatch!.sellingPrice.toStringAsFixed(2)
              : ''),
    );
    _qtyCtrl = TextEditingController(text: '100');
  }

  @override
  void dispose() {
    _batchNumCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _mrpCtrl.dispose();
    _sellingPriceCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final batchNum = _batchNumCtrl.text.trim();
    if (batchNum.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter batch number')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final auth = context.read<AuthProvider>();
    final invProvider = context.read<InventoryProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final pharmacyId = auth.currentPharmacy?.id ?? '';
    final med = widget.medicine;
    final gm = widget.matchingGlobalMedicine;
    final packInfo = MedicinePackagingHelper.getPackagingInfo(
      med: med,
      matchingGlobalMedicine: gm,
    );
    final double libraryMrp = packInfo['libraryMrp'] ?? 0.0;

    final purchasePrice = double.tryParse(_purchasePriceCtrl.text) ?? 0.0;
    var mrp = double.tryParse(_mrpCtrl.text) ?? 0.0;
    if (mrp <= 0) mrp = libraryMrp > 0 ? libraryMrp : purchasePrice;

    var sellingPrice = double.tryParse(_sellingPriceCtrl.text) ?? 0.0;
    if (sellingPrice <= 0) sellingPrice = mrp > 0 ? mrp : purchasePrice;
    final qty = int.tryParse(_qtyCtrl.text) ?? 0;

    Navigator.pop(context);

    bool success = false;
    if (med.pharmacyId.isEmpty) {
      // Adding global medicine to pharmacy local stock
      success = await invProvider.addMedicine(
        pharmacyId: pharmacyId,
        brandName: med.brandName,
        genericName: med.genericName,
        dosageForm: med.dosageForm,
        strength: med.strength,
        company: med.company,
        unit: med.unit,
        minStockAlert: 10,
        batchNumber: batchNum,
        expiryDate: _selectedExpDate,
        purchasePrice: purchasePrice,
        sellingPrice: sellingPrice,
        mrp: mrp,
        initialStock: qty,
      );
    } else {
      // Existing medicine in pharmacy inventory
      success = await invProvider.addBatch(
        pharmacyId: pharmacyId,
        medicineId: med.id,
        batchNumber: batchNum,
        expiryDate: _selectedExpDate,
        purchasePrice: purchasePrice,
        sellingPrice: sellingPrice,
        mrp: mrp,
        stockQty: qty,
      );
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? (med.pharmacyId.isEmpty
                  ? '${med.brandName} added to store stock successfully!'
                  : 'Batch $batchNum added successfully!')
              : 'Failed to save to stock',
        ),
        backgroundColor: success ? const Color(0xFF10B981) : Colors.red,
      ),
    );

    if (success) {
      widget.onSuccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    final med = widget.medicine;
    final gm = widget.matchingGlobalMedicine;
    final packInfo = MedicinePackagingHelper.getPackagingInfo(
      med: med,
      matchingGlobalMedicine: gm,
    );
    final double libraryMrp = packInfo['libraryMrp'] ?? 0.0;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            med.pharmacyId.isEmpty
                ? 'Stock In: ${med.brandName}'
                : 'Add Batch: ${med.brandName}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Text(
            '${med.dosageForm} • ${med.strength ?? ""}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (libraryMrp > 0)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 15, color: Color(0xFF1D4ED8)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Library MRP: ৳${libraryMrp.toStringAsFixed(2)} / unit (Auto-applied)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1D4ED8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: _batchNumCtrl,
              decoration: const InputDecoration(
                labelText: 'Batch Number',
                hintText: 'e.g. B-2026-01',
                prefixIcon: Icon(Icons.qr_code_rounded),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                await DatePickerHelper.pickMonthYear(
                  context: context,
                  initialDate: _selectedExpDate,
                  onSelected: (d) => setState(() => _selectedExpDate = d),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_rounded, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Text(
                      'Expiry: ${DateFormat('MM/yyyy').format(_selectedExpDate)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    const Text('Change', style: TextStyle(color: AppColors.primary)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _purchasePriceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Buy / Retail Rate (৳) *',
                      prefixText: '৳ ',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Quantity *',
                      suffixText: 'Units',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _mrpCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'MRP (৳)',
                      prefixText: '৳ ',
                      helperText: 'Auto from library',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _sellingPriceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Sell Rate (৳)',
                      prefixText: '৳ ',
                      helperText: 'Defaults to MRP',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _handleSave,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(widget.medicine.pharmacyId.isEmpty ? 'Save to Stock' : 'Save Batch'),
        ),
      ],
    );
  }
}
