import 'package:flutter/material.dart';

class TableColumn<T> {
  final String title;
  final Widget Function(T) builder;
  final bool sortable;
  final String sortKey;

  TableColumn({
    required this.title, 
    required this.builder, 
    this.sortable = false, 
    this.sortKey = ""
  });
}

class CommonTable<T> extends StatelessWidget {
  final List<T> data;
  final List<TableColumn<T>> columns;
  final int? sortColumnIndex;
  final bool sortAscending;
  final Function(int, bool)? onSort;

  const CommonTable({
    super.key,
    required this.data,
    required this.columns,
    this.sortColumnIndex,
    this.sortAscending = true,
    this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              sortColumnIndex: sortColumnIndex,
              sortAscending: sortAscending,
              headingRowColor: WidgetStateProperty.all(colorScheme.surfaceContainerHighest.withOpacity(0.4)),
              dataRowMinHeight: 56,
              dataRowMaxHeight: 64,
              showCheckboxColumn: false,
              columns: columns.map((col) {
                return DataColumn(
                  label: Text(col.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  onSort: col.sortable ? (idx, asc) => onSort?.call(idx, asc) : null,
                );
              }).toList(),
              rows: List<DataRow>.generate(data.length, (index) {
                final item = data[index];
                return DataRow(
                  color: WidgetStateProperty.resolveWith((states) => index % 2 != 0 ? colorScheme.primary.withOpacity(0.02) : null),
                  cells: columns.map((col) => DataCell(col.builder(item))).toList(),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}