class Sale {
  final int? id;
  final String invoiceNo;
  final int? customerId;
  final String customerName;
  final double subtotal;
  final double gstPercent;
  final double gstAmount;
  final double grandTotal;
  final String paymentMode;
  final String createdAt;
  final String syncState;

  const Sale({
    this.id,
    required this.invoiceNo,
    this.customerId,
    required this.customerName,
    required this.subtotal,
    required this.gstPercent,
    required this.gstAmount,
    required this.grandTotal,
    required this.paymentMode,
    required this.createdAt,
    this.syncState = 'pending',
  });

  factory Sale.fromMap(Map<String, Object?> map) => Sale(
        id: map['id'] as int?,
        invoiceNo: (map['invoice_no'] ?? '') as String,
        customerId: map['customer_id'] as int?,
        customerName: (map['customer_name'] ?? 'Walk-in Customer') as String,
        subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0,
        gstPercent: (map['gst_percent'] as num?)?.toDouble() ?? 0,
        gstAmount: (map['gst_amount'] as num?)?.toDouble() ?? 0,
        grandTotal: (map['grand_total'] as num?)?.toDouble() ?? 0,
        paymentMode: (map['payment_mode'] ?? 'Cash') as String,
        createdAt: (map['created_at'] ?? '') as String,
        syncState: (map['sync_state'] ?? 'pending') as String,
      );
}

class SaleLine {
  final int? id;
  final int? saleId;
  final int inventoryId;
  final String tileName;
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  const SaleLine({
    this.id,
    this.saleId,
    required this.inventoryId,
    required this.tileName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  factory SaleLine.fromMap(Map<String, Object?> map) => SaleLine(
        id: map['id'] as int?,
        saleId: map['sale_id'] as int?,
        inventoryId: (map['inventory_id'] as num?)?.toInt() ?? 0,
        tileName: (map['tile_name'] ?? '') as String,
        quantity: (map['quantity'] as num?)?.toInt() ?? 0,
        unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0,
        lineTotal: (map['line_total'] as num?)?.toDouble() ?? 0,
      );
}
