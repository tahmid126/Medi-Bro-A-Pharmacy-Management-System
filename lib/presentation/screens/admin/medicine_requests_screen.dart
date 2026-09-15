import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/medicine_packaging_helper.dart';
import '../../../data/models/medicine_model.dart';
import '../../../data/services/supabase_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common/medi_app_bar.dart';
import '../../widgets/inventory/stock_medicine_card.dart';
import 'add_medicine_form_screen.dart';

class MedicineRequestsScreen extends StatefulWidget {
  const MedicineRequestsScreen({super.key});

  @override
  State<MedicineRequestsScreen> createState() => _MedicineRequestsScreenState();
}

class _MedicineRequestsScreenState extends State<MedicineRequestsScreen> {
  final SupabaseClient _supabase = SupabaseService.instance.client;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _statusFilter = 'pending'; // 'pending', 'approved', 'rejected', 'all'
  String _selectedQueueType = 'new'; // 'new' or 'suggestion'

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isSuggestion(Map<String, dynamic> req) {
    final type = req['request_type']?.toString().toLowerCase();
    if (type == 'suggestion' || type == 'edit_suggestion') return true;
    final notes = (req['notes'] ?? '').toString().toLowerCase();
    return notes.contains('type:suggestion') || notes.contains('globalmedid:') || notes.contains('suggestedit:');
  }

  Future<void> _fetchRequests() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      var query = _supabase
          .from('medicine_requests')
          .select('*, pharmacy:pharmacy_id(name, phone)');

      if (_statusFilter != 'all') {
        query = query.eq('status', _statusFilter);
      }

      final data = await query.order('created_at', ascending: false);
      final rawRequests = List<Map<String, dynamic>>.from(data);

      // Collect all localMedIds to fetch their exact batch prices & packaging
      final localMedIds = <String>[];
      for (final r in rawRequests) {
        final notes = (r['notes'] ?? '').toString();
        final match = RegExp(r'LocalMedId:([^\s|]+)').firstMatch(notes);
        if (match != null) {
          localMedIds.add(match.group(1)!);
        }
      }

      final Map<String, double> medIdToPrice = {};
      final Map<String, Map<String, dynamic>> medIdToInfo = {};

      if (localMedIds.isNotEmpty) {
        try {
          final batchesData = await _supabase
              .from('batches')
              .select('medicine_id, mrp, selling_price')
              .inFilter('medicine_id', localMedIds);
          for (final b in batchesData) {
            final mId = b['medicine_id']?.toString();
            if (mId != null) {
              final double bMrp = double.tryParse(b['mrp']?.toString() ?? '0') ?? 0.0;
              final double bSp = double.tryParse(b['selling_price']?.toString() ?? '0') ?? 0.0;
              final double price = bMrp > 0 ? bMrp : bSp;
              if (price > 0 && !medIdToPrice.containsKey(mId)) {
                medIdToPrice[mId] = price;
              }
            }
          }
        } catch (_) {}

        try {
          final medsData = await _supabase
              .from('medicines')
              .select('id, unit, pieces_per_strip, strips_per_box, weight')
              .inFilter('id', localMedIds);
          for (final m in medsData) {
            final mId = m['id']?.toString();
            if (mId != null) {
              medIdToInfo[mId] = m;
            }
          }
        } catch (_) {}
      }

