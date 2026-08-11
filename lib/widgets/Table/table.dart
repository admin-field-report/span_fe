import 'package:flutter/material.dart';

enum SortOrder { asc, desc, original }

class TableColumn<T> {
  final String title;
  final Widget Function(T) builder;
  final int flex;
  final double minWidth;
  final bool sortable;
  final Comparable Function(T)? sortValue;
  final bool isStickyRight; // 🚀 Keep this flag

  TableColumn({
    required this.title,
    required this.builder,
    this.flex = 1,
    this.minWidth = 120,
    this.sortable = false,
    this.sortValue,
    this.isStickyRight = false,
  });
}

class CommonTable<T> extends StatefulWidget {
  final bool isLoading;
  final List<T> data;
  final List<TableColumn<T>> columns;
  final bool showCheckboxes;
  final Function(T item)? onRowTap;

  const CommonTable({
    super.key,
    this.isLoading = false,
    required this.data,
    required this.columns,
    this.showCheckboxes = true,
    this.onRowTap,
  });

  @override
  State<CommonTable<T>> createState() => _CommonTableState<T>();
}

class _CommonTableState<T> extends State<CommonTable<T>> {
  final Set<T> _selectedItems = {};
  int? _sortColumnIndex;
  SortOrder _sortOrder = SortOrder.original;

  // 🚀 These controllers perfectly sync the horizontal scrolling!
  final ScrollController _headerHorizontalController = ScrollController();
  final ScrollController _bodyHorizontalController = ScrollController();

  @override
  void dispose() {
    _headerHorizontalController.dispose();
    _bodyHorizontalController.dispose();
    super.dispose();
  }

  List<T> get _processedData {
    if (widget.data.isEmpty) return [];
    List<T> list = List.from(widget.data);

    if (_sortColumnIndex != null && _sortOrder != SortOrder.original) {
      final col = widget.columns[_sortColumnIndex!];
      if (col.sortValue != null) {
        list.sort((a, b) {
          final aVal = col.sortValue!(a);
          final bVal = col.sortValue!(b);
          return _sortOrder == SortOrder.asc
              ? Comparable.compare(aVal, bVal)
              : Comparable.compare(bVal, aVal);
        });
      }
    }
    return list;
  }

