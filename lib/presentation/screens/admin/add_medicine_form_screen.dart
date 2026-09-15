import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../data/services/supabase_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/inventory_provider.dart';

import '../../widgets/common/searchable_dropdown_field.dart';
import '../../widgets/common/medi_app_bar.dart';

class AddMedicineFormScreen extends StatefulWidget {
  final Map<String, dynamic>? medicineData; // If editing
  final bool isGlobalCatalog;
  final bool isSuggestionMode;

  const AddMedicineFormScreen({
    super.key,
    this.medicineData,
    this.isGlobalCatalog = true,
    this.isSuggestionMode = false,
  });

  @override
  State<AddMedicineFormScreen> createState() => _AddMedicineFormScreenState();
}

class _AddMedicineFormScreenState extends State<AddMedicineFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final SupabaseClient _supabase = SupabaseService.instance.client;

  // Controllers
  final TextEditingController _medicineNameCtrl = TextEditingController();
  final TextEditingController _genericNameCtrl = TextEditingController();
  final TextEditingController _companyNameCtrl = TextEditingController();
  final TextEditingController _medicineTypeCtrl = TextEditingController();
  final TextEditingController _baseUnitCtrl = TextEditingController(text: 'Piece');
  final TextEditingController _weightCtrl = TextEditingController();
  final TextEditingController _strengthCtrl = TextEditingController();
  final TextEditingController _mrpPriceCtrl = TextEditingController();
  final TextEditingController _piecesPerStripCtrl = TextEditingController();
  final TextEditingController _stripsPerBoxCtrl = TextEditingController();



  // Focus Nodes
  final FocusNode _genericFocus = FocusNode();
  final FocusNode _typeFocus = FocusNode();
  final FocusNode _companyFocus = FocusNode();
  final FocusNode _unitFocus = FocusNode();

  bool _isSaving = false;
  bool _canExit = false;

  Future<bool> _showExitConfirmationDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 10),
            Text('Discard Changes?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text(
          'Are you sure you want to exit without saving?\nAny unsaved medicine information will be lost.\n\n(আপনি কি নিশ্চিত যে সেভ না করে বের হতে চান? লেখা তথ্য মুছে যাবে।)',
          style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No, Keep Editing', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Exit', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _handleBackPress() async {
    if (_isSaving) return;
    final shouldExit = await _showExitConfirmationDialog();
    if (shouldExit && mounted) {
      setState(() => _canExit = true);
      Navigator.of(context).pop();
    }
  }

  // Search states for Company
  List<Map<String, dynamic>> _companySearchResults = [];
  bool _isSearchingCompany = false;
  String? _selectedCompanyId;

  // Search states for Generic Name
  List<String> _genericSearchResults = [];
  bool _isSearchingGeneric = false;
  bool _genericSelected = false;

  // Search states for Dosage Form / Type
  List<String> _typeSearchResults = [];
  bool _isSearchingType = false;
  bool _typeSelected = false;

  // Search states for Base Unit
  List<String> _unitSearchResults = [];
  bool _isSearchingUnit = false;
  bool _unitSelected = false;

  final List<String> _standardTypes = [
    'Tablet',
    'Capsule',
    'Syrup',
    'Suspension',
    'Injection',
    'Ointment',
    'Cream',
    'Gel',
    'Eye Drops',
    'Ear Drops',
    'Inhaler',
    'Saline / Sachet',
    'Suppository',
    'Diaper',
    'Sanitary Napkin',
    'Surgical / Cotton',
    'Powder / Sachet',
    'Lotion',
    'Solution',
  ];

  final List<String> _standardUnits = [
    'Piece',
    'Strip',
    'Box',
    'Bottle',
    'Tube',
    'Vial',
    'Ampoule',
    'Packet',
    'Sachet',
    'Roll',
    'Canister',
    'Pouch',
  ];

  bool get _isEditMode => widget.medicineData != null;

  @override
  void initState() {
    super.initState();

    // Edit mode prefill
    if (widget.medicineData != null) {
      final data = widget.medicineData!;
      _medicineNameCtrl.text = data['brand_name'] ?? data['medicine_name'] ?? '';
      _genericNameCtrl.text = data['generic_name'] ?? '';
      final form = (data['dosage_form'] ?? data['medicine_type'] ?? '').toString().trim();
      _medicineTypeCtrl.text = form;

      String rawStrength = (data['strength'] ?? '').toString().trim();
      rawStrength = rawStrength.replaceAll(RegExp(r'\[MRP:\s*[৳$]?\s*\d+(?:\.\d+)?\]', caseSensitive: false), '').trim();
      String rawWeight = (data['weight'] ?? '').toString().trim();
      String? parsedPps;
      String? parsedSpb;

      // Extract pack-size pattern like "(6*5)", "(15*10)", or "(1*25)" strictly from strength
      final packPattern = RegExp(
        r'[\(\[]\s*(\d+)\s*[*xX×]\s*(\d+)(?:\x27?s|\s*pcs)?\s*[\)\]]',
        caseSensitive: false,
      );
      final singlePackPattern = RegExp(
        r'[\(\[]\s*(\d+)(?:\x27?s|\s*pcs|\s*pack|\s*tabs|\s*caps)\s*[\)\]]',
        caseSensitive: false,
      );

      final packMatch = packPattern.firstMatch(rawStrength);
      if (packMatch != null) {
        final spbVal = packMatch.group(1)!.trim();
        final ppsVal = packMatch.group(2)!.trim();
        if (spbVal == '1') {
          parsedPps = ppsVal;
          parsedSpb = '';
        } else {
          parsedSpb = spbVal;
          parsedPps = ppsVal;
        }
        rawStrength = rawStrength.replaceFirst(packPattern, '').trim();
      } else {
        final singleMatch = singlePackPattern.firstMatch(rawStrength);
        if (singleMatch != null) {
          parsedPps = singleMatch.group(1)!.trim();
          parsedSpb = '';
          rawStrength = rawStrength.replaceFirst(singlePackPattern, '').trim();
        }
      }

      // Only clear rawWeight if it purely contains pack numbers like (10*10)
      if (rawWeight.isNotEmpty &&
          RegExp(r'^[\(\[]?\s*\d+\s*[*xX×]\s*\d+\s*[\)\]]?$').hasMatch(rawWeight)) {
        rawWeight = '';
      }

      // Extract pure volume/weight from strength or notes if rawWeight is empty
      if (rawWeight.isEmpty && data['notes'] != null) {
        final wMatch = RegExp(r'Weight:\s*([^,|]+)', caseSensitive: false).firstMatch(data['notes'].toString());
        if (wMatch != null) {
          final w = wMatch.group(1)!.trim();
          if (w.isNotEmpty && w.toLowerCase() != 'null') {
            rawWeight = w;
          }
        }
      }

      rawWeight = rawWeight.replaceAll(RegExp(r'[\(\)\[\]]'), '').trim();

      // Extract volume/weight in parentheses from rawStrength: e.g. "1% (10.25 gm)" or "(10.25 gm)"
      final volInParens = RegExp(
        r'^(.*?)\s*[\(\[]\s*([^()\[\]]+?(?:ml|gm|g|l|kg|pads?|sachets?|tubes?|drops?|spray)[^()\[\]]*)\s*[\)\]]$',
        caseSensitive: false,
      ).firstMatch(rawStrength);

      if (volInParens != null) {
        final prefix = volInParens.group(1)!.trim();
        final extractedWt = volInParens.group(2)!.trim();
        if (rawWeight.isEmpty) {
          rawWeight = extractedWt.replaceAll(RegExp(r'[\(\)\[\]]'), '').trim();
        }
        rawStrength = prefix; // If only weight in parens, prefix is empty!
      }

      // If rawStrength is purely a weight/volume without parentheses (e.g. "10.25 gm", "100 ml", "15 g"):
      final exactVol = RegExp(
        r'^\d+(?:\.\d+)?\s*(?:ml|gm|g|l|kg|pads?|sachets?|tubes?|drops?|spray)$',
        caseSensitive: false,
      ).firstMatch(rawStrength);

      if (exactVol != null) {
        if (rawWeight.isEmpty) {
          rawWeight = rawStrength;
        }
        rawStrength = ''; // It is purely a weight, NOT a strength!
      }

      // If rawStrength equals rawWeight, clear rawStrength so it is not shown as strength
      if (rawStrength.isNotEmpty && rawWeight.isNotEmpty) {
        final cleanS = rawStrength.toLowerCase().trim().replaceAll(RegExp(r'[\(\)\[\]]'), '');
        final cleanW = rawWeight.toLowerCase().trim().replaceAll(RegExp(r'[\(\)\[\]]'), '');
        if (cleanS == cleanW || cleanS == cleanW.replaceAll(' ', '')) {
          rawStrength = '';
        }
      }

      // Unwrap outer parentheses if entire strength is enclosed like "(120 mg)" or "(500 mg)"
      if (rawStrength.startsWith('(') && rawStrength.endsWith(')')) {
        final inner = rawStrength.substring(1, rawStrength.length - 1).trim();
        if (!inner.contains('(') && !inner.contains(')')) {
          rawStrength = inner;
        }
      }

      // Only clear rawStrength if it was solely a pack ratio like "(10*10)" or "10*10" or pure numbers with no unit
      final purePackPattern = RegExp(r'^[\(\[]?\s*\d+\s*[*xX×]\s*\d+.*[\)\]]?$|^[\(\[]?\s*\d+(?:\x27?s|\s*pcs|\s*pack)?\s*[\)\]]?$', caseSensitive: false);
      if (purePackPattern.hasMatch(rawStrength) || RegExp(r'^\d+$').hasMatch(rawStrength)) {
        rawStrength = '';
      }

      _strengthCtrl.text = rawStrength;
      _weightCtrl.text = rawWeight;
      String resolvedMrp = (data['default_mrp'] ?? data['mrp_price'] ?? data['mrp'] ?? data['price'] ?? data['catalog_price'] ?? '').toString();
      if ((resolvedMrp.isEmpty || resolvedMrp == '0' || resolvedMrp == '0.0') && data['notes'] != null) {
        final mrpMatch = RegExp(r'MRP:\s*[৳$]?\s*(\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(data['notes'].toString());
        if (mrpMatch != null) {
          resolvedMrp = mrpMatch.group(1)!;
        }
      }
      if ((resolvedMrp.isEmpty || resolvedMrp == '0' || resolvedMrp == '0.0') && data['strength'] != null) {
        final mrpMatch = RegExp(r'\[MRP:\s*[৳$]?\s*(\d+(?:\.\d+)?)\]', caseSensitive: false).firstMatch(data['strength'].toString());
        if (mrpMatch != null) {
          resolvedMrp = mrpMatch.group(1)!;
        }
      }
      if ((resolvedMrp.isEmpty || resolvedMrp == '0' || resolvedMrp == '0.0') && data['batches'] != null && data['batches'] is List) {
        for (final b in (data['batches'] as List)) {
          final bm = b['mrp'] ?? b['selling_price'];
          if (bm != null && bm.toString() != '0' && bm.toString() != '0.0' && bm.toString().isNotEmpty) {
            resolvedMrp = bm.toString();
            break;
          }
        }
      }
      _mrpPriceCtrl.text = (resolvedMrp == '0' || resolvedMrp == '0.0') ? '' : resolvedMrp;

      String defaultUnit = data['default_unit'] ?? data['unit'] ?? 'Piece';
      if ((defaultUnit.isEmpty || defaultUnit == 'Piece') && data['notes'] != null) {
        final buMatch = RegExp(r'Base Unit:\s*([^,\s|]+)', caseSensitive: false).firstMatch(data['notes'].toString());
        if (buMatch != null) {
          defaultUnit = buMatch.group(1)!.trim();
        }
      }
      _baseUnitCtrl.text = defaultUnit;

      // Packaging fields: use explicit DB values, or parsed values from strength
      final dbPps = (data['pieces_per_strip'] ?? '').toString().trim();
      final dbSpb = (data['strips_per_box'] ?? '').toString().trim();
      final dbWeight = (data['weight'] ?? '').toString().trim();

      if (dbPps.isNotEmpty && dbPps != 'null') {
        _piecesPerStripCtrl.text = dbPps;
        _stripsPerBoxCtrl.text = (dbSpb != 'null' && dbSpb.isNotEmpty) ? dbSpb : '';
      } else if (parsedPps != null && parsedPps.isNotEmpty) {
        _piecesPerStripCtrl.text = parsedPps;
        _stripsPerBoxCtrl.text = parsedSpb ?? '';
      } else {
        _piecesPerStripCtrl.text = '';
        _stripsPerBoxCtrl.text = '';
      }

      if (_piecesPerStripCtrl.text.isEmpty && data['notes'] != null) {
        final ppsMatch = RegExp(r'(\d+)\s*(?:pcs|piece|pieces)?\s*\/\s*strip', caseSensitive: false).firstMatch(data['notes'].toString());
        if (ppsMatch != null) {
          _piecesPerStripCtrl.text = ppsMatch.group(1)!;
        }
      }
      if (_stripsPerBoxCtrl.text.isEmpty && data['notes'] != null) {
        final spbMatch = RegExp(r'(\d+)\s*(?:strips?|units?|box)?\s*\/\s*box', caseSensitive: false).firstMatch(data['notes'].toString());
        if (spbMatch != null) {
          _stripsPerBoxCtrl.text = spbMatch.group(1)!;
        }
      }

      if (dbWeight.isNotEmpty && dbWeight != 'null') {
        _weightCtrl.text = dbWeight.replaceAll(RegExp(r'[\(\)\[\]]'), '').trim();
      } else if (_weightCtrl.text.isEmpty && data['notes'] != null) {
        final wtMatch = RegExp(r'Weight:\s*([^,|]+)', caseSensitive: false).firstMatch(data['notes'].toString());
        if (wtMatch != null) {
          final wVal = wtMatch.group(1)!.trim();
          if (wVal.isNotEmpty && wVal.toLowerCase() != 'null') {
            _weightCtrl.text = wVal;
          }
        }
      }

      if (data['company'] != null) {
        _companyNameCtrl.text = data['company'].toString();
      } else if (data['company_name'] != null) {
        _companyNameCtrl.text = data['company_name'].toString();
      }

      if (_genericNameCtrl.text.isNotEmpty) _genericSelected = true;
      if (_medicineTypeCtrl.text.isNotEmpty) _typeSelected = true;
      if (_baseUnitCtrl.text.isNotEmpty) _unitSelected = true;
    }
  }

  @override
  void dispose() {
    _medicineNameCtrl.dispose();
    _genericNameCtrl.dispose();
    _companyNameCtrl.dispose();
    _medicineTypeCtrl.dispose();
    _baseUnitCtrl.dispose();
    _weightCtrl.dispose();
    _strengthCtrl.dispose();
    _mrpPriceCtrl.dispose();
    _piecesPerStripCtrl.dispose();
    _stripsPerBoxCtrl.dispose();

    _genericFocus.dispose();
    _typeFocus.dispose();
    _companyFocus.dispose();
    _unitFocus.dispose();
    super.dispose();
  }

  // ── COMPANY SEARCH ──────────────────────────────────────────────────────────
  Future<void> _searchCompany(String query) async {
    if (_selectedCompanyId != null) {
      setState(() => _selectedCompanyId = null);
    }
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _companySearchResults = [];
        _isSearchingCompany = false;
      });
      return;
    }
    setState(() => _isSearchingCompany = true);

    final Set<String> uniqueCompanies = {};
    final pharmacyId = context.read<AuthProvider>().currentProfile?.pharmacyId;

    // 1. Fetch from user's own store medicines (private suggestion for this store only)
    if (pharmacyId != null && pharmacyId.isNotEmpty) {
      try {
        final localData = await _supabase
            .from('medicines')
            .select('company')
            .eq('pharmacy_id', pharmacyId)
            .ilike('company', '%$q%')
            .limit(8);
        for (var item in localData) {
          final comp = item['company']?.toString().trim();
          if (comp != null && comp.isNotEmpty) {
            uniqueCompanies.add(comp);
          }
        }
      } catch (_) {}
    }

    // 2. Fetch from global company table
    try {
      final globalData = await _supabase
          .from('company')
          .select('company_id, company_name')
          .ilike('company_name', '%$q%')
          .order('company_name')
          .limit(8);
      for (var item in globalData) {
        final name = item['company_name']?.toString().trim();
        if (name != null && name.isNotEmpty) {
          uniqueCompanies.add(name);
        }
      }
    } catch (_) {
      try {
        final data = await _supabase
            .from('global_medicines')
            .select('company')
            .ilike('company', '%$q%')
            .limit(8);
        for (var item in data) {
          final comp = item['company']?.toString().trim();
          if (comp != null && comp.isNotEmpty) {
            uniqueCompanies.add(comp);
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _companySearchResults = uniqueCompanies
          .map((name) => {'company_name': name})
          .toList();
      _isSearchingCompany = false;
    });
  }

  // ── GENERIC SEARCH ──────────────────────────────────────────────────────────
  Future<void> _searchGeneric(String query) async {
    if (_genericSelected) setState(() => _genericSelected = false);
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _genericSearchResults = [];
        _isSearchingGeneric = false;
      });
      return;
    }
    setState(() => _isSearchingGeneric = true);

    final Set<String> uniqueGenerics = {};
    final pharmacyId = context.read<AuthProvider>().currentProfile?.pharmacyId;

    // 1. Fetch from user's own store medicines (private suggestion for this store only)
    if (pharmacyId != null && pharmacyId.isNotEmpty) {
      try {
        final localData = await _supabase
            .from('medicines')
            .select('generic_name')
            .eq('pharmacy_id', pharmacyId)
            .ilike('generic_name', '%$q%')
            .limit(8);
        for (var item in localData) {
          final gen = item['generic_name']?.toString().trim();
          if (gen != null && gen.isNotEmpty) {
            uniqueGenerics.add(gen);
          }
        }
      } catch (_) {}
    }

    // 2. Fetch from global generic_names table
    try {
      final globalData = await _supabase
          .from('generic_names')
          .select('generic_name')
          .ilike('generic_name', '%$q%')
          .order('generic_name')
          .limit(8);
      for (var item in globalData) {
        final name = item['generic_name']?.toString().trim();
        if (name != null && name.isNotEmpty) {
          uniqueGenerics.add(name);
        }
      }
    } catch (_) {
      try {
        final data = await _supabase
            .from('global_medicines')
            .select('generic_name')
            .ilike('generic_name', '%$q%')
            .limit(8);
        for (var item in data) {
          final gen = item['generic_name']?.toString().trim();
          if (gen != null && gen.isNotEmpty) {
            uniqueGenerics.add(gen);
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _genericSearchResults = uniqueGenerics.toList();
      _isSearchingGeneric = false;
    });
  }

  // â”€â”€ MEDICINE TYPE / DOSAGE FORM SEARCH â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _searchType(String query) async {
    if (_typeSelected) setState(() => _typeSelected = false);
    if (query.trim().isEmpty) {
      setState(() {
        _typeSearchResults = _standardTypes.take(8).toList();
        _isSearchingType = false;
      });
      return;
    }

    final Set<String> matches = {};
    for (var t in _standardTypes) {
      if (t.toLowerCase().contains(query.toLowerCase().trim())) {
        matches.add(t);
      }
    }

    // Also search distinct from database
    try {
      final data = await _supabase
          .from('global_medicines')
          .select('dosage_form')
          .ilike('dosage_form', '%$query%')
          .limit(8);
      for (var row in data) {
        if (row['dosage_form'] != null && row['dosage_form'].toString().isNotEmpty) {
          matches.add(row['dosage_form'].toString());
        }
      }
    } catch (_) {}

    setState(() {
      _typeSearchResults = matches.toList();
      _isSearchingType = false;
    });
  }

  // â”€â”€ BASE UNIT SEARCH â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _searchUnit(String query) async {
    if (_unitSelected) setState(() => _unitSelected = false);
    if (query.trim().isEmpty) {
      setState(() {
        _unitSearchResults = _standardUnits.take(8).toList();
        _isSearchingUnit = false;
      });
      return;
    }

    final Set<String> matches = {};
    for (var u in _standardUnits) {
      if (u.toLowerCase().contains(query.toLowerCase().trim())) {
        matches.add(u);
      }
    }

    // Also search distinct from database
    try {
      final data = await _supabase
          .from('global_medicines')
          .select('default_unit')
          .ilike('default_unit', '%$query%')
          .limit(8);
      for (var row in data) {
        if (row['default_unit'] != null && row['default_unit'].toString().isNotEmpty) {
          matches.add(row['default_unit'].toString());
        }
      }
    } catch (_) {}

    setState(() {
      _unitSearchResults = matches.toList();
      _isSearchingUnit = false;
    });
  }

  // â”€â”€ SAVE HANDLER â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final isSuperAdmin = auth.currentProfile?.isSuperAdmin ?? false;

    setState(() => _isSaving = true);

    try {
      final String brand = _medicineNameCtrl.text.trim();
      final String generic = _genericNameCtrl.text.trim();
      final String company = _companyNameCtrl.text.trim();
      final String dosageForm = _medicineTypeCtrl.text.trim();
      final String baseUnit = _baseUnitCtrl.text.trim().isEmpty ? 'Piece' : _baseUnitCtrl.text.trim();
      final double mrp = double.tryParse(_mrpPriceCtrl.text.trim()) ?? 0.0;
      final int? piecesPerStrip = int.tryParse(_piecesPerStripCtrl.text.trim());
      final int? stripsPerBox = int.tryParse(_stripsPerBoxCtrl.text.trim());

      final messenger = ScaffoldMessenger.of(context);

      final str = _strengthCtrl.text.trim();
      final wt = _weightCtrl.text.trim();
      String? effectiveStrength;
      String? effectiveWeight;

      // Check if wt is a pack-size pattern like "6*5", "6x5", "6×5"
      final packSizeMatch = RegExp(r'^(\d+)\s*[*xX×]\s*(\d+)$').firstMatch(wt);

      if (packSizeMatch != null) {
        // Pack-size notation detected — parse into packaging fields, NOT strength
        effectiveStrength = str.isNotEmpty ? str : null;
        effectiveWeight = null; // Not a weight/volume value
      } else {
        // Normal weight/volume value (e.g. "60 ml", "15g") or empty
        effectiveStrength = str.isNotEmpty ? str : null;
        effectiveWeight = wt.isNotEmpty ? wt : null;
      }

      // Pure data-driven packaging normalization:
      int? effectivePps = piecesPerStrip;
      int? effectiveSpb = stripsPerBox;

      if (effectiveSpb == 1) {
        effectiveSpb = null;
      }
      if (effectivePps == 1 && effectiveSpb != null && effectiveSpb > 1) {
        effectivePps = effectiveSpb;
        effectiveSpb = null;
      } else if (effectivePps == 1 && (effectiveSpb == null || effectiveSpb <= 1)) {
        effectivePps = null;
        effectiveSpb = null;
      }

      if (effectivePps != null && effectivePps > 1 && effectiveSpb != null && effectiveSpb > 1) {
        // Both two-tier pack values present (e.g. 10 strips of 10 pieces, suppository 6*5)
      } else if ((effectivePps == null || effectivePps <= 1) && (effectiveSpb != null && effectiveSpb > 1)) {
        // Only one box entered -> treat as single pack quantity
        effectivePps = effectiveSpb;
        effectiveSpb = null;
      } else if (effectivePps != null && effectivePps > 1 && (effectiveSpb == null || effectiveSpb <= 1)) {
        effectiveSpb = null;
      } else {
        effectivePps = null;
        effectiveSpb = null;
      }

      // Strip previous pack tags and parenthesized weights from effectiveStrength and effectiveWeight
      final packPattern = RegExp(r'\s*[\(\[]?\s*\d+\s*[*xX×]\s*\d+\s*[\)\]]?');
      final singlePackPattern = RegExp(r'\s*[\(\[]\s*\d+(?:\x27?s|\s*pcs|\s*pack)?\s*[\)\]]', caseSensitive: false);

      String cleanStrength = (effectiveStrength ?? '')
          .replaceAll(packPattern, '')
          .replaceAll(singlePackPattern, '')
          .trim();
      String cleanWeight = (effectiveWeight ?? '')
          .replaceAll(packPattern, '')
          .replaceAll(singlePackPattern, '')
          .trim();



      final isGlobalSave = widget.isGlobalCatalog || isSuperAdmin;

      if (isGlobalSave) {
        // --- 1. GLOBAL CATALOG MODE (ADMIN) ---
        final Map<String, dynamic> dataToSave = {
          'brand_name': brand,
          'generic_name': generic.isEmpty ? null : generic,
          'company': company.isEmpty ? null : company,
          'dosage_form': dosageForm.isEmpty ? null : dosageForm,
          'strength': cleanStrength.isNotEmpty ? cleanStrength : null,
          'weight': cleanWeight.isNotEmpty ? cleanWeight : null,
          'pieces_per_strip': effectivePps,
          'strips_per_box': effectiveSpb,
          'default_unit': baseUnit,
          'default_mrp': mrp > 0 ? mrp : null,
        };

        final requestId = widget.medicineData?['request_id'];
        final notes = (widget.medicineData?['notes'] ?? '').toString();
        final rawId = widget.medicineData?['id']?.toString();
        final cleanId = rawId?.replaceFirst('global_', '');

        // Resolve real global_medicines ID
        String? targetGlobalId = widget.medicineData?['global_id']?.toString();
        if (targetGlobalId == null || targetGlobalId.isEmpty || targetGlobalId == 'null') {
          final match = RegExp(r'GlobalMedId:([^\s|]+)').firstMatch(notes);
          if (match != null && match.group(1) != 'null') {
            targetGlobalId = match.group(1);
          }
        }
        if (requestId == null && (targetGlobalId == null || targetGlobalId.isEmpty)) {
          targetGlobalId = cleanId;
        }

        String? newGlobalId;

        try {
          bool updated = false;
          if (targetGlobalId != null && targetGlobalId.isNotEmpty && targetGlobalId != 'null') {
            final res = await _supabase
                .from('global_medicines')
                .update(dataToSave)
                .eq('id', targetGlobalId)
                .select('id');
            if ((res as List).isNotEmpty) {
              updated = true;
              newGlobalId = targetGlobalId;
            }
          }

          if (!updated) {
            var q = _supabase
                .from('global_medicines')
                .update(dataToSave)
                .ilike('brand_name', brand);
            if (dosageForm.isNotEmpty) {
              q = q.ilike('dosage_form', dosageForm);
            }
            final res = await q.select('id');
            if ((res as List).isNotEmpty) {
              updated = true;
              newGlobalId = res.first['id']?.toString();
            }
          }

          if (!updated) {
            final res = await _supabase.from('global_medicines').insert(dataToSave).select('id').single();
            newGlobalId = res['id']?.toString();
            updated = true;
          }

          // Sync updated packaging, price, weight and unit to existing local copies of this medicine
          try {
            final localSync = <String, dynamic>{
              'brand_name': brand,
              if (generic.isNotEmpty) 'generic_name': generic,
              if (company.isNotEmpty) 'company': company,
              'dosage_form': dosageForm.isEmpty ? null : dosageForm,
              'strength': cleanStrength.isNotEmpty ? cleanStrength : null,
              'weight': cleanWeight.isNotEmpty ? cleanWeight : null,
              'pieces_per_strip': effectivePps,
              'strips_per_box': effectiveSpb,
              'unit': baseUnit,
              if (mrp > 0) 'catalog_price': mrp,
            };
            if (newGlobalId != null && newGlobalId.isNotEmpty) {
              localSync['global_id'] = newGlobalId;
              await _supabase.from('medicines').update(localSync).eq('global_id', newGlobalId);
            }
            final oldBrand = widget.medicineData?['brand_name']?.toString() ?? brand;
            var localMedQuery = _supabase.from('medicines').update(localSync).ilike('brand_name', oldBrand);
            if (dosageForm.isNotEmpty) {
              localMedQuery = localMedQuery.ilike('dosage_form', dosageForm);
            }
            await localMedQuery;
          } catch (err) {
            debugPrint('Silent sync to local medicines: $err');
          }

          // 1. If editing a request or suggestion, ALWAYS update request status to 'approved' FIRST!
          final isRequestData = widget.medicineData != null && widget.medicineData!['status'] != null;
          final actualReqId = requestId ?? (isRequestData ? widget.medicineData!['id']?.toString() : null);

          if (actualReqId != null && actualReqId.isNotEmpty) {
            try {
              await _supabase.from('medicine_requests').update({
                'status': 'approved',
                'brand_name': brand,
                'generic_name': generic.isEmpty ? null : generic,
                'dosage_form': dosageForm,
                'strength': cleanStrength.isNotEmpty ? cleanStrength : null,
                'weight': cleanWeight.isNotEmpty ? cleanWeight : null,
                'pieces_per_strip': effectivePps,
                'strips_per_box': effectiveSpb,
                'unit': baseUnit,
                if (mrp > 0) 'catalog_price': mrp,
                'company': company.isEmpty ? null : company,
                'admin_remarks': 'Approved into Global Catalog via Full Editor',
              }).eq('id', actualReqId);
              debugPrint('Marked medicine request $actualReqId as approved! ✅');
            } catch (reqErr) {
              debugPrint('Error with full request update, falling back to minimal: $reqErr');
              try {
                await _supabase.from('medicine_requests').update({
                  'status': 'approved',
                  'admin_remarks': 'Approved into Global Catalog via Full Editor',
                }).eq('id', actualReqId);
              } catch (fallbackErr) {
                debugPrint('Fallback request approval error: $fallbackErr');
              }
            }
          }

          // Also auto-approve any other pending requests targeting this global medicine
          if (newGlobalId != null && newGlobalId.isNotEmpty) {
            try {
              await _supabase.from('medicine_requests').update({
                'status': 'approved',
                'admin_remarks': 'Auto-approved via Global Catalog Update',
              }).ilike('notes', '%GlobalMedId:$newGlobalId%').eq('status', 'pending');
            } catch (err) {
              debugPrint('Silent auto-approval for pending suggestions: $err');
            }
          }

          // 2. In a separate isolated try-catch, silently link requesting pharmacy's medicine
          try {
            final reqPharmacyId = widget.medicineData?['pharmacy_id']?.toString();

            if (reqPharmacyId != null && reqPharmacyId.isNotEmpty && newGlobalId != null) {
              String? localMedId;
              final match = RegExp(r'LocalMedId:([^\s|]+)').firstMatch(notes);
              if (match != null) localMedId = match.group(1);

              final pharmacyMedUpdate = <String, dynamic>{
                'global_id': newGlobalId,
                'brand_name': brand,
                if (generic.isNotEmpty) 'generic_name': generic,
                if (company.isNotEmpty) 'company': company,
                if (dosageForm.isNotEmpty) 'dosage_form': dosageForm,
                'strength': cleanStrength.isNotEmpty ? cleanStrength : null,
                'weight': cleanWeight.isNotEmpty ? cleanWeight : null,
                'unit': baseUnit,
                'pieces_per_strip': effectivePps,
                'strips_per_box': effectiveSpb,
                if (mrp > 0) 'catalog_price': mrp,
              };

              if (localMedId != null && localMedId.isNotEmpty) {
                await _supabase
                    .from('medicines')
                    .update(pharmacyMedUpdate)
                    .eq('id', localMedId)
                    .eq('pharmacy_id', reqPharmacyId);
              } else {
                final oldBrand = widget.medicineData?['brand_name']?.toString() ?? brand;
                var pMedQuery = _supabase
                    .from('medicines')
                    .update(pharmacyMedUpdate)
                    .eq('pharmacy_id', reqPharmacyId)
                    .ilike('brand_name', oldBrand);
                if (dosageForm.isNotEmpty) {
                  pMedQuery = pMedQuery.ilike('dosage_form', dosageForm);
                }
                await pMedQuery;
              }
            }
          } catch (err) {
            debugPrint('Silent sync for requesting pharmacy medicine: $err');
          }
        } catch (e) {
          debugPrint('Error updating global_medicines: $e');
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(
              content: Text('Failed to update: ${ErrorFormatter.format(e)}'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(_isEditMode ? 'Updated $brand successfully! ✅' : '$brand added to Global Master Catalog! ✅'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
        setState(() => _canExit = true);
        Navigator.pop(context, true);
      } else if (widget.isSuggestionMode) {
        // --- 2. SUGGESTION MODE: SUBMIT GLOBAL MEDICINE EDIT SUGGESTION TO ADMIN ---
        final pharmacyId = auth.currentProfile?.pharmacyId;
        final uid = auth.currentProfile?.id ?? _supabase.auth.currentUser?.id;

        if (pharmacyId == null || pharmacyId.isEmpty) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Error: No pharmacy linked to current user'), backgroundColor: Colors.red),
          );
          return;
        }

        final rawId = widget.medicineData?['global_id'] ?? widget.medicineData?['id'];
        final cleanGlobalId = rawId?.toString().replaceFirst('global_', '');
        final localMedId = widget.medicineData?['id']?.toString();
        final hasLocalId = localMedId != null && localMedId.isNotEmpty && !localMedId.startsWith('global_');

        // Immediately update user's local inventory if they already have this medicine in stock
        if (hasLocalId) {
          try {
            await _supabase.from('medicines').update({
              'brand_name': brand,
              'generic_name': generic.isEmpty ? null : generic,
              'company': company.isEmpty ? null : company,
              'dosage_form': dosageForm.isEmpty ? null : dosageForm,
              'strength': cleanStrength.isNotEmpty ? cleanStrength : null,
              'weight': cleanWeight.isNotEmpty ? cleanWeight : null,
              'pieces_per_strip': effectivePps,
              'strips_per_box': effectiveSpb,
              'unit': baseUnit,
              if (mrp > 0) 'catalog_price': mrp,
            }).eq('id', localMedId).eq('pharmacy_id', pharmacyId);
          } catch (err) {
            debugPrint('Local medicine update in suggestion mode: $err');
          }
        }

        await _supabase.from('medicine_requests').insert({
          'pharmacy_id': pharmacyId,
          'requested_by': uid,
          'brand_name': brand,
          'generic_name': generic.isEmpty ? null : generic,
          'company': company.isEmpty ? null : company,
          'dosage_form': dosageForm.isEmpty ? null : dosageForm,
          'strength': cleanStrength.isNotEmpty ? cleanStrength : null,
          'weight': cleanWeight.isNotEmpty ? cleanWeight : null,
          'pieces_per_strip': effectivePps,
          'strips_per_box': effectiveSpb,
          'unit': baseUnit,
          if (mrp > 0) 'catalog_price': mrp,
          'notes': 'Type:Suggestion | GlobalMedId:$cleanGlobalId | LocalMedId:${hasLocalId ? localMedId : ''} | Packaging: $effectivePps pcs/strip, $effectiveSpb units/box, Weight: ${effectiveWeight ?? ''}, Base Unit: $baseUnit, MRP: ৳$mrp',
          'status': 'pending',
        });

        if (mounted) {
          try {
            context.read<InventoryProvider>().loadMedicines();
          } catch (_) {}
        }

        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text('Changes saved locally & edit suggestion for "$brand" submitted to Admin! ✅'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _canExit = true);
        Navigator.pop(context, true);
      } else {
        // --- 3. PHARMACY USER: ADD LOCALLY + AUTO SUBMIT REQUEST TO ADMIN ---
        final pharmacyId = auth.currentProfile?.pharmacyId;
        final uid = auth.currentProfile?.id ?? _supabase.auth.currentUser?.id;

        if (pharmacyId == null || pharmacyId.isEmpty) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Error: No pharmacy linked to current user'), backgroundColor: Colors.red),
          );
          return;
        }

        if (_isEditMode && widget.medicineData?['id'] != null) {
          final medId = widget.medicineData!['id'].toString();
          await _supabase.from('medicines').update({
            'brand_name': brand,
            'generic_name': generic.isEmpty ? null : generic,
            'company': company.isEmpty ? null : company,
            'dosage_form': dosageForm.isEmpty ? null : dosageForm,
            'strength': cleanStrength.isNotEmpty ? cleanStrength : null,
            'weight': cleanWeight.isNotEmpty ? cleanWeight : null,
            'pieces_per_strip': effectivePps,
            'strips_per_box': effectiveSpb,
            'unit': baseUnit,
            if (mrp > 0) 'catalog_price': mrp,
          }).eq('id', medId);

          // Also sync changes to any pending request for this medicine so Admin sees updated info
          try {
            final updatedReqs = await _supabase.from('medicine_requests').update({
              'brand_name': brand,
              'generic_name': generic.isEmpty ? null : generic,
              'company': company.isEmpty ? null : company,
              'dosage_form': dosageForm.isEmpty ? null : dosageForm,
              'strength': cleanStrength.isNotEmpty ? cleanStrength : null,
              'weight': cleanWeight.isNotEmpty ? cleanWeight : null,
              'pieces_per_strip': effectivePps,
              'strips_per_box': effectiveSpb,
              'unit': baseUnit,
              if (mrp > 0) 'catalog_price': mrp,
              'notes': 'LocalMedId:$medId | Packaging: $effectivePps pcs/strip, $effectiveSpb units/box, Weight: ${effectiveWeight ?? ''}, Base Unit: $baseUnit, MRP: ৳$mrp',
            }).eq('pharmacy_id', pharmacyId).eq('status', 'pending').ilike('notes', '%LocalMedId:$medId%').select('id');

            // Fallback: If no request matched LocalMedId in notes, try matching by old brand name
            if ((updatedReqs as List).isEmpty) {
              final oldBrand = (widget.medicineData?['brand_name'] ?? widget.medicineData?['medicine_name'])?.toString().trim();
              if (oldBrand != null && oldBrand.isNotEmpty) {
                var fallbackReqQuery = _supabase.from('medicine_requests').update({
                  'brand_name': brand,
                  'generic_name': generic.isEmpty ? null : generic,
                  'company': company.isEmpty ? null : company,
                  'dosage_form': dosageForm.isEmpty ? null : dosageForm,
                  'strength': cleanStrength.isNotEmpty ? cleanStrength : null,
                  'weight': cleanWeight.isNotEmpty ? cleanWeight : null,
                  'pieces_per_strip': effectivePps,
                  'strips_per_box': effectiveSpb,
                  'unit': baseUnit,
                  if (mrp > 0) 'catalog_price': mrp,
                  'notes': 'LocalMedId:$medId | Packaging: $effectivePps pcs/strip, $effectiveSpb units/box, Weight: ${effectiveWeight ?? ''}, Base Unit: $baseUnit, MRP: ৳$mrp',
                }).eq('pharmacy_id', pharmacyId).eq('status', 'pending').ilike('brand_name', oldBrand);

                final oldDosage = (widget.medicineData?['dosage_form'] ?? widget.medicineData?['medicine_type'] ?? dosageForm)?.toString().trim() ?? '';
                if (oldDosage.isNotEmpty) {
                  fallbackReqQuery = fallbackReqQuery.ilike('dosage_form', oldDosage);
                }
                await fallbackReqQuery;
              }
            }
          } catch (err) {
            debugPrint('Silent update of pending medicine_request: $err');
          }

          if (mrp > 0) {
            try {
              final batches = await _supabase
                  .from('batches')
                  .select('id')
                  .eq('medicine_id', medId);
              if (batches.isNotEmpty) {
                await _supabase
                    .from('batches')
                    .update({'mrp': mrp, 'selling_price': mrp})
                    .eq('id', batches.first['id']);
              }
            } catch (_) {}
          }
        } else {
          // A. Insert into pharmacy's local medicines table
          final localMed = await _supabase.from('medicines').insert({
            'pharmacy_id': pharmacyId,
            'brand_name': brand,
            'generic_name': generic.isEmpty ? null : generic,
            'company': company.isEmpty ? null : company,
            'dosage_form': dosageForm.isEmpty ? null : dosageForm,
            'strength': cleanStrength.isNotEmpty ? cleanStrength : null,
            'weight': cleanWeight.isNotEmpty ? cleanWeight : null,
            'pieces_per_strip': effectivePps,
            'strips_per_box': effectiveSpb,
            'unit': baseUnit,
            if (mrp > 0) 'catalog_price': mrp,
            'min_stock_alert': 10,
          }).select().single();

          final localMedId = localMed['id'] as String;

          // B. Insert into medicine_requests for Admin review
          await _supabase.from('medicine_requests').insert({
            'pharmacy_id': pharmacyId,
            'requested_by': uid,
            'brand_name': brand,
            'generic_name': generic.isEmpty ? null : generic,
            'company': company.isEmpty ? null : company,
            'dosage_form': dosageForm.isEmpty ? null : dosageForm,
            'strength': cleanStrength.isNotEmpty ? cleanStrength : null,
            'weight': cleanWeight.isNotEmpty ? cleanWeight : null,
            'pieces_per_strip': effectivePps,
            'strips_per_box': effectiveSpb,
            'unit': baseUnit,
            if (mrp > 0) 'catalog_price': mrp,
            'notes': 'LocalMedId:$localMedId | Packaging: $effectivePps pcs/strip, $effectiveSpb units/box, Weight: ${effectiveWeight ?? ''}, Base Unit: $baseUnit, MRP: ৳$mrp',
            'status': 'pending',
          });
        }

        // D. Refresh inventory in state
        if (mounted) {
          try {
            context.read<InventoryProvider>().loadMedicines();
          } catch (_) {}
        }

        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(_isEditMode
                ? 'Updated "$brand" successfully! ✅'
                : '"$brand" added to your store inventory! (Active as Local) ✅'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _canExit = true);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: ${ErrorFormatter.format(e)}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isSuperAdmin = auth.currentProfile?.isSuperAdmin ?? false;
    final isGlobal = widget.isGlobalCatalog || isSuperAdmin;

    return PopScope(
      canPop: _canExit,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackPress();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: MediAppBar(
          title: widget.isSuggestionMode
              ? 'Suggest Medicine Edit'
              : (_isEditMode
                  ? 'Edit Medicine'
                  : (isGlobal ? 'Add to Master Catalog' : 'Add Medicine')),
          onBack: _handleBackPress,
        ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Top Status Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: widget.isSuggestionMode
                  ? Colors.blue.shade700
                  : (isGlobal ? AppColors.primary.withValues(alpha: 0.9) : const Color(0xFF0F766E)),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    Icon(
                      widget.isSuggestionMode
                          ? Icons.tips_and_updates_outlined
                          : (isGlobal ? Icons.verified_user_rounded : Icons.store_mall_directory_rounded),
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.isSuggestionMode
                            ? "Suggest Edit Mode: Your suggested changes will be sent to Admin for approval to keep the catalog accurate."
                            : (isGlobal
                                ? "Master Catalog Mode: Saving publishes directly to all pharmacies nationwide."
                                : "Store Local Medicine: Added directly to your inventory and submitted for admin catalog review."),
                        style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // â”€â”€ 1. MEDICINE NAME (BRAND NAME) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    _buildTextField(
                      controller: _medicineNameCtrl,
                      label: "Brand Name *",
                      icon: Icons.medication_rounded,
                      hint: "e.g. Napa Extra, Seclo, SMC Orsaline, NeoCare",
                      isRequired: true,
                    ),

                    // â”€â”€ 2. GENERIC NAME (FLOATING OVERLAY DROPDOWN) â”€â”€â”€â”€â”€â”€â”€â”€
                    SearchableDropdownField<String>(
                      controller: _genericNameCtrl,
                      focusNode: _genericFocus,
                      label: "Generic Name",
                      icon: Icons.science_rounded,
                      hint: "Type generic (e.g. Paracetamol, Oral Rehydration Salt)",
                      isSelected: _genericSelected,
                      isSearching: _isSearchingGeneric,
                      items: _genericSearchResults,
                      itemLabel: (s) => s,
                      onChanged: _searchGeneric,
                      onSelect: (val) {
                        setState(() {
                          _genericNameCtrl.text = val;
                          _genericSelected = true;
                          _genericSearchResults = [];
                        });
                      },
                      onSelectCustom: (val) {
                        setState(() {
                          _genericNameCtrl.text = val;
                          _genericSelected = true;
                          _genericSearchResults = [];
                        });
                      },
                      onClear: () => setState(() {
                        _genericSelected = false;
                        _genericNameCtrl.clear();
                        _genericSearchResults = [];
                      }),
                      newItemLabel: "Add as new Generic",
                    ),

                    // â”€â”€ 3. COMPANY / MANUFACTURER (FLOATING OVERLAY DROPDOWN)
                    SearchableDropdownField<Map<String, dynamic>>(
                      controller: _companyNameCtrl,
                      focusNode: _companyFocus,
                      label: "Company / Manufacturer",
                      icon: Icons.business_rounded,
                      hint: "e.g. Square, Beximco, SMC, ACI",
                      isSelected: _selectedCompanyId != null,
                      isSearching: _isSearchingCompany,
                      items: _companySearchResults,
                      itemLabel: (m) => m['company_name'] ?? '',
                      onChanged: _searchCompany,
                      onSelect: (comp) {
                        final name = comp['company_name'] ?? '';
                        setState(() {
                          _companyNameCtrl.text = name;
                          _selectedCompanyId = comp['company_id']?.toString() ?? name;
                          _companySearchResults = [];
                        });
                      },
                      onSelectCustom: (name) {
                        setState(() {
                          _companyNameCtrl.text = name;
                          _selectedCompanyId = name;
                          _companySearchResults = [];
                        });
                      },
                      onClear: () => setState(() {
                        _companyNameCtrl.clear();
                        _selectedCompanyId = null;
                        _companySearchResults = [];
                      }),
                      newItemLabel: "Add as new Company",
                    ),

                    // â”€â”€ 4. DOSAGE FORM & BASE UNIT (FLOATING OVERLAYS - FIXED POSITION)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Dosage Form (Floats above components)
                        Expanded(
                          child: SearchableDropdownField<String>(
                            controller: _medicineTypeCtrl,
                            focusNode: _typeFocus,
                            label: "Dosage Form (Type) *",
                            icon: Icons.category_rounded,
                            hint: "Tablet, Syrup...",
                            isSelected: _typeSelected,
                            isSearching: _isSearchingType,
                            items: _typeSearchResults,
                            itemLabel: (s) => s,
                            onChanged: _searchType,
                            onTap: () {
                              if (_medicineTypeCtrl.text.isEmpty || _typeSearchResults.isEmpty) {
                                _searchType(_medicineTypeCtrl.text);
                              }
                            },
                            onSelect: (val) {
                              setState(() {
                                _medicineTypeCtrl.text = val;
                                _typeSelected = true;
                                _typeSearchResults = [];
                              });
                            },
                            onSelectCustom: (val) {
                              setState(() {
                                _medicineTypeCtrl.text = val;
                                _typeSelected = true;
                                _typeSearchResults = [];
                              });
                            },
                            onClear: () => setState(() {
                              _typeSelected = false;
                              _medicineTypeCtrl.clear();
                              _typeSearchResults = [];
                            }),
                            newItemLabel: "Add as new Type",
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Base Unit (Floats above components)
                        Expanded(
                          child: SearchableDropdownField<String>(
                            controller: _baseUnitCtrl,
                            focusNode: _unitFocus,
                            label: "Base Unit *",
                            icon: Icons.inventory_rounded,
                            hint: "Piece, Bottle...",
                            isSelected: _unitSelected,
                            isSearching: _isSearchingUnit,
                            items: _unitSearchResults,
                            itemLabel: (s) => s,
                            onChanged: _searchUnit,
                            onTap: () {
                              if (_baseUnitCtrl.text.isEmpty || _unitSearchResults.isEmpty) {
                                _searchUnit(_baseUnitCtrl.text);
                              }
                            },
                            onSelect: (val) {
                              setState(() {
                                _baseUnitCtrl.text = val;
                                _unitSelected = true;
                                _unitSearchResults = [];
                              });
                            },
                            onSelectCustom: (val) {
                              setState(() {
                                _baseUnitCtrl.text = val;
                                _unitSelected = true;
                                _unitSearchResults = [];
                              });
                            },
                            onClear: () => setState(() {
                              _unitSelected = false;
                              _baseUnitCtrl.clear();
                              _unitSearchResults = [];
                            }),
                            newItemLabel: "Add as new Unit",
                          ),
                        ),
                      ],
                    ),

                    // â”€â”€ 5. PACKAGING RATIO (CLEAN, COMPACT & NEVER OVERFLOWS) â”€
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.teal.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.inventory_2_rounded, size: 18, color: Colors.teal.shade800),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Packaging Ratio",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.teal.shade900,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Applicable for Tablets, Saline, Diapers, etc.",
                            style: TextStyle(color: Colors.teal.shade700, fontSize: 11),
                          ),
                          const SizedBox(height: 12),
                          Builder(
                            builder: (context) {
                              final dForm = _medicineTypeCtrl.text.toLowerCase();
                              final isTabOrCap = dForm.contains('tab') || dForm.contains('cap');

                              final String ppsLabel = isTabOrCap ? "Unit / Strip" : "Unit / Strip or Pack";
                              final String ppsHint = isTabOrCap ? "e.g. 10 (Napa), 14, 15" : "e.g. 10 (strip), 12 (pack), leave empty if N/A";

                              final String spbLabel = isTabOrCap ? "Strip / Box" : "Strip or Pack / Box";
                              final String spbHint = isTabOrCap ? "e.g. 10 strips/box, 20" : "e.g. 10 (boxes/packs), leave empty if N/A";

                              return Row(
                                children: [
                                  Expanded(
                                    child: _buildTextField(
                                      controller: _piecesPerStripCtrl,
                                      label: ppsLabel,
                                      icon: Icons.format_size_rounded,
                                      isInteger: true,
                                      hint: ppsHint,
                                      isRequired: false,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _buildTextField(
                                      controller: _stripsPerBoxCtrl,
                                      label: spbLabel,
                                      icon: Icons.all_inbox_rounded,
                                      isInteger: true,
                                      hint: spbHint,
                                      isRequired: false,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 2, left: 4),
                            child: Text(
                              "💡 Tip: Tablet/Strip: enter Unit/Strip & Strip/Box. Sachet/Pack: enter Pack Size in Unit/Strip. Leave empty for single items (Syrup, Tube).",
                              style: TextStyle(fontSize: 11, color: Colors.teal.shade800, fontStyle: FontStyle.italic),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // â”€â”€ 6. STRENGTH & WEIGHT / PACK SIZE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _strengthCtrl,
                            label: "Strength",
                            icon: Icons.fitness_center_rounded,
                            hint: "e.g. 500mg, 20mg, 100ml, L",
                            isRequired: false,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildTextField(
                            controller: _weightCtrl,
                            label: "Pack Size / Weight",
                            icon: Icons.scale_rounded,
                            hint: "e.g. 100ml, 15g, 8 pads",
                            isRequired: false,
                          ),
                        ),
                      ],
                    ),

                    // â”€â”€ 7. PRICING (OFFICIAL COMPANY MRP ONLY) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    _buildTextField(
                      controller: _mrpPriceCtrl,
                      label: "Default MRP (৳) *",
                      icon: Icons.payments_rounded,
                      isNumber: true,
                      hint: "e.g. 3.00 (Official MRP per Base Unit)",
                      isRequired: true,
                    ),
                    const SizedBox(height: 24),

                    // â”€â”€ 8. SUBMIT BUTTON â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _handleSave,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 3,
                        ),
                        child: _isSaving
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isGlobal
                                        ? (_isEditMode ? Icons.check_circle_outline : Icons.add_circle_outline)
                                        : (widget.isSuggestionMode ? Icons.tips_and_updates_outlined : Icons.send_rounded),
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isGlobal
                                        ? (_isEditMode ? "Update Global Medicine" : "Save to Global Catalog")
                                        : (widget.isSuggestionMode ? "Submit Edit Suggestion" : (_isEditMode ? "Update Medicine" : "Submit Medicine Request")),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }

  // â”€â”€ REUSABLE TEXT FIELD BUILDER â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isNumber = false,
    bool isInteger = false,
    String? hint,
    bool isRequired = true,
    Function(String)? onChanged,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        onChanged: onChanged,
        keyboardType: isInteger
            ? TextInputType.number
            : (isNumber
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text),
        inputFormatters: isInteger
            ? [FilteringTextInputFormatter.digitsOnly]
            : (isNumber
                ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))]
                : null),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: AppColors.primary),
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 16,
          ),
        ),
        validator: (value) {
          if (isRequired && (value == null || value.trim().isEmpty)) {
            return "Required";
          }
          if ((isNumber || isInteger) &&
              value != null &&
              value.trim().isNotEmpty &&
              double.tryParse(value.trim()) == null) {
            return "Enter valid number";
          }
          return null;
        },
      ),
    );
  }
}

// â”€â”€ FLOATING OVERLAY DROPDOWN FIELD (SAFE FRAME SCHEDULING) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€