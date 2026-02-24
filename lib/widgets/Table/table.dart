import 'package:flutter/material.dart';

enum SortOrder { asc, desc, original }

class TableColumn<T> {
  final String title;
  final Widget Function(T) builder;
  final int flex;
  final double minWidth;
  final bool sortable;
  final Comparable Function(T)? sortValue;

  TableColumn({
    required this.title,
    required this.builder,
    this.flex = 1,
    this.minWidth = 120,
    this.sortable = false,
    this.sortValue,
  });
}

class CommonTable<T> extends StatefulWidget {
  final List<T> data;
  final List<TableColumn<T>> columns;
  final bool showCheckboxes;
  final int rowsPerPage;

  const CommonTable({
    super.key,
    required this.data,
    required this.columns,
    this.showCheckboxes = true,
    this.rowsPerPage = 10,
  });

  @override
  State<CommonTable<T>> createState() => _CommonTableState<T>();
}

class _CommonTableState<T> extends State<CommonTable<T>> {
  final Set<T> _selectedItems = {};
  int _currentPage = 0;
  
  int? _sortColumnIndex;
  SortOrder _sortOrder = SortOrder.original;

  List<T> get _processedData {
    // 1. Guard against null or empty data
    if (widget.data.isEmpty) return [];

    List<T> list = List.from(widget.data);

    // 2. Sorting with Null-Safety
    if (_sortColumnIndex != null && _sortOrder != SortOrder.original) {
      final col = widget.columns[_sortColumnIndex!];
      if (col.sortValue != null) {
        list.sort((a, b) {
          final aVal = col.sortValue!(a);
          final bVal = col.sortValue!(b);
          // Comparable.compare handles the actual comparison logic
          return _sortOrder == SortOrder.asc 
              ? Comparable.compare(aVal, bVal) 
              : Comparable.compare(bVal, aVal);
        });
      }
    }

    // 3. Pagination with Bounds Safety
    int start = _currentPage * widget.rowsPerPage;
    if (start >= list.length) start = 0; // Reset if search results shrink
    
    int end = start + widget.rowsPerPage;
    return list.sublist(start, end > list.length ? list.length : end);
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
    final isDark = theme.brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        double totalMinWidth = widget.columns.fold(0.0, (sum, col) => sum + col.minWidth);
        if (widget.showCheckboxes) totalMinWidth += 60;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: SizedBox(
              width: constraints.maxWidth < totalMinWidth ? totalMinWidth : constraints.maxWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // --- HEADER ---
                  _buildHeader(theme, colorScheme, isDark),
                  
                  // --- DATA ROWS
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: displayData.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: colorScheme.outlineVariant.withOpacity(0.2)),
                    itemBuilder: (context, index) {
                      final item = displayData[index];
                      final isSelected = _selectedItems.contains(item);
                      return _buildRow(item, isSelected, theme, colorScheme);
                    },
                  ),

                  // --- FOOTER ---
                  _buildPaginationFooter(theme, colorScheme),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme colorScheme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        // color: Color(isDark ? 0xFF1E1E1E : 0xFFF5F5F5),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          if (widget.showCheckboxes) ...[
            SizedBox(
              height: 24, width: 24,
              child: Checkbox(
                value: widget.data.isNotEmpty && _selectedItems.length == widget.data.length,
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _selectedItems.addAll(widget.data);
                    } else {
                      _selectedItems.clear();
                    }
                  });
                },
                activeColor: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
          ],
          ...widget.columns.asMap().entries.map((entry) {
            int idx = entry.key;
            var col = entry.value;
            return Expanded(
              flex: col.flex,
              child: InkWell(
                onTap: col.sortable ? () => _handleSort(idx) : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(col.title, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant)),
                    if (col.sortable) ...[
                      const SizedBox(width: 4),
                      _buildSortIcon(idx, colorScheme),
                    ],
                  ],
                ),
              ),
            );
          }),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildRow(T item, bool isSelected, ThemeData theme, ColorScheme colorScheme) {
    return InkWell(
      onTap: widget.showCheckboxes ? null : () {}, // Row click logic if needed
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        // High-contrast primary highlight for selected rows
        color: isSelected ? colorScheme.primary.withOpacity(0.08) : Colors.transparent,
        child: Row(
          children: [
            if (widget.showCheckboxes) ...[
              SizedBox(
                height: 24, width: 24,
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
            ...widget.columns.map((col) => Expanded(
              flex: col.flex, 
              child: col.builder(item)
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildSortIcon(int index, ColorScheme colorScheme) {
    bool isCurrent = _sortColumnIndex == index && _sortOrder != SortOrder.original;
    return Icon(
      !isCurrent ? Icons.unfold_more : (_sortOrder == SortOrder.asc ? Icons.arrow_upward : Icons.arrow_downward),
      size: 20, 
      color: isCurrent ? colorScheme.primary : colorScheme.onSurfaceVariant.withOpacity(0.3)
    );
  }

  Widget _buildPaginationFooter(ThemeData theme, ColorScheme colorScheme) {
    final int total = widget.data.length;
    final int start = total == 0 ? 0 : (_currentPage * widget.rowsPerPage) + 1;
    final int end = (start + widget.rowsPerPage - 1) > total ? total : (start + widget.rowsPerPage - 1);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.3)))
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text("Rows per page: ${widget.rowsPerPage}", style: theme.textTheme.bodyMedium),
          const SizedBox(width: 24),
          Text("$start–$end of $total", style: theme.textTheme.bodyMedium),
          const SizedBox(width: 12),
          IconButton(
            onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null, 
            icon: const Icon(Icons.chevron_left, size: 24)
          ),
          IconButton(
            onPressed: end < total ? () => setState(() => _currentPage++) : null, 
            icon: const Icon(Icons.chevron_right, size: 24)
          ),
        ],
      ),
    );
  }
}