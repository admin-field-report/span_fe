import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import '../../../widgets/widgets.dart';

class GeneratedReportView extends StatelessWidget {
  final String htmlContent;

  const GeneratedReportView({super.key, required this.htmlContent});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainer,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        centerTitle: true,
        title: const Text("Final Report", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        automaticallyImplyLeading: false, 
        actions: [],
      ),
      body: Column(
        children: [
          // 🚀 RENDER THE HTML HERE
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white, // Reports usually look best on pure white
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))
                  ],
                ),
                clipBehavior: Clip.hardEdge,
                // Using flutter_html to render the backend string
                child: Html(
                  data: htmlContent,
                  style: {
                    // Provide a default base style in case the HTML lacks it
                    "body": Style(
                      margin: Margins.zero,
                      padding: HtmlPaddings.all(16),
                      fontFamily: 'sans-serif',
                    ),
                    "img": Style(
                      width: Width(100, Unit.percent),
                      height: Height.auto(),
                    ),
                  },
                ),
              ),
            ),
          ),
          
          // BOTTOM STICKY ACTION BAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Button(
                      label: "Close & Finish",
                      variant: ButtonVariant.filled,
                      onPressed: () {
                        // Pop this modal
                        Navigator.pop(context);
                        // Pop the Preview Screen to go back to the tables
                        Navigator.pop(context, true); 
                      },
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}