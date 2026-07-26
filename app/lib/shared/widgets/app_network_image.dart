import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../core/config/api_config.dart';

/// Drop-in replacement for [CachedNetworkImage] that works on both mobile
/// and Flutter Web.
///
/// Problem on Web:
///   [CachedNetworkImage] cannot attach custom request headers to the
///   underlying browser `<img>` fetch. When the API is served behind ngrok the
///   `ngrok-skip-browser-warning` header is required, otherwise ngrok returns
///   its HTML interstitial page and the image fails to decode.
///
/// Solution:
///   - Mobile → [CachedNetworkImage] as usual (disk cache, etc.)
///   - Web    → [Image.network] with explicit headers (browser handles caching)
class AppNetworkImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final Widget Function(BuildContext)? placeholder;
  final Widget Function(BuildContext)? errorWidget;
  final double? width;
  final double? height;

  const AppNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return _error(context);
    }

    if (kIsWeb) {
      return Image.network(
        url,
        fit: fit,
        width: width,
        height: height,
        headers: Map<String, String>.from(ApiConfig.defaultHeaders),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _loading(context);
        },
        errorBuilder: (context, _, __) => _error(context),
      );
    }

    // Mobile — use CachedNetworkImage for disk caching
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      placeholder: placeholder != null ? (context, _) => placeholder!(context) : (context, _) => _loading(context),
      errorWidget:
          errorWidget != null ? (context, _, __) => errorWidget!(context) : (context, _, __) => _error(context),
    );
  }

  Widget _loading(BuildContext context) =>
      placeholder?.call(context) ??
      const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD4AF37)),
        ),
      );

  Widget _error(BuildContext context) =>
      errorWidget?.call(context) ??
      const ColoredBox(
        color: Color(0xFFF0EDE6),
        child: Center(
          child: Icon(Icons.image_outlined, color: Color(0xFF9E9E9E), size: 22),
        ),
      );
}
