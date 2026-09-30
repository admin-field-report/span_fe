import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Non-web fallback: the in-app .docx preview uses a browser renderer.
class DocxPreviewView extends StatelessWidget {
  final Uint8List bytes;

  const DocxPreviewView({super.key, required this.bytes});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        'Template preview is available in the web app. Download the .docx to view it.',
        textAlign: TextAlign.center,
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
