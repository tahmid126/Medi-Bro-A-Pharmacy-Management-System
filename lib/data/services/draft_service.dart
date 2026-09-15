import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class DraftService {
  static const String _exportDraftsKey = 'medibro_export_drafts_v1';
  static const String _importDraftsKey = 'medibro_import_drafts_v1';
  static const _uuid = Uuid();

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPORT (CUSTOMER / POS SALES) DRAFTS
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> getExportDrafts({
    String? customerId,
    String? filterName,
    String? searchQuery,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_exportDraftsKey);
    List<Map<String, dynamic>> list = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List;
        list = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {}
    }

    // Filter by selected customer (ID or Name)
    if ((customerId != null && customerId.isNotEmpty) || (filterName != null && filterName.isNotEmpty)) {
      final targetId = customerId?.trim();
      final targetName = filterName?.toLowerCase().trim();
      list = list.where((d) {
        final cId = d['customer_id']?.toString().trim();
        final cName = (d['customer_name'] ?? d['customer']?['customer_name'] ?? '').toString().toLowerCase();
        final matchesId = (targetId != null && targetId.isNotEmpty && cId == targetId);
        final matchesName = (targetName != null && targetName.isNotEmpty && cName.contains(targetName));
        return matchesId || matchesName;
      }).toList();
    }

    // Filter by live search query
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.toLowerCase().trim();
      list = list.where((d) {
        final dName = (d['draft_name'] ?? '').toString().toLowerCase();
        final cName = (d['customer_name'] ?? d['customer']?['customer_name'] ?? '').toString().toLowerCase();
        final phone = (d['customer_phone'] ?? d['customer']?['phone'] ?? '').toString().toLowerCase();
        return dName.contains(q) || cName.contains(q) || phone.contains(q);
      }).toList();
    }

    // Sort newest first
    list.sort((a, b) {
      final aDate = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(2000);
      final bDate = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(2000);
      return bDate.compareTo(aDate);
    });

    return list;
  }

  static Future<Map<String, dynamic>?> getExportDraft(String draftId) async {
    final all = await getExportDrafts();
    try {
      return all.firstWhere((d) => d['draft_id'] == draftId);
    } catch (_) {
      return null;
    }
  }

  static Future<String> saveExportDraft({
    String? draftId,
    required String draftName,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String discountType = '%',
    double discountValue = 0.0,
    required List<Map<String, dynamic>> items,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await getExportDrafts();
    final id = draftId ?? _uuid.v4();
    final now = DateTime.now().toIso8601String();

    final draftData = {
      'draft_id': id,
      'draft_name': draftName,
      'created_at': now,
      'customer_id': customerId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'customer': {
        'customer_id': customerId,
        'customer_name': customerName ?? '',
        'phone': customerPhone ?? '',
      },
      'discount_type': discountType,
      'discount_value': discountValue,
      'items': items,
      'export_draft_items': [{'count': items.length}],
      'items_count': items.length,
    };

    final index = all.indexWhere((d) => d['draft_id'] == id);
    if (index >= 0) {
      all[index] = draftData;
    } else {
      all.insert(0, draftData);
    }

    await prefs.setString(_exportDraftsKey, jsonEncode(all));

    // Best-effort async sync to Supabase table if it exists
    _trySyncExportDraftToSupabase(draftData);

    return id;
  }

  static Future<void> deleteExportDraft(String draftId) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await getExportDrafts();
    all.removeWhere((d) => d['draft_id'] == draftId);
    await prefs.setString(_exportDraftsKey, jsonEncode(all));

    // Best-effort remote delete
    _tryDeleteExportDraftFromSupabase(draftId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // IMPORT (COMPANY / SUPPLIER PURCHASES) DRAFTS
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> getImportDrafts({
    String? supplierId,
    String? filterName,
    String? searchQuery,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_importDraftsKey);
    List<Map<String, dynamic>> list = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List;
        list = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {}
    }

    // Filter by selected supplier / company (ID or Name)
    if ((supplierId != null && supplierId.isNotEmpty) || (filterName != null && filterName.isNotEmpty)) {
      final targetId = supplierId?.trim();
      final targetName = filterName?.toLowerCase().trim();
      list = list.where((d) {
        final sId = d['supplier_id']?.toString().trim();
        final sName = (d['supplier_name'] ?? d['supplier']?['company_name'] ?? '').toString().toLowerCase();
        final matchesId = (targetId != null && targetId.isNotEmpty && sId == targetId);
        final matchesName = (targetName != null && targetName.isNotEmpty && sName.contains(targetName));
        return matchesId || matchesName;
      }).toList();
    }

    // Filter by live search query
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.toLowerCase().trim();
      list = list.where((d) {
        final dName = (d['draft_name'] ?? '').toString().toLowerCase();
        final sName = (d['supplier_name'] ?? d['supplier']?['company_name'] ?? '').toString().toLowerCase();
        return dName.contains(q) || sName.contains(q);
      }).toList();
    }

    // Sort newest first
    list.sort((a, b) {
      final aDate = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(2000);
      final bDate = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(2000);
      return bDate.compareTo(aDate);
    });

    return list;
  }

  static Future<Map<String, dynamic>?> getImportDraft(String draftId) async {
    final all = await getImportDrafts();
    try {
      return all.firstWhere((d) => d['draft_id'] == draftId);
    } catch (_) {
      return null;
    }
  }

  static Future<String> saveImportDraft({
    String? draftId,
    required String draftName,
    String? supplierId,
    String? supplierName,
    String? supplierPhone,
    String discountType = '%',
    double discountValue = 0.0,
    required List<Map<String, dynamic>> items,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await getImportDrafts();
    final id = draftId ?? _uuid.v4();
    final now = DateTime.now().toIso8601String();

    final draftData = {
      'draft_id': id,
      'draft_name': draftName,
      'created_at': now,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'supplier_phone': supplierPhone,
      'supplier': {
        'company_id': supplierId,
        'company_name': supplierName ?? '',
      },
      'discount_type': discountType,
      'discount_value': discountValue,
      'items': items,
      'import_draft_items': [{'count': items.length}],
      'items_count': items.length,
    };

    final index = all.indexWhere((d) => d['draft_id'] == id);
    if (index >= 0) {
      all[index] = draftData;
    } else {
      all.insert(0, draftData);
    }

    await prefs.setString(_importDraftsKey, jsonEncode(all));

    // Best-effort async sync to Supabase table if it exists
    _trySyncImportDraftToSupabase(draftData);

    return id;
  }

  static Future<void> deleteImportDraft(String draftId) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await getImportDrafts();
    all.removeWhere((d) => d['draft_id'] == draftId);
    await prefs.setString(_importDraftsKey, jsonEncode(all));

    // Best-effort remote delete
    _tryDeleteImportDraftFromSupabase(draftId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BEST-EFFORT SUPABASE SYNC (Silent failover if table does not exist)
  // ═══════════════════════════════════════════════════════════════════════════

  static void _trySyncExportDraftToSupabase(Map<String, dynamic> data) async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      await supabase.from('export_draft').upsert({
        'draft_id': data['draft_id'],
        'draft_name': data['draft_name'],
        'customer_id': data['customer_id'],
        'discount_type': data['discount_type'],
        'discount_value': data['discount_value'],
        'created_at': data['created_at'],
        'user_id': userId,
      });
    } catch (_) {}
  }

  static void _tryDeleteExportDraftFromSupabase(String draftId) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('export_draft_items').delete().eq('draft_id', draftId);
      await supabase.from('export_draft').delete().eq('draft_id', draftId);
    } catch (_) {}
  }

  static void _trySyncImportDraftToSupabase(Map<String, dynamic> data) async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      await supabase.from('import_draft').upsert({
        'draft_id': data['draft_id'],
        'draft_name': data['draft_name'],
        'supplier_id': data['supplier_id'],
        'discount_type': data['discount_type'],
        'discount_value': data['discount_value'],
        'created_at': data['created_at'],
        'user_id': userId,
      });
    } catch (_) {}
  }

  static void _tryDeleteImportDraftFromSupabase(String draftId) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('import_draft_items').delete().eq('draft_id', draftId);
      await supabase.from('import_draft').delete().eq('draft_id', draftId);
    } catch (_) {}
  }
}
