import 'package:sqflite/sqflite.dart';
import 'dart:developer' as dev;
import '../models/product.dart';
import 'app_database.dart';

/// Data Access Object for products — SQLite as the single source of truth.
class ProductDao {
  static Future<void> upsert(Product product) async {
    final db = await AppDatabase.database;
    await db.insert(
      'products',
      {
        'id': product.id,
        'name': product.name,
        'barcode': product.barcode,
        'category': product.category,
        'category_id': product.categoryId,
        'branch_id': product.branchId,
        'stock': product.stock,
        'sell_price': product.sellPrice,
        'description': product.description,
        'product_image': product.image,
        'is_low_stock': product.isLowStock ? 1 : 0,
        'is_out_of_stock': product.isOutOfStock ? 1 : 0,
        'created_at': product.createdAt.toIso8601String(),
        'updated_at': product.updatedAt.toIso8601String(),
        'synced_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    dev.log('Product upserted: ${product.id} - ${product.name}', name: 'PRODUCT_DAO');
  }

  static Future<void> upsertBatch(List<Product> products) async {
    final db = await AppDatabase.database;
    final batch = db.batch();
    for (final product in products) {
      batch.insert(
        'products',
        {
          'id': product.id,
          'name': product.name,
          'barcode': product.barcode,
          'category': product.category,
          'category_id': product.categoryId,
          'branch_id': product.branchId,
          'stock': product.stock,
          'sell_price': product.sellPrice,
          'description': product.description,
          'product_image': product.image,
          'is_low_stock': product.isLowStock ? 1 : 0,
          'is_out_of_stock': product.isOutOfStock ? 1 : 0,
          'created_at': product.createdAt.toIso8601String(),
          'updated_at': product.updatedAt.toIso8601String(),
          'synced_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    dev.log('Batch upserted ${products.length} products', name: 'PRODUCT_DAO');
  }

  static Future<void> delete(String productId) async {
    final db = await AppDatabase.database;
    await db.delete('products', where: 'id = ?', whereArgs: [productId]);
    dev.log('Product deleted: $productId', name: 'PRODUCT_DAO');
  }

  static Future<List<Product>> getAll({int? branchId}) async {
    final db = await AppDatabase.database;
    final maps = branchId != null
        ? await db.query('products',
            where: 'branch_id = ?', whereArgs: [branchId], orderBy: 'updated_at DESC, name ASC')
        : await db.query('products', orderBy: 'updated_at DESC, name ASC');
    return maps.map(_mapToProduct).toList();
  }

  static Future<Product?> getById(String productId) async {
    final db = await AppDatabase.database;
    final maps = await db.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
    if (maps.isEmpty) return null;
    return _mapToProduct(maps.first);
  }

  static Future<Product?> getByBarcode(String barcode) async {
    final db = await AppDatabase.database;
    final maps = await db.query('products', where: 'barcode = ?', whereArgs: [barcode], limit: 1);
    if (maps.isEmpty) return null;
    return _mapToProduct(maps.first);
  }

  static Future<List<Product>> search(String query, {int? branchId}) async {
    final db = await AppDatabase.database;
    final p = '%${query.toLowerCase()}%';
    String where = '(LOWER(name) LIKE ? OR LOWER(barcode) LIKE ? OR LOWER(category) LIKE ?)';
    List<dynamic> args = [p, p, p];
    if (branchId != null) {
      where = '$where AND branch_id = ?';
      args.add(branchId);
    }
    final maps = await db.query('products', where: where, whereArgs: args, orderBy: 'name ASC');
    return maps.map(_mapToProduct).toList();
  }

  static Product _mapToProduct(Map<String, dynamic> m) => Product(
        id: m['id'] as String,
        name: m['name'] as String,
        barcode: m['barcode'] as String?,
        category: m['category'] as String?,
        categoryId: m['category_id'] as int?,
        branchId: m['branch_id'] as int?,
        stock: m['stock'] as int,
        costPrice: 0,
        sellPrice: (m['sell_price'] as num).toDouble(),
        description: m['description'] as String?,
        image: m['product_image'] as String?,
        createdAt: m['created_at'] != null ? DateTime.parse(m['created_at'] as String) : DateTime.now(),
        updatedAt: m['updated_at'] != null ? DateTime.parse(m['updated_at'] as String) : DateTime.now(),
      );
}
