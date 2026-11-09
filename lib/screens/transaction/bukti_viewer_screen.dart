import 'package:flutter/material.dart';

class BuktiViewerScreen extends StatelessWidget {
  final List<String> urlFoto;
  final int indexAwal;

  const BuktiViewerScreen({super.key, required this.urlFoto, this.indexAwal = 0});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Bukti Transaksi'),
      ),
      body: PageView.builder(
        controller: PageController(initialPage: indexAwal),
        itemCount: urlFoto.length,
        itemBuilder: (ctx, i) {
          return InteractiveViewer(
            minScale: 0.8,
            maxScale: 4,
            child: Center(
              child: Image.network(
                urlFoto[i],
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return const CircularProgressIndicator(color: Colors.white);
                },
                errorBuilder: (ctx, err, st) =>
                    const Icon(Icons.broken_image, color: Colors.white54, size: 64),
              ),
            ),
          );
        },
      ),
    );
  }
}
