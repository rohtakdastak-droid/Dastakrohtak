typedef Json = Map<String, dynamic>;
int integer(dynamic v) => v is num ? v.toInt() : int.parse('$v');
double decimal(dynamic v) => v is num ? v.toDouble() : double.parse('$v');
String money(int paise) => '₹${(paise / 100).toStringAsFixed(2)}';
String human(String value) => value.replaceAll('_', ' ');

class Account {
  final String id, name, role, status;
  Account(Json j)
      : id = j['id'],
        name = j['display_name'] ?? '',
        role = j['role'],
        status = j['status'];
  bool get active => status == 'active';
}

class Store {
  final String id, name, category, address, description;
  final String? image;
  final int minimum;
  final bool active;
  Store(Json j)
      : id = j['id'],
        name = j['name'],
        category = j['category'],
        address = j['dispatch_address'],
        description = j['description'] ?? '',
        image = j['cover_image_path'],
        minimum = integer(j['min_order_paise']),
        active = j['is_active'];
}

class ProductOption {
  final String id, group, label, selection;
  final int delta;
  ProductOption(Json j)
      : id = j['id'],
        group = j['group_name'],
        label = j['label'],
        selection = j['selection'] ?? 'multi',
        delta = integer(j['price_delta_paise']);
  bool get required => selection == 'single_required';
  Json toJson() => {
        'id': id,
        'group_name': group,
        'label': label,
        'selection': selection,
        'price_delta_paise': delta
      };
}

class Product {
  final String id, vendorId, name, description, diet;
  final int price;
  final int? stock;
  final String? image;
  final bool available;
  final List<ProductOption> options;
  Product(Json j)
      : id = j['id'],
        vendorId = j['vendor_id'],
        name = j['name'],
        description = j['description'] ?? '',
        diet = j['diet'] ?? 'unknown',
        price = integer(j['sale_price_paise'] ?? j['price_paise']),
        stock = j['stock'] == null ? null : integer(j['stock']),
        image = j['image_path'],
        available = j['is_available'] ?? true,
        options = ((j['product_options'] ?? []) as List)
            .where((o) => o['is_available'] != false)
            .map((o) => ProductOption(Map<String, dynamic>.from(o)))
            .toList();
  /// Required single-choice groups such as Portion: Half plate / Full plate.
  Map<String, List<ProductOption>> get choiceGroups {
    final groups = <String, List<ProductOption>>{};
    for (final o in options.where((o) => o.required)) {
      groups.putIfAbsent(o.group, () => []).add(o);
    }
    return groups;
  }

  /// "Half plate ₹120 • Full plate ₹200" for single-group items, otherwise the plain price.
  String get priceText {
    final groups = choiceGroups;
    if (groups.length == 1) {
      return groups.values.first.map((o) => '${o.label} ${money(price + o.delta)}').join(' • ');
    }
    if (groups.isEmpty) return money(price);
    final least = groups.values.fold<int>(0, (s, g) => s + g.map((o) => o.delta).reduce((a, b) => a < b ? a : b));
    return 'from ${money(price + least)}';
  }

  Json toJson() => {
        'id': id,
        'vendor_id': vendorId,
        'name': name,
        'description': description,
        'diet': diet,
        'price_paise': price,
        'stock': stock,
        'image_path': image,
        'is_available': available,
        'product_options': options.map((o) => o.toJson()).toList()
      };
}

class CartLine {
  final Product product;
  final int quantity;
  final List<ProductOption> options;
  CartLine(this.product, this.quantity, this.options) {
    if (quantity < 1 || quantity > 99) {
      throw ArgumentError('Quantity must be between 1 and 99');
    }
  }
  /// Same product with a different option set (e.g. Half vs Full plate) is a separate line.
  String get key => options.isEmpty
      ? product.id
      : '${product.id}|${(options.map((o) => o.id).toList()..sort()).join(',')}';
  int get unitPrice => product.price + options.fold<int>(0, (s, o) => s + o.delta);
  int get total => unitPrice * quantity;
  Json toJson() => {
        'product': product.toJson(),
        'quantity': quantity,
        'options': options.map((o) => o.toJson()).toList()
      };
  Json get request => {
        'product_id': product.id,
        'quantity': quantity,
        'options': options.map((o) => {'option_id': o.id}).toList()
      };
  factory CartLine.fromJson(Json j) => CartLine(
      Product(Map<String, dynamic>.from(j['product'])),
      integer(j['quantity']),
      (j['options'] as List)
          .map((o) => ProductOption(Map<String, dynamic>.from(o)))
          .toList());
}

