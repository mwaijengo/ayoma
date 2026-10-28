import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../state/session.dart';
import '../theme.dart';
import 'common.dart';

/// Image URL field with an "Upload" button that stores the picked photo on
/// the server and fills in its URL, plus a live preview.
class ImageField extends StatefulWidget {
  const ImageField({
    super.key,
    required this.controller,
    this.aspectRatio = 16 / 9,
    this.validator,
    this.onChanged,
  });

  final TextEditingController controller;
  final double aspectRatio;
  final FormFieldValidator<String>? validator;
  final VoidCallback? onChanged;

  @override
  State<ImageField> createState() => _ImageFieldState();
}

class _ImageFieldState extends State<ImageField> {
  bool _uploading = false;

  bool get _hasImage {
    final uri = Uri.tryParse(widget.controller.text.trim());
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  static String _mimeFor(XFile file) {
    final type = file.mimeType;
    if (type != null && type.startsWith('image/')) return type;
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  Future<void> _upload() async {
    final api = SessionScope.read(context).api;
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    } catch (_) {
      if (mounted) toast(context, 'Could not open your photos.', error: true);
      return;
    }
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      final url = await api.uploadImage(bytes, _mimeFor(file));
      widget.controller.text = url;
      widget.onChanged?.call();
      if (mounted) toast(context, 'Image uploaded');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: widget.controller,
                validator: widget.validator,
                keyboardType: TextInputType.url,
                enabled: !_uploading,
                onChanged: (_) {
                  setState(() {});
                  widget.onChanged?.call();
                },
                decoration: const InputDecoration(
                  labelText: 'Image URL',
                  prefixIcon: Icon(LucideIcons.image, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 56,
              child: FilledButton.tonalIcon(
                onPressed: _uploading ? null : _upload,
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.green),
                      )
                    : const Icon(LucideIcons.upload, size: 18),
                label: Text(_uploading ? 'Uploading' : 'Upload'),
              ),
            ),
          ],
        ),
        if (_hasImage) ...[
          const SizedBox(height: 10),
          AspectRatio(
            aspectRatio: widget.aspectRatio,
            child: NetImage(widget.controller.text.trim(), radius: 14),
          ),
        ],
      ],
    );
  }
}
