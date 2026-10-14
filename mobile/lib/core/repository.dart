import 'dart:async';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';

class DastakRepository {
  final SupabaseClient client;
  DastakRepository(this.client);
  String get uid =>
      client.auth.currentUser?.id ?? (throw StateError('Please sign in'));
  Future<List<Json>> rows(String table,
      {String select = '*',
      String sort = 'created_at',
      bool ascending = false,
      Map<String, Object> filters = const {},
      int page = 0}) async {
    var query = client.from(table).select(select);
    for (final entry in filters.entries) {
      query = query.eq(entry.key, entry.value);
    }
    final data = await query
        .order(sort, ascending: ascending)
        .range(page * 30, page * 30 + 29)
        .timeout(const Duration(seconds: 20));
    return data.map((j) => Map<String, dynamic>.from(j)).toList();
  }

  Future<Json> one(String table, String id,
          {String key = 'id', String select = '*'}) async =>
      await client
          .from(table)
          .select(select)
          .eq(key, id)
          .single()
          .timeout(const Duration(seconds: 20));
  Future<List<Json>> orderRows(String table, String orderId,
      {String sort = 'created_at'}) async {
    final result = <Json>[];
    for (var page = 0;; page++) {
      final batch = await rows(table,
          filters: {'order_id': orderId},
          sort: sort,
          ascending: true,
          page: page);
      result.addAll(batch);
      if (batch.length < 30) return result;
    }
  }

  Future<void> save(String table, Json data,
      {String? id, String key = 'id'}) async {
    if (id == null) {
      await client
          .from(table)
          .insert(data)
          .timeout(const Duration(seconds: 20));
    } else {
      await client
          .from(table)
          .update(data)
          .eq(key, id)
          .select()
          .single()
          .timeout(const Duration(seconds: 20));
    }
  }

  Future<void> remove(String table, String id) async => client
      .from(table)
      .delete()
      .eq('id', id)
      .timeout(const Duration(seconds: 20));
  Future<dynamic> rpc(String name, [Json params = const {}]) =>
      client.rpc(name, params: params).timeout(const Duration(seconds: 25));
  Future<Account?> account() async => client.auth.currentUser == null
      ? null
      : Account(await one('profiles', uid));
  Future<List<Store>> stores(
      {int page = 0, String? category, String search = ''}) async {
    var q = client.from('vendors').select().eq('is_active', true);
    if (category != null) q = q.eq('category', category);
    if (search.trim().isNotEmpty) {
      q = q.ilike('name', '%${search.replaceAll(RegExp(r'[%_]'), '')}%');
    }
    return (await q
            .order('sort_priority')
            .range(page * 30, page * 30 + 29)
            .timeout(const Duration(seconds: 20)))
        .map(Store.new)
        .toList();
  }

  Future<List<Json>> discover(
      {double? lat, double? lng, String search = '', int page = 0}) async {
    final data = await rpc('discover_stores', {
      'p_lat': lat,
      'p_lng': lng,
      'p_search': search.replaceAll(RegExp(r'[%_]'), '').trim(),
      'p_category': 'food',
      'p_page': page
    });
    return List<Json>.from(
        (data as List).map((j) => Map<String, dynamic>.from(j as Map)));
  }

  Future<Json> rpcJson(String name, [Json params = const {}]) async {
    final data = await rpc(name, params);
    if (data == null) return {};
    return Map<String, dynamic>.from(data as Map);
  }

  Future<List<Json>> rpcList(String name, [Json params = const {}]) async {
    final data = await rpc(name, params);
    if (data == null) return [];
    return List<Json>.from(
        (data as List).map((j) => Map<String, dynamic>.from(j as Map)));
  }

  /// Address suggestions from the server (Ola Maps). Throws when search is unavailable.
  Future<List<Json>> searchPlaces(String input, {double? lat, double? lng}) async {
    final response = await client.functions
        .invoke('places-search', body: {'input': input, 'lat': lat, 'lng': lng})
        .timeout(const Duration(seconds: 10));
    final data = response.data;
    if (data is! Map || data['suggestions'] is! List) throw StateError('Address search unavailable');
    return List<Json>.from((data['suggestions'] as List).map((j) => Map<String, dynamic>.from(j as Map)));
  }

  Future<String> signedUrl(String bucket, String path, {int seconds = 120}) =>
      client.storage
          .from(bucket)
          .createSignedUrl(path, seconds)
          .timeout(const Duration(seconds: 20));

  Future<List<Product>> products(String vendor, {int page = 0}) async =>
      (await rows('products',
              select: '*,product_options(*)',
              sort: 'sort_priority',
              ascending: true,
              filters: {'vendor_id': vendor, 'is_available': true},
              page: page))
          .map(Product.new)
          .toList();
  Future<List<Json>> myStores() async {
    final data = await client
        .from('vendor_members')
        .select('vendors(*)')
        .eq('user_id', uid)
        .eq('status', 'active');
    return data.map((r) => Map<String, dynamic>.from(r['vendors'])).toList();
  }

  Future<Json> checkout(Json body) async {
    // A legacy place-order function ignores quote_only and would place an order.
    // Fail closed unless the coordinated mobile backend deployment is present.
    try {
      final capabilities = await rpc('mobile_checkout_capabilities');
      if (capabilities is! Map || capabilities['version'] != 1) {
        throw StateError('Unsupported checkout service');
      }
    } catch (_) {
      throw StateError(
          'Checkout is unavailable until the mobile backend update is deployed. Your bag has been kept.');
    }
    try {
      final response = await client.functions
          .invoke('place-order', body: body)
          .timeout(const Duration(seconds: 30));
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['error'] != null) throw StateError(data['error'].toString());
      return data;
    } on FunctionException catch (e) {
      throw StateError(e.details is Map
          ? '${e.details['error'] ?? 'Checkout failed'}'
          : 'Checkout unavailable. Retry.');
    }
  }

  Future<String> upload(String bucket, String folder, Uint8List bytes) async {
    if (bytes.length > 5 * 1024 * 1024) {
      throw StateError('Image must be smaller than 5 MB');
    }
    final (extension, contentType) = imageFormat(bytes);
    final path = '$folder/${const Uuid().v4()}.$extension';
    await client.storage
        .from(bucket)
        .uploadBinary(path, bytes,
            fileOptions: FileOptions(contentType: contentType))
        .timeout(const Duration(seconds: 30));
    return path;
  }

  static (String, String) imageFormat(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) {
      return ('jpg', 'image/jpeg');
    }
    if (bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71) {
      return ('png', 'image/png');
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return ('webp', 'image/webp');
    }
    throw StateError('Choose a JPEG, PNG or WebP image.');
  }

  String? imageUrl(String? path, {String bucket = 'product-images'}) {
    if (path == null || path.isEmpty) return null;
    if (Uri.tryParse(path)?.scheme == 'https') return path;
    return client.storage.from(bucket).getPublicUrl(path);
  }

  RealtimeChannel watch(String table, void Function() changed,
          {String? column, String? value}) =>
      client
          .channel('$table:${const Uuid().v4()}')
          .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: table,
              filter: column == null
                  ? null
                  : PostgresChangeFilter(
                      type: PostgresChangeFilterType.eq,
                      column: column,
                      value: value!),
              callback: (_) => changed())
          .subscribe();
}