class Address {
  final String id, label, text;
  final double lat, lng;
  Address(Json j)
      : id = j['id'],
        label = j['label'] ?? 'Address',
        text = j['formatted_address'],
        lat = decimal(j['latitude']),
        lng = decimal(j['longitude']);
}

class Order {
  final Json data;
  Order(this.data);
  String get id => data['id'];
  String get number => data['order_number'];
  String get status => data['status'];
  String get payment => data['payment_status'];
  int get total => integer(data['total_payable_paise']);
}

List<String> vendorTransitions(String status) => switch (status) {
      'vendor_confirmation' => ['preparing', 'rejected'],
      'preparing' => ['ready_for_pickup'],
      _ => []
    };
String? deliveryTransition(String status) => switch (status) {
      'assigned' => 'picked_up',
      'picked_up' => 'out_for_delivery',
      'out_for_delivery' => 'delivered',
      _ => null
    };
bool validCoordinates(double? lat, double? lng) =>
    lat != null &&
    lng != null &&
    lat.isFinite &&
    lng.isFinite &&
    lat >= -90 &&
    lat <= 90 &&
    lng >= -180 &&
    lng <= 180;

const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

DateTime _istNow() {
  final u = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  return DateTime(u.year, u.month, u.day, u.hour, u.minute);
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Next opening time for schedules in Asia/Kolkata; null when unknown.
String? nextOpening(dynamic hours) {
  if (hours is! Map || hours['weekly'] is! Map || (hours['weekly'] as Map).isEmpty) {
    return null;
  }
  if ((hours['timezone'] ?? 'Asia/Kolkata') != 'Asia/Kolkata') return null;
  final weekly = hours['weekly'] as Map;
  final holidays = ((hours['holidays'] as List?) ?? []).map((e) => '$e').toSet();
  final now = _istNow();
  for (var d = 0; d < 8; d++) {
    final day = DateTime(now.year, now.month, now.day).add(Duration(days: d));
    if (holidays.contains(_ymd(day))) continue;
    final opens = ((weekly['${day.weekday}'] as List?) ?? [])
        .map((s) => '${(s as List)[0]}')
        .toList()
      ..sort();
    for (final o in opens) {
      final p = o.split(':');
      final at = DateTime(day.year, day.month, day.day, int.parse(p[0]), int.parse(p[1]));
      if (at.isAfter(now)) {
        final dayText = d == 0
            ? 'today'
            : d == 1
                ? 'tomorrow'
                : weekdayNames[day.weekday - 1];
        return 'Opens $dayText at $o';
      }
    }
  }
  return null;
}

List<String> hoursSummary(dynamic hours) {
  if (hours is! Map || hours['weekly'] is! Map || (hours['weekly'] as Map).isEmpty) {
    return const [];
  }
  final weekly = hours['weekly'] as Map;
  return [
    for (var i = 1; i <= 7; i++)
      '${weekdayNames[i - 1]}: ${((weekly['$i'] as List?) ?? []).isEmpty ? 'Closed' : ((weekly['$i'] as List).map((s) => '${(s as List)[0]}–${s[1]}').join(', '))}'
  ];
}

/// Editable rupee text for a paise amount: 12000 -> "120", 12050 -> "120.50".
String rupeesText(dynamic paise) {
  if (paise == null || '$paise'.isEmpty) return '';
  final p = integer(paise);
  return p % 100 == 0 ? '${p ~/ 100}' : '${p ~/ 100}.${(p % 100).toString().padLeft(2, '0')}';
}

/// Parses a rupee amount typed by a person into exact paise, or null when invalid.
int? parsePaise(String text) {
  final m = RegExp(r'^(\d{1,7})(?:\.(\d{1,2}))?$').firstMatch(text.trim().replaceAll(',', ''));
  if (m == null) return null;
  return int.parse(m.group(1)!) * 100 + int.parse((m.group(2) ?? '0').padRight(2, '0'));
}
