import 'package:flutter/material.dart';
import '../services/db.dart';

/// Thumbnail for a photo in the private diagnosis-images bucket (signed URL).
class StorageImage extends StatefulWidget {
  final String path;
  final double size;
  const StorageImage({super.key, required this.path, this.size = 48});
  @override
  State<StorageImage> createState() => _StorageImageState();
}

class _StorageImageState extends State<StorageImage> {
  late final Future<String> _url = Db.i.signedUrl(widget.path);

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final placeholder = SizedBox(width: s, height: s, child: const Icon(Icons.image_outlined));
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: FutureBuilder<String>(
        future: _url,
        builder: (_, snap) => snap.hasData
            ? Image.network(
                snap.data!,
                width: s,
                height: s,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => placeholder,
              )
            : placeholder,
      ),
    );
  }
}
