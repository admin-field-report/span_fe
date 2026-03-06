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
  final bool isLoading;
  final List<T> data;
  final List<TableColumn<T>> columns;
  final bool showCheckboxes;
  final int rowsPerPage;
  final Function(T item)? onRowTap;

  const CommonTable({
    super.key,
    this.isLoading = false,
    required this.data,
    required this.columns,
    this.showCheckboxes = true,
    this.rowsPerPage = 10,
    this.onRowTap,
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

    int start = _currentPage * widget.rowsPerPage;
    if (start >= list.length) start = 0;
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

    if (widget.isLoading) return _buildLoadingState(theme, colorScheme);
    if (widget.data.isEmpty) return _buildEmptyState(theme, colorScheme);

    return LayoutBuilder(
      builder: (context, constraints) {
        double totalMinWidth = widget.columns.fold(0.0, (sum, col) => sum + col.minWidth);
        if (widget.showCheckboxes) totalMinWidth += 60;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: SizedBox(
                  width: constraints.maxWidth < totalMinWidth ? totalMinWidth : constraints.maxWidth,
                  child: Column(
                    children: [
                      _buildHeader(theme, colorScheme),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: displayData.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: colorScheme.outlineVariant.withOpacity(0.2),
                        ),
                        itemBuilder: (context, index) {
                          final item = displayData[index];
                          final isSelected = _selectedItems.contains(item);
                          return _buildRow(item, isSelected, theme, colorScheme);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _buildPaginationFooter(theme, colorScheme),
          ],
        );
      },
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 17),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5))),
      ),
      child: Row(
        children: [
          if (widget.showCheckboxes) ...[
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

  Widget _buildRow(T item, bool isSelected, ThemeData theme, ColorScheme colorScheme) {
    return InkWell(
      onTap: widget.onRowTap != null ? () => widget.onRowTap!(item) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        color: isSelected ? colorScheme.primary.withOpacity(0.08) : Colors.transparent,
        child: Row(
          children: [
            if (widget.showCheckboxes) ...[
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
            ...widget.columns.map((col) => Expanded(
              flex: col.flex,
              child: col.builder(item),
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

  Widget _buildPaginationFooter(ThemeData theme, ColorScheme colorScheme) {
    final int total = widget.data.length;
    final int start = total == 0 ? 0 : (_currentPage * widget.rowsPerPage) + 1;
    final int end = (start + widget.rowsPerPage - 1) > total ? total : (start + widget.rowsPerPage - 1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.3))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            "Rows per page: ${widget.rowsPerPage}",
            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 32),
          Text(
            "$start–$end of $total",
            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 16),
          IconButton(
            onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
            icon: const Icon(Icons.chevron_left, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 16),
          IconButton(
            onPressed: end < total ? () => setState(() => _currentPage++) : null,
            icon: const Icon(Icons.chevron_right, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(theme, colorScheme),
        ...List.generate(5, (index) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildShimmerRow(colorScheme),
            Divider(
              height: 1, 
              color: colorScheme.outlineVariant.withOpacity(0.2)
            ),
          ],
        )),
      ],
    );
  }

  Widget _buildShimmerRow(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      child: Row(
        children: widget.columns.map((col) => Expanded(
          flex: col.flex,
          child: Container(
            height: 14,
            margin: const EdgeInsets.only(right: 24),
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withOpacity(0.05),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(theme, colorScheme),
          
          Container(
            height: MediaQuery.of(context).size.height * 0.6,
            alignment: Alignment.center,
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
                const SizedBox(height: 8),
                Text(
                  "Try adjusting your filters or check back later.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withOpacity(0.6)
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
