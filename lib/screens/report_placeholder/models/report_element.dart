import 'package:flutter/material.dart';

enum ReportElementType { header, footer, bodyContent, text, logo, pageNumber, infoBar }

extension ReportElementTypeLabel on ReportElementType {
  String get label {
    switch (this) {
      case ReportElementType.header:
        return 'Header';
      case ReportElementType.footer:
        return 'Footer';
      case ReportElementType.bodyContent:
        return 'Body Content';
      case ReportElementType.text:
        return 'Text';
      case ReportElementType.logo:
        return 'Logo';
      case ReportElementType.pageNumber:
        return 'Page Number';
      case ReportElementType.infoBar:
        return 'Info Bar';
    }
  }

  IconData get icon {
    switch (this) {
      case ReportElementType.header:
        return Icons.view_headline_rounded;
      case ReportElementType.footer:
        return Icons.view_stream_rounded;
      case ReportElementType.bodyContent:
        return Icons.article_rounded;
      case ReportElementType.text:
        return Icons.notes_rounded;
      case ReportElementType.logo:
        return Icons.workspace_premium_outlined;
      case ReportElementType.pageNumber:
        return Icons.pin_rounded;
      case ReportElementType.infoBar:
        return Icons.event_note_rounded;
    }
  }

  /// Elements whose text content can be edited via the generic text toolbar
  /// (bold/italic/underline/align/font size/color). infoBar has editable text
  /// too but through its own dedicated bg+text-color toolbar instead.
  bool get hasEditableText =>
      this == ReportElementType.header ||
      this == ReportElementType.footer ||
      this == ReportElementType.bodyContent ||
      this == ReportElementType.text ||
      this == ReportElementType.pageNumber;

  /// Logo/Page Number live inside the header or footer band rather than the
  /// open page body — dragging them is constrained to whichever band they're
  /// closer to instead of the whole page.
  bool get isBandElement =>
      this == ReportElementType.logo || this == ReportElementType.pageNumber;
}

class ReportElement {
  final String id;
  final ReportElementType type;
  final String? toolType;
  String text;

  /// Only used by [ReportElementType.infoBar]: the right-side label (e.g.
  /// Inspector Name) alongside [text] used as the left-side label (e.g. Date).
  String secondaryText;

  Offset position;
  Size size;
  double fontSize;
  bool isBold;
  bool isItalic;
  bool isUnderline;
  Color color;
  TextAlign align;
  Color backgroundColor;

  /// Header (and eventually Footer) act as small containers: Logo/Title/
  /// Description/Info-bar live here as their own independently movable/
  /// stylable elements, positioned relative to the container's own top-left.
  final List<ReportElement> children;

  ReportElement({
    required this.id,
    required this.type,
    required this.text,
    this.toolType,
    this.secondaryText = '',
    this.position = Offset.zero,
    Size? size,
    double? fontSize,
    bool? isBold,
    this.isItalic = false,
    this.isUnderline = false,
    this.color = Colors.black,
    this.align = TextAlign.left,
    this.backgroundColor = Colors.transparent,
    List<ReportElement>? children,
  }) : size = size ?? _defaultSize(type),
       fontSize = fontSize ?? _defaultFontSize(type),
       isBold = isBold ?? _defaultIsBold(type),
       children = children ?? [];

  static double _defaultFontSize(ReportElementType type) {
    switch (type) {
      case ReportElementType.header:
        return 12;
      case ReportElementType.footer:
        return 10;
      case ReportElementType.bodyContent:
        return 14;
      case ReportElementType.text:
        return 14;
      case ReportElementType.pageNumber:
        return 10;
      case ReportElementType.infoBar:
        return 11;
      case ReportElementType.logo:
        return 14;
    }
  }

  static bool _defaultIsBold(ReportElementType type) {
    return false;
  }

  static Size _defaultSize(ReportElementType type) {
    switch (type) {
      case ReportElementType.bodyContent:
        return const Size(720, 300);
      case ReportElementType.logo:
        return const Size(70, 70);
      case ReportElementType.header:
        // Tall enough that the default Logo (70px) and Description don't
        // collide with the bottom info bar (28px).
        return const Size(0, 130);
      case ReportElementType.footer:
        return const Size(0, 60);
      case ReportElementType.infoBar:
        return const Size(0, 28);
      default:
        return Size.zero;
    }
  }

  bool get isPinned =>
      type == ReportElementType.header || type == ReportElementType.footer;

  bool get isContainer =>
      type == ReportElementType.header || type == ReportElementType.footer;

  ReportElement copyWith({required String id, Offset? position}) {
    return ReportElement(
      id: id,
      type: type,
      text: 'Copy of $text',
      toolType: toolType,
      secondaryText: secondaryText,
      position: position ?? this.position,
      size: size,
      fontSize: fontSize,
      isBold: isBold,
      isItalic: isItalic,
      isUnderline: isUnderline,
      color: color,
      align: align,
      backgroundColor: backgroundColor,
      children: children
          .map((c) => c.copyWith(id: '${id}_${c.id}'))
          .toList(),
    );
  }
}
