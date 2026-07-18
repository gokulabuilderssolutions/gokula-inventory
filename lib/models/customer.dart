class Customer {
  final int? id;
  final String name;
  final String phone;
  final String address;
  final String gstin;

  const Customer({this.id, required this.name, this.phone = '', this.address = '', this.gstin = ''});

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'gstin': gstin,
      };

  factory Customer.fromMap(Map<String, Object?> map) => Customer(
        id: map['id'] as int?,
        name: (map['name'] ?? '') as String,
        phone: (map['phone'] ?? '') as String,
        address: (map['address'] ?? '') as String,
        gstin: (map['gstin'] ?? '') as String,
      );
}
