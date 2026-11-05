import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../services/hardware/display_service.dart';

class CustomerPresentationPage extends StatefulWidget {
  const CustomerPresentationPage({super.key});

  @override
  State<CustomerPresentationPage> createState() => _CustomerPresentationPageState();
}

class _CustomerPresentationPageState extends State<CustomerPresentationPage> {
  InAppWebViewController? _webViewController;
  late final VoidCallback _listener;

  @override
  void initState() {
    super.initState();
    _listener = () {
      if (mounted && _webViewController != null) {
        _webViewController!.loadData(
          data: DisplayService.instance.currentHtml,
          mimeType: 'text/html',
          encoding: 'utf-8',
        );
      }
    };
    DisplayService.instance.addListener(_listener);
  }

  @override
  void dispose() {
    DisplayService.instance.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: InAppWebView(
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: false, // No JS needed for displaying static Odoo HTML display
          supportZoom: false,
          domStorageEnabled: false,
        ),
        onWebViewCreated: (controller) {
          _webViewController = controller;
          controller.loadData(
            data: DisplayService.instance.currentHtml,
            mimeType: 'text/html',
            encoding: 'utf-8',
          );
        },
      ),
    );
  }
}
