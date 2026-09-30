// In-app preview of a .docx on Flutter web.
//
// Renders the file with docx-preview (the same renderer the Eve dev tool uses)
// inside a sandboxed iframe, loaded from jsDelivr. The bytes are posted into
// the iframe once it has loaded, so nothing is uploaded anywhere.
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:universal_html/html.dart' as html;

const String _previewHtml = '''
<!doctype html>
<html><head><meta charset="utf-8">
<script src="https://cdn.jsdelivr.net/npm/jszip@3.10.1/dist/jszip.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/docx-preview@0.4.1/dist/docx-preview.min.js"></script>
<style>
  html, body { margin: 0; background: #F4F6F8; }
  #status { font: 13px -apple-system, "Segoe UI", sans-serif; color: #637381; padding: 32px; text-align: center; }
  .docx-wrapper { background: #F4F6F8 !important; padding: 24px !important; }
  .docx-wrapper > section.docx { box-shadow: 0 1px 3px rgba(0,0,0,.12) !important; margin-bottom: 24px !important; }
</style>
</head><body>
<div id="status">Loading preview…</div>
<div id="container"></div>
<script>
  // Scale pages down to the frame width (Word pages are ~816px wide).
  function fit() {
    var container = document.getElementById('container');
    var page = container.querySelector('section.docx');
    if (!page) return;
    container.style.zoom = '';
    var scale = Math.min(1, (window.innerWidth - 48) / page.offsetWidth);
    container.style.zoom = scale < 1 ? String(scale) : '';
  }
  window.addEventListener('resize', fit);
  window.addEventListener('message', function (event) {
    // jszip/docx-preview use window.postMessage (strings) internally as a
    // setImmediate shim: only binary payloads are documents from the app.
    var data = event.data;
    if (!data || !(data instanceof ArrayBuffer || ArrayBuffer.isView(data))) return;
    var status = document.getElementById('status');
    var container = document.getElementById('container');
    if (!window.docx) {
      status.textContent = 'Preview is unavailable (the renderer did not load). Download the .docx instead.';
      return;
    }
    container.innerHTML = '';
    docx.renderAsync(new Blob([data]), container, null, {
      inWrapper: true,
      ignoreLastRenderedPageBreak: true,
      experimental: true
    }).then(function () {
      status.style.display = 'none';
      fit();
    }).catch(function (error) {
      status.textContent = 'Preview failed: ' + (error && error.message ? error.message : error);
    });
  });
</script>
</body></html>
''';

int _viewCounter = 0;

class DocxPreviewView extends StatefulWidget {
  final Uint8List bytes;

  const DocxPreviewView({super.key, required this.bytes});

  @override
  State<DocxPreviewView> createState() => _DocxPreviewViewState();
}

class _DocxPreviewViewState extends State<DocxPreviewView> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'span-docx-preview-${_viewCounter++}';
    final iframe = html.IFrameElement()
      ..srcdoc = _previewHtml
      ..setAttribute('sandbox', 'allow-scripts')
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%';
    final bytes = widget.bytes;
    iframe.onLoad.first.then((_) {
      iframe.contentWindow?.postMessage(bytes, '*');
    });
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) => iframe);
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
