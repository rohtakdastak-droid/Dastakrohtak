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
  final String id, group, label;
  final int delta;
  ProductOption(Json j)
      : id = j['id'],
        group = j['group_name'],
        label = j['label'],
        delta = integer(j['price_delta_paise']);
  Json toJson() => {
        'id': id,
        'group_name': group,
        'label': label,
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
  int get total =>
      (product.price + options.fold<int>(0, (s, o) => s + o.delta)) * quantity;
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
