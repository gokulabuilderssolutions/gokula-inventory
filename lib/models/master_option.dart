class MasterOption {
  final int? id;
  final String type;
  final String value;
  final String category;
  final bool favorite;
  final int sortOrder;

  const MasterOption({
    this.id,
    required this.type,
    required this.value,
    this.category = 'General',
    this.favorite = false,
    this.sortOrder = 0,
  });

  factory MasterOption.fromMap(Map<String, dynamic> map) => MasterOption(
        id: map['id'] as int?,
        type: (map['type'] ?? '').toString(),
        value: (map['value'] ?? '').toString(),
        category: (map['category'] ?? 'General').toString(),
        favorite: (map['favorite'] ?? 0) == 1,
        sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'value': value,
        'category': category,
        'favorite': favorite ? 1 : 0,
        'sort_order': sortOrder,
      };
}
