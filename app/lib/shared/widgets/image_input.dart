import 'dart:io';

import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';

class ImageInput extends StatefulWidget {
  final File? file;
  final String? imageUrl;
  final ValueChanged<File?> onChanged;
  final String label;
  final double height;
  final bool isRequired;

  const ImageInput({
    super.key,
    this.file,
    this.imageUrl,
    required this.onChanged,
    this.label = "",
    this.height = 220,
    this.isRequired = false,
  });

  @override
  State<ImageInput> createState() => ImageInputState();
}

class ImageInputState extends State<ImageInput> {
  final ImagePicker _picker = ImagePicker();
  String? _errorText;

  bool get _hasImage => widget.file != null || widget.imageUrl != null;

  // ================= IMAGE PICK + CROP =================

  Future<void> _pickImage(ImageSource source) async {
    debugPrint('[ImageInput] _pickImage called, source: $source');
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 2048,
        maxHeight: 2048,
      );

      debugPrint('[ImageInput] picker result: ${picked?.path ?? 'null'}');
      if (picked == null) return;

      // Validate extension — be lenient on Android where camera paths vary
      final String extension = picked.path.toLowerCase().split('.').last;
      final bool hasKnownExtension = ['jpg', 'jpeg', 'png'].contains(extension);
      // Only reject if there's a clear non-image extension (not just an unknown temp path)
      if (!hasKnownExtension && extension.length <= 5 && extension.isNotEmpty) {
        // Check MIME type from XFile as fallback
        final String? mime = picked.mimeType;
        if (mime != null && !mime.startsWith('image/')) {
          setState(() => _errorText = 'Invalid file type. Only JPG and PNG are allowed.');
          return;
        }
      }

      // Crop the image
      final CroppedFile? cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Image',
            toolbarColor: AppTheme.gold,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: AppTheme.gold,
            lockAspectRatio: true,
          ),
          IOSUiSettings(
            title: 'Crop Image',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
          ),
          WebUiSettings(
            context: context,
            presentStyle: WebPresentStyle.dialog,
          ),
        ],
      );

      if (cropped == null) {
        debugPrint('[ImageInput] crop cancelled');
        return;
      }

      final File file = File(cropped.path);

      // Validate file size (5MB max)
      final int fileSize = await file.length();
      const int maxSize = 5 * 1024 * 1024;
      debugPrint('[ImageInput] file size: ${(fileSize / 1024).toStringAsFixed(1)} KB');

      if (fileSize > maxSize) {
        setState(() => _errorText = 'File size exceeds 5MB limit.');
        return;
      }

      debugPrint('[ImageInput] image accepted, calling onChanged');
      setState(() {
        _errorText = null;
        widget.onChanged(file);
      });
    } catch (e, stack) {
      debugPrint('[ImageInput] ERROR picking image: $e');
      debugPrint('[ImageInput] stack: $stack');
      setState(() => _errorText = 'Failed to pick image: $e');
    }
  }

  void _showPickOption() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text("Camera"),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text("Gallery"),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _removeImage() {
    widget.onChanged(null);
  }

  // ================= VALIDATION =================

  bool validate() {
    if (widget.isRequired && !_hasImage) {
      setState(() => _errorText = "Image is required");
      return false;
    }
    setState(() => _errorText = null);
    return true;
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    final borderColor = _errorText != null
        ? Colors.redAccent
        : Theme.of(context).colorScheme.outlineVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label.isNotEmpty)
          Text(
            widget.label,
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        if (widget.label.isNotEmpty) const SizedBox(height: 8),
        GestureDetector(
          onTap: _showPickOption,
          child: DottedBorder(
            color: borderColor,
            strokeWidth: 1.4,
            dashPattern: const [6, 4],
            borderType: BorderType.RRect,
            radius: const Radius.circular(20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                height: widget.height,
                width: double.infinity,
                color: Theme.of(context).colorScheme.surface,
                child: Stack(
                  children: [
                    _buildImage(),
                    if (_hasImage)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: GestureDetector(
                          onTap: _removeImage,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            _errorText!,
            style: const TextStyle(
              color: Colors.redAccent,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  // ================= IMAGE RENDER =================

  Widget _buildImage() {
    if (widget.file != null) {
      return Image.file(
        widget.file!,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
      );
    }

    if (widget.imageUrl != null) {
      return Image.network(
        widget.imageUrl!,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        },
        errorBuilder: (_, __, ___) {
          return const Center(
            child: Icon(
              Icons.broken_image_outlined,
              size: 40,
              color: AppTheme.mutedForeground,
            ),
          );
        },
      );
    }

    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_upload_outlined,
            size: 48,
            color: AppTheme.mutedForeground,
          ),
          SizedBox(height: 12),
          Text(
            "Tap to upload image",
            style: TextStyle(
              color: AppTheme.mutedForeground,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
