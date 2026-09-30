import 'package:flutter/material.dart';
import '../models/report_element.dart';

class ElementToolsPanel extends StatelessWidget {
  final bool hasHeader;
  final bool hasFooter;
  final Set<String> addedBandElements;
  final ValueChanged<ReportElementType> onAddElement;
  final ValueChanged<int>? onAddHeaderStyle;
  final ValueChanged<int>? onAddFooterStyle;
  final ValueChanged<String>? onAddBandElement;

  const ElementToolsPanel({
    super.key,
    required this.hasHeader,
    required this.hasFooter,
    required this.addedBandElements,
    required this.onAddElement,
    this.onAddHeaderStyle,
    this.onAddFooterStyle,
    this.onAddBandElement,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionLabel(theme, "Report Structure"),
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: true,
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text(
                "Header Templates",
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              children: [
                _TemplateStyleButton(theme: theme, style: 1, label: "Style 1 (Standard)", icon: Icons.view_headline_rounded, onAddStyle: onAddHeaderStyle),
                _TemplateStyleButton(theme: theme, style: 2, label: "Style 2 (Centered)", icon: Icons.view_headline_rounded, onAddStyle: onAddHeaderStyle),
                _TemplateStyleButton(theme: theme, style: 3, label: "Style 3 (Minimal)", icon: Icons.view_headline_rounded, onAddStyle: onAddHeaderStyle),
                _TemplateStyleButton(theme: theme, style: 4, label: "Style 4 (Bold)", icon: Icons.view_headline_rounded, onAddStyle: onAddHeaderStyle),
                _TemplateStyleButton(theme: theme, style: 5, label: "Style 5 (Modern)", icon: Icons.view_headline_rounded, onAddStyle: onAddHeaderStyle),
              ],
            ),
          ),
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: true,
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text(
                "Footer Templates",
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              children: [
                _TemplateStyleButton(theme: theme, style: 1, label: "Style 1 (Standard)", icon: Icons.view_stream_rounded, onAddStyle: onAddFooterStyle),
                _TemplateStyleButton(theme: theme, style: 2, label: "Style 2 (Centered)", icon: Icons.view_stream_rounded, onAddStyle: onAddFooterStyle),
                _TemplateStyleButton(theme: theme, style: 3, label: "Style 3 (Minimal)", icon: Icons.view_stream_rounded, onAddStyle: onAddFooterStyle),
                _TemplateStyleButton(theme: theme, style: 4, label: "Style 4 (Bold)", icon: Icons.view_stream_rounded, onAddStyle: onAddFooterStyle),
                _TemplateStyleButton(theme: theme, style: 5, label: "Style 5 (Modern)", icon: Icons.view_stream_rounded, onAddStyle: onAddFooterStyle),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionLabel(theme, "Band Elements"),
          _CustomToolButton(
            icon: Icons.workspace_premium_outlined,
            label: 'Logo',
            enabled: !addedBandElements.contains('logo'),
            onTap: () => onAddBandElement?.call('logo'),
          ),
          _CustomToolButton(
            icon: Icons.business_rounded,
            label: 'Company Name',
            enabled: !addedBandElements.contains('companyName'),
            onTap: () => onAddBandElement?.call('companyName'),
          ),
          _CustomToolButton(
            icon: Icons.location_on_rounded,
            label: 'Address',
            enabled: !addedBandElements.contains('address'),
            onTap: () => onAddBandElement?.call('address'),
          ),
          _CustomToolButton(
            icon: Icons.event_note_rounded,
            label: 'Info Bar',
            enabled: !addedBandElements.contains('infoBar'),
            onTap: () => onAddBandElement?.call('infoBar'),
          ),
          _CustomToolButton(
            icon: Icons.pin_rounded,
            label: 'Page Number',
            enabled: !addedBandElements.contains('pageNumber'),
            onTap: () => onAddBandElement?.call('pageNumber'),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _CustomToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _CustomToolButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: enabled ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: enabled ? colorScheme.onSurface : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.add_rounded,
                  size: 16,
                  color: enabled ? colorScheme.onSurfaceVariant.withValues(alpha: 0.6) : colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplateStyleButton extends StatelessWidget {
  final ThemeData theme;
  final int style;
  final String label;
  final IconData icon;
  final ValueChanged<int>? onAddStyle;

  const _TemplateStyleButton({
    required this.theme,
    required this.style,
    required this.label,
    required this.icon,
    required this.onAddStyle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onAddStyle?.call(style),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
