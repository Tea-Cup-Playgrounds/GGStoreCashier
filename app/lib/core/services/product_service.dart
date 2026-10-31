import '../config/api_config.dart';

/// Image helpers for catalog products. Product data comes from CatalogService (/api/catalog).
class ProductService {
  static String getProductImageUrl(String? imageName) {
    if (imageName == null || imageName.isEmpty) {
      return '';
    }
    return '${ApiConfig.apiUrl}/uploads/products/$imageName';
  }

  static String getPlaceholderImage() {
    return 'assets/products/example.jpg';
  }
}