  void _handleSort(int index) {
    setState(() {
      if (_sortColumnIndex == index) {
        if (_sortOrder == SortOrder.asc) _sortOrder = SortOrder.desc;
        else if (_sortOrder == SortOrder.desc) _sortOrder = SortOrder.original;
        else _sortOrder = SortOrder.asc;
      } else {
        _sortColumnIndex = index;
        _sortOrder = SortOrder.asc;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayData = _processedData;

    if (widget.isLoading) return _buildLoadingState(theme, colorScheme);
    if (widget.data.isEmpty) return _buildEmptyState(theme, colorScheme);

    // Split columns into scrollable and sticky
    final regularColumns = widget.columns.where((c) => !c.isStickyRight).toList();
    final stickyColumns = widget.columns.where((c) => c.isStickyRight).toList();

    return Flexible(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate precise widths to ensure perfect layout
          double stickyWidth = stickyColumns.isNotEmpty 
              ? stickyColumns.fold(0.0, (sum, col) => sum + col.minWidth) + 32.0 
              : 0.0;
              
          double remainingWidth = constraints.maxWidth - stickyWidth;
          double mainMinWidth = regularColumns.fold(0.0, (sum, col) => sum + col.minWidth) + (widget.showCheckboxes ? 60 : 0);
          double mainWidth = remainingWidth < mainMinWidth ? mainMinWidth : remainingWidth;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ------------------------------------------------------------------
              // 1. THE HEADER (Fixed vertically, synced horizontally)
              // ------------------------------------------------------------------
              Row(
                children: [
                  Expanded(
                    child: NotificationListener<ScrollUpdateNotification>(
                      onNotification: (notification) {
                        if (notification.depth == 0 && _bodyHorizontalController.hasClients) {
                          if (_bodyHorizontalController.offset != notification.metrics.pixels) {
                            _bodyHorizontalController.jumpTo(notification.metrics.pixels);
                          }
                        }
                        return false;
                      },
                      child: SingleChildScrollView(
                        controller: _headerHorizontalController,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: mainWidth,
                          child: _buildHeaderRow(regularColumns, theme, colorScheme),
                        ),
                      ),
                    ),
                  ),
                  if (stickyColumns.isNotEmpty)
                    SizedBox(
                      width: stickyWidth,
                      child: _buildHeaderRow(stickyColumns, theme, colorScheme, isSticky: true),
                    ),
                ],
              ),

              // ------------------------------------------------------------------
              // 2. THE BODY (Scrolls vertically as ONE unit)
              // ------------------------------------------------------------------
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Scrollable Main Columns
                      Expanded(
                        child: NotificationListener<ScrollUpdateNotification>(
                          onNotification: (notification) {
                            if (notification.depth == 0 && _headerHorizontalController.hasClients) {
                              if (_headerHorizontalController.offset != notification.metrics.pixels) {
                                _headerHorizontalController.jumpTo(notification.metrics.pixels);
                              }
                            }
                            return false;
                          },
                          child: SingleChildScrollView(
                            controller: _bodyHorizontalController,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: mainWidth,
                              child: Column(
                                children: displayData.map((item) {
                                  final isSelected = _selectedItems.contains(item);
                                  // RepaintBoundary lets the compositor reuse each
                                  // rasterized row while scrolling this non-lazy list.
                                  return RepaintBoundary(
                                    child: Column(
                                      children: [
                                        _buildDataRow(item, isSelected, theme, colorScheme, regularColumns),
                                        Divider(height: 1, color: colorScheme.outlineVariant.withOpacity(0.2)),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ),
                      
                      // Sticky Action Columns
                      if (stickyColumns.isNotEmpty)
                        SizedBox(
                          width: stickyWidth,
                          child: Column(
                            children: displayData.map((item) {
                              final isSelected = _selectedItems.contains(item);
                              return RepaintBoundary(
                                child: Column(
                                  children: [
                                    // 🚀 Passes the sticky flag to ensure it renders transparent/correctly
                                    _buildDataRow(item, isSelected, theme, colorScheme, stickyColumns, isSticky: true),
                                    Divider(height: 1, color: colorScheme.outlineVariant.withOpacity(0.2)),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- REBUILT HELPERS WITH FIXED HEIGHTS TO ENSURE LEFT/RIGHT ALIGNMENT ---

  Widget _buildHeaderRow(List<TableColumn<T>> cols, ThemeData theme, ColorScheme colorScheme, {bool isSticky = false}) {
    return Container(
      height: 56, // Fixed height guarantees alignment
      padding: EdgeInsets.symmetric(horizontal: isSticky ? 16 : 17),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5))),
      ),
      child: Row(
        children: [
          if (!isSticky && widget.showCheckboxes) ...[
            _buildCheckboxContainer(
              child: Checkbox(
                value: widget.data.isNotEmpty && _selectedItems.length == widget.data.length,
                onChanged: (val) {
                  setState(() {
                    if (val == true) _selectedItems.addAll(widget.data);
                    else _selectedItems.clear();
                  });
                },
                activeColor: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
          ],
          ...cols.map((col) {
            int idx = widget.columns.indexOf(col);
            return Expanded(
              flex: col.flex,
              child: InkWell(
                onTap: col.sortable ? () => _handleSort(idx) : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      col.title,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (col.sortable) ...[
                      const SizedBox(width: 4),
                      _buildSortIcon(idx, colorScheme),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDataRow(T item, bool isSelected, ThemeData theme, ColorScheme colorScheme, List<TableColumn<T>> cols, {bool isSticky = false}) {
    return InkWell(
      onTap: widget.onRowTap != null ? () => widget.onRowTap!(item) : null,
      child: Container(
        height: 64, // Fixed height guarantees alignment across split lists
        padding: EdgeInsets.symmetric(horizontal: isSticky ? 16 : 20),
        
        // 🚀 PERFECT COLORS: Now uses your exact original hover/selection logic for BOTH sides!
        color: isSelected ? colorScheme.primary.withOpacity(0.08) : Colors.transparent,
        
        child: Row(
          children: [
            if (!isSticky && widget.showCheckboxes) ...[
              _buildCheckboxContainer(
                child: Checkbox(
                  value: isSelected,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) _selectedItems.add(item);
                      else _selectedItems.remove(item);
                    });
                  },
                  activeColor: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
            ],
            ...cols.map((col) => Expanded(
              flex: col.flex,
              child: Align(
                alignment: Alignment.centerLeft,
                child: col.builder(item),
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckboxContainer({required Widget child}) {
    return SizedBox(height: 24, width: 24, child: child);
  }

  Widget _buildSortIcon(int index, ColorScheme colorScheme) {
    bool isCurrent = _sortColumnIndex == index && _sortOrder != SortOrder.original;
    return Icon(
      !isCurrent ? Icons.unfold_more : (_sortOrder == SortOrder.asc ? Icons.arrow_upward : Icons.arrow_downward),
      size: 16,
      color: isCurrent ? colorScheme.primary : colorScheme.onSurfaceVariant.withOpacity(0.3),
    );
  }

  Widget _buildLoadingState(ThemeData theme, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(60.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            "Loading data...",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeaderRow(widget.columns, theme, colorScheme),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 80.0, horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.inventory_2_outlined, 
                  size: 64, 
                  color: colorScheme.onSurfaceVariant.withOpacity(0.2)
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "No Records Found", 
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant, 
                  fontWeight: FontWeight.w600
                )
              ),
            ],
          ),
        ),
      ],
    );
  }
}