      for (final r in rawRequests) {
        final notes = (r['notes'] ?? '').toString();
        String? localMedId;
        final match = RegExp(r'LocalMedId:([^\s|]+)').firstMatch(notes);
        if (match != null) localMedId = match.group(1);

        // 1. Resolve price
        double resolvedPrice = 0.0;
        if (r['default_mrp'] != null) {
          resolvedPrice = double.tryParse(r['default_mrp'].toString()) ?? 0.0;
        } else if (r['mrp'] != null) {
          resolvedPrice = double.tryParse(r['mrp'].toString()) ?? 0.0;
        } else if (r['price'] != null) {
          resolvedPrice = double.tryParse(r['price'].toString()) ?? 0.0;
        }

        if (resolvedPrice <= 0 && localMedId != null && medIdToPrice.containsKey(localMedId)) {
          resolvedPrice = medIdToPrice[localMedId]!;
        }

        if (resolvedPrice <= 0 && notes.isNotEmpty) {
          final mrpMatch = RegExp(r'MRP:\s*[৳$]?\s*(\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(notes);
          if (mrpMatch != null) {
            resolvedPrice = double.tryParse(mrpMatch.group(1)!) ?? 0.0;
          }
        }
        if (resolvedPrice <= 0 && r['strength'] != null) {
          final mrpMatch = RegExp(r'\[MRP:\s*[৳$]?\s*(\d+(?:\.\d+)?)\]', caseSensitive: false).firstMatch(r['strength'].toString());
          if (mrpMatch != null) {
            resolvedPrice = double.tryParse(mrpMatch.group(1)!) ?? 0.0;
          }
        }

        r['default_mrp'] = resolvedPrice;
        r['mrp'] = resolvedPrice;

        // 2. Resolve packaging and unit if missing
        if (localMedId != null && medIdToInfo.containsKey(localMedId)) {
          final info = medIdToInfo[localMedId]!;
          if (r['default_unit'] == null && info['unit'] != null) r['default_unit'] = info['unit'];
          if (r['pieces_per_strip'] == null && info['pieces_per_strip'] != null) r['pieces_per_strip'] = info['pieces_per_strip'];
          if (r['strips_per_box'] == null && info['strips_per_box'] != null) r['strips_per_box'] = info['strips_per_box'];
          if (r['weight'] == null && info['weight'] != null) r['weight'] = info['weight'];
        }

        // Also parse packaging from notes if still empty
        if (r['pieces_per_strip'] == null && notes.isNotEmpty) {
          final ppsMatch = RegExp(r'(\d+)\s*(?:pcs|piece|pieces)?\s*\/\s*strip', caseSensitive: false).firstMatch(notes);
          if (ppsMatch != null) r['pieces_per_strip'] = int.tryParse(ppsMatch.group(1)!);
        }
        if (r['strips_per_box'] == null && notes.isNotEmpty) {
          final spbMatch = RegExp(r'(\d+)\s*(?:strips?|units?|box)?\s*\/\s*box', caseSensitive: false).firstMatch(notes);
          if (spbMatch != null) r['strips_per_box'] = int.tryParse(spbMatch.group(1)!);
        }
        if (r['default_unit'] == null && notes.isNotEmpty) {
          final buMatch = RegExp(r'Base Unit:\s*([^,\s|]+)', caseSensitive: false).firstMatch(notes);
          if (buMatch != null) r['default_unit'] = buMatch.group(1)!.trim();
        }

        // 3. Resolve weight from notes or strength if missing
        if (r['weight'] == null && notes.isNotEmpty) {
          final wtMatch = RegExp(r'Weight:\s*([^,|]+)', caseSensitive: false).firstMatch(notes);
          if (wtMatch != null) {
            final w = wtMatch.group(1)!.trim();
            if (w.isNotEmpty && w.toLowerCase() != 'null') r['weight'] = w;
          }
        }
        if (r['weight'] == null && r['strength'] != null) {
          final parenVol = RegExp(
            r'[\(\[]\s*([^()\[\]]+?(?:ml|gm|g|mg|l|kg|iu|pads?|sachets?|tubes?|drops?|spray|caps?|tabs?)[^()\[\]]*)\s*[\)\]]',
            caseSensitive: false,
          ).firstMatch(r['strength'].toString());
          if (parenVol != null) {
            final w = parenVol.group(1)!.trim();
            if (w.isNotEmpty && w.toLowerCase() != 'null') r['weight'] = w;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _requests = rawRequests;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading requests: ${ErrorFormatter.format(e)}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<Map<String, dynamic>> get _filteredRequests {
    final typeFiltered = _requests.where((req) {
      final isSug = _isSuggestion(req);
      return _selectedQueueType == 'suggestion' ? isSug : !isSug;
    }).toList();

    if (_searchQuery.trim().isEmpty) return typeFiltered;
    final q = _searchQuery.trim().toLowerCase();
    return typeFiltered.where((req) {
      final brand = (req['brand_name'] ?? '').toString().toLowerCase();
      final generic = (req['generic_name'] ?? '').toString().toLowerCase();
      final company = (req['company'] ?? '').toString().toLowerCase();
      final dosage = (req['dosage_form'] ?? '').toString().toLowerCase();
      final pharmacy = req['pharmacy'] as Map<String, dynamic>?;
      final pharmacyName = (pharmacy?['name'] ?? '').toString().toLowerCase();
      return brand.contains(q) ||
          generic.contains(q) ||
          company.contains(q) ||
          dosage.contains(q) ||
          pharmacyName.contains(q);
    }).toList();
  }

  void _openEditRequest(Map<String, dynamic> req) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddMedicineFormScreen(
          medicineData: {
            ...req,
            'request_id': req['id'],
            'weight': req['weight'],
            'default_mrp': req['default_mrp'] ?? req['mrp'] ?? 0.0,
            'mrp': req['default_mrp'] ?? req['mrp'] ?? 0.0,
            'mrp_price': req['default_mrp'] ?? req['mrp'] ?? 0.0,
          },
          isGlobalCatalog: true,
        ),
      ),
    );
    if (result == true) {
      _fetchRequests();
    }
  }

  // 1. APPROVE & ADD TO GLOBAL / UPDATE GLOBAL (IF SUGGESTION)
  Future<void> _approveAndAddRequest(Map<String, dynamic> request) async {
    final bool isSug = _isSuggestion(request);
    final String brandName = (request['brand_name'] ?? 'Medicine').toString().trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isSug ? Icons.tips_and_updates_rounded : Icons.check_circle_rounded,
              color: isSug ? const Color(0xFFD97706) : const Color(0xFF10B981),
            ),
            const SizedBox(width: 8),
            Text(
              isSug ? 'Approve Suggestion' : 'Approve Medicine',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          isSug
              ? 'Are you sure you want to approve this edit suggestion for "$brandName"?'
              : 'Are you sure you want to approve "$brandName" to the global catalog?',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade800),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isSug ? const Color(0xFFD97706) : const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Yes', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final notes = (request['notes'] ?? '').toString();
      final String rawStrength = (request['strength'] ?? '').toString().trim();
      double defaultMrp = (request['catalog_price'] as num?)?.toDouble() ??
          (request['default_mrp'] as num?)?.toDouble() ??
          (request['mrp'] as num?)?.toDouble() ?? 0.0;
      if (defaultMrp <= 0 && notes.isNotEmpty) {
        final mrpMatch = RegExp(r'MRP:\s*[৳$]?\s*(\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(notes);
        if (mrpMatch != null) defaultMrp = double.tryParse(mrpMatch.group(1)!) ?? 0.0;
      }
      if (defaultMrp <= 0 && rawStrength.isNotEmpty) {
        final mrpMatch = RegExp(r'\[MRP:\s*[৳$]?\s*(\d+(?:\.\d+)?)\]', caseSensitive: false).firstMatch(rawStrength);
        if (mrpMatch != null) defaultMrp = double.tryParse(mrpMatch.group(1)!) ?? 0.0;
      }

      final String finalBrand = (request['brand_name'] ?? '').toString().trim();
      final String finalGeneric = (request['generic_name'] ?? '').toString().trim();
      final String dosageForm = (request['dosage_form'] ?? 'Tablet').toString().trim();
      final String company = (request['company'] ?? '').toString().trim();
      String unit = (request['default_unit'] ?? request['unit'] ?? 'Pcs').toString().trim();

      int? pps = (request['pieces_per_strip'] as num?)?.toInt();
      int? spb = (request['strips_per_box'] as num?)?.toInt();
      String? wt = request['weight']?.toString().trim();

      if (pps == null && notes.isNotEmpty) {
        final ppsMatch = RegExp(r'(\d+)\s*(?:pcs|piece|pieces)?\s*\/\s*strip', caseSensitive: false).firstMatch(notes);
        if (ppsMatch != null) pps = int.tryParse(ppsMatch.group(1)!);
      }
      if (spb == null && notes.isNotEmpty) {
        final spbMatch = RegExp(r'(\d+)\s*(?:strips?|units?|box)?\s*\/\s*box', caseSensitive: false).firstMatch(notes);
        if (spbMatch != null) spb = int.tryParse(spbMatch.group(1)!);
      }
      if ((wt == null || wt.isEmpty) && notes.isNotEmpty) {
        final wtMatch = RegExp(r'Weight:\s*([^,|]+)', caseSensitive: false).firstMatch(notes);
        if (wtMatch != null) {
          final wVal = wtMatch.group(1)!.trim();
          if (wVal.isNotEmpty && wVal.toLowerCase() != 'null') wt = wVal;
        }
      }
      if ((unit.isEmpty || unit.toLowerCase() == 'pcs') && notes.isNotEmpty) {
        final uMatch = RegExp(r'Base Unit:\s*([^,|]+)', caseSensitive: false).firstMatch(notes);
        if (uMatch != null) {
          final uVal = uMatch.group(1)!.trim();
          if (uVal.isNotEmpty && uVal.toLowerCase() != 'null') unit = uVal;
        }
      }

      String cleanStr = rawStrength
          .replaceAll(RegExp(r'\s*[\(\[]?\s*\d+\s*[*xX×]\s*\d+\s*[\)\]]?'), '')
          .replaceAll(RegExp(r'\[MRP:\s*[৳$]?\s*\d+(?:\.\d+)?\]', caseSensitive: false), '')
          .trim();

      final pureWeightPattern = RegExp(
        r'^\d+(?:\.\d+)?\s*(?:ml|gm|g|l|kg|pads?|sachets?|tubes?|drops?|spray)$',
        caseSensitive: false,
      );
      if (pureWeightPattern.hasMatch(cleanStr) || (wt != null && cleanStr.toLowerCase() == wt.toLowerCase())) {
        if (wt == null || wt.isEmpty) wt = cleanStr;
        cleanStr = '';
      }

      final String? finalStrength = cleanStr.isNotEmpty ? cleanStr : null;

      final globalData = <String, dynamic>{
        'brand_name': finalBrand,
        if (finalGeneric.isNotEmpty) 'generic_name': finalGeneric,
        if (company.isNotEmpty) 'company': company,
        if (dosageForm.isNotEmpty) 'dosage_form': dosageForm,
        'strength': finalStrength,
        'weight': (wt != null && wt.isNotEmpty) ? wt : null,
        'pieces_per_strip': pps,
        'strips_per_box': spb,
        'default_unit': unit,
        if (defaultMrp > 0) 'default_mrp': defaultMrp,
      };

      String? targetGlobalId = request['global_id']?.toString();
      final match = RegExp(r'GlobalMedId:([^\s|]+)').firstMatch(notes);
      if (match != null && match.group(1) != 'null' && match.group(1)!.isNotEmpty) {
        targetGlobalId = match.group(1);
      }

      String? newGlobalId;
      bool updated = false;

      // 1. Try update by known global id
      if (targetGlobalId != null && targetGlobalId.isNotEmpty && targetGlobalId != 'null') {
        final res = await _supabase
            .from('global_medicines')
            .update(globalData)
            .eq('id', targetGlobalId)
            .select('id');
        if ((res as List).isNotEmpty) {
          updated = true;
          newGlobalId = targetGlobalId;
        }
      }

      // 2. Fallback: match by brand_name + dosage_form
      if (!updated) {
        var query = _supabase
            .from('global_medicines')
            .update(globalData)
            .ilike('brand_name', finalBrand);
        if (dosageForm.isNotEmpty) {
          query = query.ilike('dosage_form', dosageForm);
        }
        final res = await query.select('id');
        if ((res as List).isNotEmpty) {
          updated = true;
          newGlobalId = res.first['id']?.toString();
        }
      }

      // 3. If not found in global_medicines for this brand + dosage_form, INSERT as new!
      if (!updated) {
        final insertMap = Map<String, dynamic>.from(globalData);
        final res = await _supabase.from('global_medicines').insert(insertMap).select('id').single();
        newGlobalId = res['id']?.toString();
        updated = true;
      }

      // Update linked local medicines in pharmacies
      try {
        final localUpdate = <String, dynamic>{
          if (newGlobalId != null) 'global_id': newGlobalId,
          'brand_name': finalBrand,
          if (finalGeneric.isNotEmpty) 'generic_name': finalGeneric,
          if (company.isNotEmpty) 'company': company,
          if (dosageForm.isNotEmpty) 'dosage_form': dosageForm,
          'strength': finalStrength,
          'weight': (wt != null && wt.isNotEmpty) ? wt : null,
          'pieces_per_strip': pps,
          'strips_per_box': spb,
          'unit': unit,
          if (defaultMrp > 0) 'catalog_price': defaultMrp,
        };

        final pharmacyId = request['pharmacy_id']?.toString();
        if (pharmacyId != null && pharmacyId.isNotEmpty) {
          String? localMedId;
          final localMatch = RegExp(r'LocalMedId:([^\s|]+)').firstMatch(notes);
          if (localMatch != null) localMedId = localMatch.group(1);
          if (localMedId != null && localMedId.isNotEmpty) {
            await _supabase.from('medicines').update(localUpdate).eq('id', localMedId).eq('pharmacy_id', pharmacyId);
          }
        }
        if (newGlobalId != null) {
          await _supabase.from('medicines').update(localUpdate).eq('global_id', newGlobalId);
        }
        await _supabase
            .from('medicines')
            .update(localUpdate)
            .ilike('brand_name', finalBrand)
            .ilike('dosage_form', dosageForm);
      } catch (_) {}

      // Update medicine_requests record to approved
      await _supabase
          .from('medicine_requests')
          .update({
            'status': 'approved',
            'brand_name': finalBrand,
            if (finalGeneric.isNotEmpty) 'generic_name': finalGeneric,
            'dosage_form': dosageForm,
            'strength': finalStrength,
            'weight': (wt != null && wt.isNotEmpty) ? wt : null,
            'pieces_per_strip': pps,
            'strips_per_box': spb,
            'unit': unit,
            if (defaultMrp > 0) 'catalog_price': defaultMrp,
            if (company.isNotEmpty) 'company': company,
            'admin_remarks': isSug
                ? 'Approved Edit Suggestion into Global Catalog'
                : 'Approved into Global Catalog',
          })
          .eq('id', request['id']);

      messenger.showSnackBar(
        SnackBar(
          content: Text('$finalBrand approved and global catalog updated!'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
      _fetchRequests();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to approve: ${ErrorFormatter.format(e)}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 2. DENY REQUEST (WITH REASON)
  Future<void> _denyRequest(Map<String, dynamic> request) async {
    final remarksCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.cancel_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Deny Medicine Request', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to deny "${request['brand_name']}"?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: remarksCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason for denial *',
                hintText: 'e.g. Already exists in library as "...", invalid brand name, or incorrect strength',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (remarksCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please provide a reason for denial')),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Deny Request'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _supabase
          .from('medicine_requests')
          .update({
            'status': 'rejected',
            'admin_remarks': remarksCtrl.text.trim(),
          })
          .eq('id', request['id']);

      messenger.showSnackBar(
        const SnackBar(content: Text('Medicine request denied.'), backgroundColor: Colors.red),
      );
      _fetchRequests();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error: ${ErrorFormatter.format(e)}'), backgroundColor: Colors.red),
      );
    }
  }

  // 3. DELETE REQUEST
  Future<void> _deleteRequest(Map<String, dynamic> request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Request?'),
        content: Text('Permanently delete request for "${request['brand_name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _supabase.from('medicine_requests').delete().eq('id', request['id']);
        _fetchRequests();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request deleted successfully! ✅'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: ${ErrorFormatter.format(e)}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _filterChip(String label, String value) {
    final isSelected = _statusFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _statusFilter = value);
          _fetchRequests();
        }
      },
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      backgroundColor: Colors.grey.shade100,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color border;
    Color text;
    IconData icon;
    String label;

    switch (status.toLowerCase()) {
      case 'approved':
        bg = const Color(0xFFECFDF5);
        border = const Color(0xFFA7F3D0);
        text = const Color(0xFF059669);
        icon = Icons.check_circle_outline_rounded;
        label = 'Approved';
        break;
      case 'rejected':
        bg = const Color(0xFFFEF2F2);
        border = const Color(0xFFFECACA);
        text = const Color(0xFFDC2626);
        icon = Icons.cancel_outlined;
        label = 'Rejected';
        break;
      case 'pending':
      default:
        bg = const Color(0xFFFEF3C7);
        border = const Color(0xFFFDE68A);
        text = const Color(0xFFD97706);
        icon = Icons.schedule_rounded;
        label = 'Pending';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: text),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: text),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeBadge(bool isSuggestion) {
    final bg = isSuggestion ? const Color(0xFFFEF3C7) : const Color(0xFFEFF6FF);
    final border = isSuggestion ? const Color(0xFFFDE68A) : const Color(0xFFBFDBFE);
    final text = isSuggestion ? const Color(0xFFD97706) : const Color(0xFF2563EB);
    final icon = isSuggestion ? Icons.tips_and_updates_outlined : Icons.add_circle_outline_rounded;
    final label = isSuggestion ? 'Suggestion' : 'New';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: text),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: text),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestedBySection(Map<String, dynamic> req, String status) {
    final pharmacy = req['pharmacy'] as Map<String, dynamic>?;
    final pharmacyName = (pharmacy?['name']?.toString().trim().isNotEmpty ?? false)
        ? pharmacy!['name'].toString().trim()
        : 'Pharmacy';
    final pharmacyPhone = pharmacy?['phone']?.toString().trim() ?? '';

    String timeStr = '';
    if (req['created_at'] != null) {
      try {
        final dt = DateTime.parse(req['created_at'].toString()).toLocal();
        final datePart = DateFormat('d MMM').format(dt);
        final timePart = DateFormat('h:mm a').format(dt);
        timeStr = '$datePart, $timePart';
      } catch (_) {}
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              const Icon(Icons.storefront_rounded, size: 15, color: Color(0xFF475569)),
              const SizedBox(width: 6),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
                    children: [
                      TextSpan(
                        text: pharmacyName,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      if (pharmacyPhone.isNotEmpty && pharmacyPhone != 'No phone')
                        TextSpan(
                          text: ' ($pharmacyPhone)',
                          style: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w500),
                        ),
                      if (timeStr.isNotEmpty)
                        TextSpan(
                          text: ' ($timeStr)',
                          style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (req['admin_remarks'] != null && req['admin_remarks'].toString().trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: status == 'rejected' ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: status == 'rejected' ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0),
              ),
            ),
            child: Text(
              'Remarks: ${req['admin_remarks']}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: status == 'rejected' ? const Color(0xFFDC2626) : const Color(0xFF059669),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRequests;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      endDrawer: const AppDrawer(),
      appBar: const MediAppBar(title: 'Medicine Requests Queue'),
      body: Column(
        children: [
          // Filter & Search Controls (Matching Global Medicines Screen)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    setState(() => _searchQuery = val);
                  },
                  decoration: InputDecoration(
                    hintText: 'Search medicine name, generic, company...',
                    prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('Pending Request', 'pending'),
                      const SizedBox(width: 8),
                      _filterChip('Approved', 'approved'),
                      const SizedBox(width: 8),
                      _filterChip('Rejected', 'rejected'),
                      const SizedBox(width: 8),
                      _filterChip('All Request', 'all'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Count & Information bar (Matching Global Medicines Screen)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${filtered.length} items',
                  style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600),
                ),
                // 2-segment selector: [ New | Suggestion ]
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () => setState(() => _selectedQueueType = 'new'),
                        borderRadius: BorderRadius.circular(16),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: _selectedQueueType == 'new' ? const Color(0xFF10B981) : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: _selectedQueueType == 'new'
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.25),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            'New',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _selectedQueueType == 'new' ? Colors.white : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => setState(() => _selectedQueueType = 'suggestion'),
                        borderRadius: BorderRadius.circular(16),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: _selectedQueueType == 'suggestion' ? const Color(0xFF10B981) : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: _selectedQueueType == 'suggestion'
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.25),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            'Suggestion',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _selectedQueueType == 'suggestion' ? Colors.white : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Medicine Requests List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.medication_outlined, size: 56, color: Colors.grey),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'No requests matching "$_searchQuery"'
                                  : 'No $_statusFilter ${_selectedQueueType == 'suggestion' ? 'suggestion' : 'new'} requests found',
                              style: const TextStyle(fontSize: 15, color: Colors.grey, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: AppColors.primary,
                        onRefresh: _fetchRequests,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: filtered.length,
                          itemBuilder: (context, idx) {
                            final req = filtered[idx];
                            final status = (req['status'] ?? 'pending').toString().toLowerCase();
                            final isSug = _isSuggestion(req);

                            final packInfoResult = MedicinePackagingHelper.getPackagingInfo(
                              matchingGlobalMedicine: {
                                ...req,
                                'default_mrp': req['default_mrp'] ?? req['mrp'] ?? 0.0,
                              },
                            );

                            final medicineModel = MedicineModel(
                              id: req['id']?.toString() ?? '',
                              pharmacyId: req['pharmacy_id']?.toString() ?? '',
                              globalId: req['id']?.toString() ?? 'req',
                              brandName: req['brand_name'] ?? 'Unnamed',
                              genericName: req['generic_name'],
                              dosageForm: (req['dosage_form'] as String?)?.trim() ?? '',
                              strength: req['strength'],
                              company: req['company'],
                              unit: req['default_unit'] ?? req['unit'] ?? 'Pcs',
                              isActive: true,
                              piecesPerStrip: packInfoResult['pps'],
                              stripsPerBox: packInfoResult['spb'],
                              weight: packInfoResult['weight'],
                            );

                            return StockMedicineCard(
                              medicine: medicineModel,
                              matchingGlobalMedicine: {
                                ...req,
                                'default_mrp': req['default_mrp'] ?? req['mrp'] ?? 0.0,
                              },
                              viewMode: 'admin',
                              showAddStock: false,
                              onTap: status == 'pending' ? () => _openEditRequest(req) : () {},
                              onGenericTap: (gen) {
                                _searchController.text = gen;
                                setState(() => _searchQuery = gen);
                              },
                              onCompanyTap: (comp) {
                                _searchController.text = comp;
                                setState(() => _searchQuery = comp);
                              },
                              onTypeTap: (type) {
                                _searchController.text = type;
                                setState(() => _searchQuery = type);
                              },
                              middleContent: _buildRequestedBySection(req, status),
                              bottomActions: Row(
                                children: [
                                  // Status Badge: Pending, Approved, or Rejected
                                  _buildStatusBadge(status),
                                  const SizedBox(width: 6),
                                  // Type Badge: New or Suggestion
                                  _buildTypeBadge(isSug),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      reverse: true,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (status == 'pending') ...[
                                            // Approve Button
                                            ElevatedButton.icon(
                                              onPressed: () => _approveAndAddRequest(req),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF10B981),
                                                foregroundColor: Colors.white,
                                                elevation: 0,
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                visualDensity: VisualDensity.compact,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                              icon: const Icon(Icons.check_rounded, size: 14),
                                              label: const Text(
                                                'Approve',
                                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            const SizedBox(width: 8),

                                            // Deny Button
                                            OutlinedButton.icon(
                                              onPressed: () => _denyRequest(req),
                                              style: OutlinedButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                visualDensity: VisualDensity.compact,
                                                side: const BorderSide(color: Color(0xFFFECACA)),
                                                backgroundColor: const Color(0xFFFEF2F2),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                              icon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFDC2626)),
                                              label: const Text(
                                                'Deny',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFFDC2626),
                                                ),
                                              ),
                                            ),
                                          ] else ...[
                                            // Accepted / Rejected list: Delete Button to remove from UI & database
                                            OutlinedButton.icon(
                                              onPressed: () => _deleteRequest(req),
                                              style: OutlinedButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                visualDensity: VisualDensity.compact,
                                                side: const BorderSide(color: Color(0xFFFECACA)),
                                                backgroundColor: const Color(0xFFFEF2F2),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                              icon: const Icon(Icons.delete_outline_rounded, size: 14, color: Color(0xFFDC2626)),
                                              label: const Text(
                                                'Delete',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFFDC2626),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}