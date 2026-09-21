import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../core/api_service.dart';
import '../../core/theme_controller.dart';
import '../../services/toast_service.dart';
import '../../utils/app_responsive.dart';
import '../../widgets/button/button.dart';
import '../../widgets/form_components/text_field.dart';
import '../auth/controllers/auth_controller.dart';

enum _SettingsSection { general, company }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _SettingsSection _selectedSection = _SettingsSection.general;

  final _companyDetailsFormKey = GlobalKey<FormState>();
  final TextEditingController _companyNameController = TextEditingController();
  Uint8List? _companyLogoBytes;
  String? _pickedLogoContentType;
  String? _existingLogoUrl;
  bool _isSavingCompanyDetails = false;

  @override
  void initState() {
    super.initState();
    final company = authController.user?.company;
    _companyNameController.text = company?.name ?? '';
    _existingLogoUrl = company?.logo;
    _fetchCompanyLogo();
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    super.dispose();
  }

  Future<void> _fetchCompanyLogo() async {
    final companyId = authController.user?.companyId;
    if (companyId == null || companyId.isEmpty) return;

    try {
      final response = await apiService.get('/presignedurl/company-logo/$companyId');
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      final signedUrl = data['signedUrl'];
      if (signedUrl == null || signedUrl is! String || signedUrl.isEmpty) return;

      if (!mounted) return;
      setState(() => _existingLogoUrl = signedUrl);
    } catch (_) {
      // Keep whatever logo we already have (from the user payload, or the placeholder).
    }
  }

  Future<void> _pickCompanyLogo() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (image == null) return;

    final bytes = await image.readAsBytes();
    setState(() {
      _companyLogoBytes = bytes;
      _pickedLogoContentType = image.mimeType ?? _guessContentType(image.name);
    });
  }

  String _guessContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _updateCompanyDetails() async {
    if (!_companyDetailsFormKey.currentState!.validate()) return;

    final name = _companyNameController.text.trim();
    setState(() => _isSavingCompanyDetails = true);

    try {
      String? logoKey;

      if (_companyLogoBytes != null) {
        final contentType = _pickedLogoContentType ?? 'image/jpeg';

        // Step 1: Ask the backend for a presigned S3 PUT URL.
        final presignResponse = await apiService.get('/presignedurl/company-logo');

        if (presignResponse.statusCode != 200 && presignResponse.statusCode != 201) {
          throw Exception("Failed to prepare company logo upload.");
        }

        final presignData = jsonDecode(presignResponse.body);
        final signedUrl = presignData['signedUrl'];
        logoKey = presignData['key'];
        if (signedUrl == null || logoKey == null) {
          throw Exception("Failed to prepare company logo upload.");
        }

        // Step 2: Upload the actual image bytes directly to S3 using that URL.
        final s3Response = await http.put(
          Uri.parse(signedUrl),
          headers: {'Content-Type': contentType},
          body: _companyLogoBytes,
        );

        if (s3Response.statusCode != 200) {
          throw Exception("Failed to upload company logo.");
        }
      }

      final updateResponse = await apiService.patch('/company/updateData', {
        "name": name,
        if (logoKey != null) "logo": logoKey,
      });

      if (updateResponse.statusCode != 200) {
        throw Exception("Failed to update company details.");
      }

      // Refresh cached user/company data and the displayed logo (a fresh signed URL).
      await authController.fetchUserDetails();
      if (!mounted) return;
      setState(() {
        _companyLogoBytes = null;
        _pickedLogoContentType = null;
      });
      await _fetchCompanyLogo();

      if (!mounted) return;
      ToastService.show(context, message: "Company details updated.", type: ToastType.success);
    } catch (e) {
      if (!mounted) return;
      ToastService.show(context, message: "Failed to update company details. Please try again.", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isSavingCompanyDetails = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final isMobile = AppResponsive.isMobileScreen(context);

        final content = isMobile
            ? _buildMobileLayout(theme, colorScheme)
            : _buildDesktopLayout(theme, colorScheme);

        return Scaffold(
          // Uses transparent to seamlessly blend into your MainScaffold's background
          backgroundColor: Colors.transparent,
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: content,
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopLayout(ThemeData theme, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: _buildSideMenu(theme, colorScheme),
          ),
          const SizedBox(width: 40),
          Expanded(
            child: _buildSectionContent(theme, colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(ThemeData theme, ColorScheme colorScheme) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: [
        _buildSideMenu(theme, colorScheme, horizontal: true),
        const SizedBox(height: 32),
        _buildSectionContent(theme, colorScheme),
      ],
    );
  }

  Widget _buildSideMenu(ThemeData theme, ColorScheme colorScheme, {bool horizontal = false}) {
    final items = [
      _NavItem(section: _SettingsSection.general, icon: Icons.tune_outlined, label: "General"),
      _NavItem(section: _SettingsSection.company, icon: Icons.apartment_outlined, label: "Company Details"),
    ];

    if (horizontal) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
        ),
        child: Row(
          children: items
              .map((item) => Expanded(child: _buildMenuTile(item, theme, colorScheme, compact: true)))
              .toList(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Settings",
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 24),
        ...items.map((item) => _buildMenuTile(item, theme, colorScheme)),
      ],
    );
  }

  Widget _buildMenuTile(_NavItem item, ThemeData theme, ColorScheme colorScheme, {bool compact = false}) {
    final isSelected = _selectedSection == item.section;
    final activeText = colorScheme.primary;
    final inactiveText = theme.textTheme.bodyMedium?.color?.withOpacity(0.6);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 0 : 2),
      child: InkWell(
        onTap: () => setState(() => _selectedSection = item.section),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(vertical: compact ? 12 : 12, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isSelected ? colorScheme.primary.withOpacity(0.08) : Colors.transparent,
          ),
          child: Row(
            mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(item.icon, size: 20, color: isSelected ? activeText : inactiveText),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  item.label,
                  style: TextStyle(
                    color: isSelected ? activeText : inactiveText,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionContent(ThemeData theme, ColorScheme colorScheme) {
    switch (_selectedSection) {
      case _SettingsSection.general:
        return _buildGeneralSettings(theme, colorScheme);
      case _SettingsSection.company:
        return _buildCompanyDetails(theme, colorScheme);
    }
  }

  // =====================================
  // General Settings
  // =====================================
  Widget _buildGeneralSettings(ThemeData theme, ColorScheme colorScheme) {
    final List<Color> accentColors = [
      const Color(0xFF1C58F6), const Color(0xFF00AB55), const Color(0xFF7635DC),
      const Color(0xFFFDA92D), const Color(0xFFFF3030),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "General Settings",
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "Manage your app appearance and preferences.",
          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 14),
        ),
        const SizedBox(height: 32),
        _buildSectionHeader("Appearance Mode", theme),
        _buildThemeToggle(colorScheme),
        const SizedBox(height: 40),
        _buildSectionHeader("Presets", theme),
        _buildColorGrid(accentColors, colorScheme),
      ],
    );
  }

  Widget _buildThemeToggle(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          _modeButton("Light", Icons.light_mode_outlined, ThemeMode.light),
          _modeButton("Dark", Icons.dark_mode_outlined, ThemeMode.dark),
          _modeButton("System", Icons.settings_brightness_outlined, ThemeMode.system),
        ],
      ),
    );
  }

  Widget _modeButton(String label, IconData icon, ThemeMode mode) {
    bool active = themeController.themeMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => themeController.setThemeMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: active ? themeController.targetColor : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: active
                ? [BoxShadow(color: themeController.targetColor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]
                : null,
          ),
          child: Column(
            children: [
              Icon(icon, size: 22, color: active ? Colors.white : Colors.grey),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(
                color: active ? Colors.white : Colors.grey,
                fontSize: 13,
                fontWeight: active ? FontWeight.bold : FontWeight.w600
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorGrid(List<Color> colors, ColorScheme colorScheme) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: colors.map((color) {
        bool selected = themeController.targetColor.value == color.value;
        return GestureDetector(
          onTap: () => themeController.setTargetColor(color),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? colorScheme.onSurface : Colors.transparent,
                width: 2
              ),
              boxShadow: selected
                  ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))]
                  : [],
            ),
            child: selected ? const Icon(Icons.check, color: Colors.white, size: 24) : null,
          ),
        );
      }).toList(),
    );
  }

  // =====================================
  // Company Details
  // =====================================
  Widget _buildCompanyDetails(ThemeData theme, ColorScheme colorScheme) {
    return Form(
      key: _companyDetailsFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Company Details",
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Update your company logo and name.",
            style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 14),
          ),
          const SizedBox(height: 32),
          _buildSectionHeader("Company Logo", theme),
          _buildLogoPicker(theme, colorScheme),
          const SizedBox(height: 40),
          _buildSectionHeader("Company Name *", theme),
          FormControlTextField(
            controller: _companyNameController,
            hintText: "Enter company name",
            prefixIcon: Icons.apartment_outlined,
            textInputAction: TextInputAction.done,
            validator: (value) => (value == null || value.trim().isEmpty) ? "Company name is required" : null,
          ),
          const SizedBox(height: 32),
          _buildUpdateButton(colorScheme),
        ],
      ),
    );
  }

  Widget _buildLogoPicker(ThemeData theme, ColorScheme colorScheme) {
    final hasExistingLogo = _existingLogoUrl != null && _existingLogoUrl!.isNotEmpty;
    final ImageProvider? logoImage = _companyLogoBytes != null
        ? MemoryImage(_companyLogoBytes!)
        : (hasExistingLogo ? NetworkImage(_existingLogoUrl!) : null);

    return Row(
      children: [
        GestureDetector(
          onTap: _pickCompanyLogo,
          child: Stack(
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.surfaceVariant.withOpacity(0.5),
                  border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
                  image: logoImage != null ? DecorationImage(image: logoImage, fit: BoxFit.cover) : null,
                ),
                child: logoImage == null
                    ? Icon(Icons.apartment_outlined, size: 32, color: colorScheme.onSurface.withOpacity(0.4))
                    : null,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary,
                    border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                  ),
                  child: const Icon(Icons.edit, size: 13, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Text(
          "Click on the logo to change it.\nPNG or JPG",
          style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withOpacity(0.5)),
        ),
      ],
    );
  }

  Widget _buildUpdateButton(ColorScheme colorScheme) {
    return Button(
      label: "Update",
      onPressed: _updateCompanyDetails,
      isLoading: _isSavingCompanyDetails,
      color: colorScheme.primary,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: theme.colorScheme.onSurface.withOpacity(0.5),
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5
        ),
      ),
    );
  }
}

class _NavItem {
  final _SettingsSection section;
  final IconData icon;
  final String label;

  const _NavItem({required this.section, required this.icon, required this.label});
}
