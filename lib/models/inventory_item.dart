class InventoryItem {
  final int? id;
  final String clientUid;
  final int? cloudId;
  final String tileName;
  final String size;
  final String texture;
  final int stock;
  final double price;
  final String hsnCode;
  final String imageUrl;
  final String localImage;
  final String syncState;
  final bool deleted;
  final String updatedAt;

  const InventoryItem({
    this.id,
    required this.clientUid,
    this.cloudId,
    required this.tileName,
    required this.size,
    required this.texture,
    required this.stock,
    required this.price,
    required this.hsnCode,
    this.imageUrl = '',
    this.localImage = '',
    this.syncState = 'pending',
    this.deleted = false,
    required this.updatedAt,
  });

  Map<String, Object?> toLocalMap() => {
    'id': id,
    'client_uid': clientUid,
    'cloud_id': cloudId,
    'tile_name': tileName,
    'size': size,
    'texture': texture,
    'stock': stock,
    'price': price,
    'hsn_code': hsnCode,
    'image_url': imageUrl,
    'local_image': localImage,
    'sync_state': syncState,
    'deleted': deleted ? 1 : 0,
    'updated_at': updatedAt,
  };

  Map<String, Object?> toCloudMap() => {
    'client_uid': clientUid,
    'tile_name': tileName,
    'size': size,
    'texture': texture,
    'stock': stock,
    'price': price,
    'hsn_code': hsnCode,
    'image_url': imageUrl,
  };

  factory InventoryItem.fromMap(Map<String, Object?> map) => InventoryItem(
    id: map['id'] as int?,
    clientUid: map['client_uid'] as String,
    cloudId: map['cloud_id'] as int?,
    tileName: (map['tile_name'] ?? '') as String,
    size: (map['size'] ?? '') as String,
    texture: (map['texture'] ?? '') as String,
    stock: (map['stock'] as num?)?.toInt() ?? 0,
    price: (map['price'] as num?)?.toDouble() ?? 0,
    hsnCode: (map['hsn_code'] ?? '6907') as String,
    imageUrl: (map['image_url'] ?? '') as String,
    localImage: (map['local_image'] ?? '') as String,
    syncState: (map['sync_state'] ?? 'pending') as String,
    deleted: ((map['deleted'] as num?)?.toInt() ?? 0) == 1,
    updatedAt: (map['updated_at'] ?? DateTime.now().toIso8601String()) as String,
  );
}
