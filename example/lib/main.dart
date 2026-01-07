import 'package:flutter/material.dart';
import 'package:quick_html_pdf/quick_html_pdf.dart';

void main() {
  runApp(const QuickHtmlPdfExample());
}

class QuickHtmlPdfExample extends StatelessWidget {
  const QuickHtmlPdfExample({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuickHtmlPdf Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isLoading = false;
  String _status = '';
  int _rowCount = 100;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QuickHtmlPdf Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'PDF Generation Demo',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Generate PDFs from HTML templates with dynamic data.',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),

            // Row count slider
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Table Rows: $_rowCount',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Slider(
                      value: _rowCount.toDouble(),
                      min: 10,
                      max: 2000,
                      divisions: 199,
                      label: '$_rowCount rows',
                      onChanged: (value) {
                        setState(() {
                          _rowCount = value.toInt();
                        });
                      },
                    ),
                    Text(
                      'Estimated pages: ${(_rowCount / 25).ceil()}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Simple Invoice Demo
            _buildDemoSection(
              context,
              title: 'Simple Invoice',
              description: 'Single-page invoice with header and line items.',
              onDownload: () => _generateSimpleInvoice(PdfOutput.download),
              onGetBytes: () => _generateSimpleInvoice(PdfOutput.bytes),
            ),
            const SizedBox(height: 16),

            // Large Report Demo
            _buildDemoSection(
              context,
              title: 'Large Report',
              description:
                  'Multi-page report with $_rowCount rows and header/footer.',
              onDownload: () => _generateLargeReport(PdfOutput.download),
              onGetBytes: () => _generateLargeReport(PdfOutput.bytes),
            ),
            const SizedBox(height: 24),

            // Status
            if (_status.isNotEmpty)
              Card(
                color: _status.startsWith('Error')
                    ? Colors.red[50]
                    : Colors.green[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        _status.startsWith('Error')
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                        color: _status.startsWith('Error')
                            ? Colors.red
                            : Colors.green,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _status,
                          style: TextStyle(
                            color: _status.startsWith('Error')
                                ? Colors.red[900]
                                : Colors.green[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Loading overlay
            if (_isLoading)
              Container(
                margin: const EdgeInsets.only(top: 24),
                child: const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Generating PDF...'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDemoSection(
    BuildContext context, {
    required String title,
    required String description,
    required VoidCallback onDownload,
    required VoidCallback onGetBytes,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              description,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : onDownload,
                  icon: const Icon(Icons.download),
                  label: const Text('Download (Fast)'),
                ),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : onGetBytes,
                  icon: const Icon(Icons.memory),
                  label: const Text('Get Bytes'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateSimpleInvoice(PdfOutput output) async {
    setState(() {
      _isLoading = true;
      _status = '';
    });

    try {
      final stopwatch = Stopwatch()..start();

      final template = _getInvoiceTemplate();
      final data = _getInvoiceData();

      final bytes = await QuickHtmlPdf.generate(
        htmlTemplate: template,
        data: data,
        options: PdfOptions(
          output: output,
          filename: 'invoice.pdf',
          pageFormat: PdfPageFormat.a4,
          orientation: PdfOrientation.portrait,
          margins: const PdfMargins(
            topMm: 20,
            rightMm: 20,
            bottomMm: 20,
            leftMm: 20,
          ),
          debug: true,
        ),
      );

      stopwatch.stop();

      if (output == PdfOutput.bytes && bytes != null) {
        // Trigger download from bytes
        QuickHtmlPdf.downloadBytes(bytes: bytes, filename: 'invoice.pdf');

        setState(() {
          _status =
              'Generated ${(bytes.length / 1024).toStringAsFixed(1)} KB in ${stopwatch.elapsedMilliseconds}ms';
        });
      } else {
        setState(() {
          _status = 'Print dialog opened in ${stopwatch.elapsedMilliseconds}ms';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _generateLargeReport(PdfOutput output) async {
    setState(() {
      _isLoading = true;
      _status = '';
    });

    try {
      final stopwatch = Stopwatch()..start();

      final template = _getLargeReportTemplate();
      final data = _getLargeReportData(_rowCount);

      final bytes = await QuickHtmlPdf.generate(
        htmlTemplate: template,
        data: data,
        options: PdfOptions(
          output: output,
          filename: 'report.pdf',
          pageFormat: PdfPageFormat.a4,
          orientation: PdfOrientation.portrait,
          headerHtml: '''
            <div style="display: flex; justify-content: space-between; align-items: center;">
              <strong>Sales Report 2024</strong>
              <span style="color: #666;">Confidential</span>
            </div>
          ''',
          footerHtml: '''
            <div style="display: flex; justify-content: space-between; align-items: center;">
              <span>Generated by QuickHtmlPdf</span>
              <span>© 2024 Acme Corp</span>
            </div>
          ''',
          margins: const PdfMargins(
            topMm: 25,
            rightMm: 15,
            bottomMm: 25,
            leftMm: 15,
          ),
          debug: true,
        ),
      );

      stopwatch.stop();

      if (output == PdfOutput.bytes && bytes != null) {
        QuickHtmlPdf.downloadBytes(bytes: bytes, filename: 'report.pdf');

        setState(() {
          _status =
              'Generated ${(bytes.length / 1024).toStringAsFixed(1)} KB ($_rowCount rows) in ${stopwatch.elapsedMilliseconds}ms';
        });
      } else {
        setState(() {
          _status =
              'Print dialog opened ($_rowCount rows) in ${stopwatch.elapsedMilliseconds}ms';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // ==================== TEMPLATES ====================

  String _getInvoiceTemplate() {
    return '''
<div style="font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto;">
  <!-- Header -->
  <div style="display: flex; justify-content: space-between; margin-bottom: 40px;">
    <div>
      <h1 style="margin: 0; color: #333;">INVOICE</h1>
      <p style="color: #666; margin: 5px 0;">{{company.name}}</p>
      <p style="color: #666; margin: 0; font-size: 12px;">{{company.address}}</p>
    </div>
    <div style="text-align: right;">
      <p style="margin: 0;"><strong>Invoice #:</strong> {{invoiceNumber}}</p>
      <p style="margin: 5px 0;"><strong>Date:</strong> {{date}}</p>
      <p style="margin: 0;"><strong>Due:</strong> {{dueDate}}</p>
    </div>
  </div>

  <!-- Bill To -->
  <div style="margin-bottom: 30px;">
    <h3 style="color: #666; margin-bottom: 10px;">Bill To:</h3>
    <p style="margin: 0;"><strong>{{customer.name}}</strong></p>
    <p style="margin: 5px 0; color: #666;">{{customer.email}}</p>
    <p style="margin: 0; color: #666;">{{customer.address}}</p>
  </div>

  <!-- Items Table -->
  <table style="width: 100%; border-collapse: collapse; margin-bottom: 30px;">
    <thead>
      <tr style="background-color: #f8f9fa;">
        <th style="padding: 12px; text-align: left; border-bottom: 2px solid #dee2e6;">Item</th>
        <th style="padding: 12px; text-align: left; border-bottom: 2px solid #dee2e6;">Description</th>
        <th style="padding: 12px; text-align: right; border-bottom: 2px solid #dee2e6;">Qty</th>
        <th style="padding: 12px; text-align: right; border-bottom: 2px solid #dee2e6;">Price</th>
        <th style="padding: 12px; text-align: right; border-bottom: 2px solid #dee2e6;">Total</th>
      </tr>
    </thead>
    <tbody>
      {{#each items}}
      <tr>
        <td style="padding: 12px; border-bottom: 1px solid #dee2e6;">{{this.name}}</td>
        <td style="padding: 12px; border-bottom: 1px solid #dee2e6; color: #666;">{{this.description}}</td>
        <td style="padding: 12px; text-align: right; border-bottom: 1px solid #dee2e6;">{{this.quantity}}</td>
        <td style="padding: 12px; text-align: right; border-bottom: 1px solid #dee2e6;">{{this.price}}</td>
        <td style="padding: 12px; text-align: right; border-bottom: 1px solid #dee2e6;"><strong>{{this.total}}</strong></td>
      </tr>
      {{/each}}
    </tbody>
  </table>

  <!-- Totals -->
  <div style="display: flex; justify-content: flex-end;">
    <div style="width: 250px;">
      <div style="display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #eee;">
        <span>Subtotal:</span>
        <span>{{subtotal}}</span>
      </div>
      <div style="display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #eee;">
        <span>Tax (10%):</span>
        <span>{{tax}}</span>
      </div>
      <div style="display: flex; justify-content: space-between; padding: 12px 0; font-size: 18px;">
        <strong>Total:</strong>
        <strong style="color: #2563eb;">{{total}}</strong>
      </div>
    </div>
  </div>

  <!-- Footer -->
  <div style="margin-top: 50px; padding-top: 20px; border-top: 1px solid #eee; text-align: center; color: #999; font-size: 12px;">
    <p>Thank you for your business!</p>
    <p>Payment is due within 30 days. Please make checks payable to {{company.name}}.</p>
  </div>
</div>
''';
  }

  Map<String, dynamic> _getInvoiceData() {
    return {
      'company': {
        'name': 'Acme Corporation',
        'address': '123 Business Ave, Suite 100, New York, NY 10001',
      },
      'customer': {
        'name': 'John Smith',
        'email': 'john@example.com',
        'address': '456 Customer St, Los Angeles, CA 90001',
      },
      'invoiceNumber': 'INV-2024-001',
      'date': 'January 8, 2024',
      'dueDate': 'February 7, 2024',
      'items': [
        {
          'name': 'Web Design',
          'description': 'Custom website design and development',
          'quantity': 1,
          'price': '\$2,500.00',
          'total': '\$2,500.00',
        },
        {
          'name': 'Hosting',
          'description': 'Annual web hosting package',
          'quantity': 1,
          'price': '\$199.00',
          'total': '\$199.00',
        },
        {
          'name': 'Support',
          'description': 'Monthly support (3 months)',
          'quantity': 3,
          'price': '\$100.00',
          'total': '\$300.00',
        },
      ],
      'subtotal': '\$2,999.00',
      'tax': '\$299.90',
      'total': '\$3,298.90',
    };
  }

  String _getLargeReportTemplate() {
    return '''
<div style="font-family: Arial, sans-serif;">
  <!-- Title -->
  <div style="text-align: center; margin-bottom: 30px;">
    <h1 style="margin: 0; color: #1e40af;">{{title}}</h1>
    <p style="color: #666; margin: 10px 0;">Generated on {{generatedDate}}</p>
    <p style="color: #666; margin: 0;">Total Records: {{totalRows}}</p>
  </div>

  <!-- Summary Cards -->
  <div style="display: flex; gap: 20px; margin-bottom: 30px;">
    <div style="flex: 1; padding: 20px; background: #f0f9ff; border-radius: 8px; text-align: center;">
      <div style="font-size: 24px; font-weight: bold; color: #1e40af;">{{summary.totalSales}}</div>
      <div style="color: #666; font-size: 14px;">Total Sales</div>
    </div>
    <div style="flex: 1; padding: 20px; background: #f0fdf4; border-radius: 8px; text-align: center;">
      <div style="font-size: 24px; font-weight: bold; color: #166534;">{{summary.totalOrders}}</div>
      <div style="color: #666; font-size: 14px;">Total Orders</div>
    </div>
    <div style="flex: 1; padding: 20px; background: #fef3c7; border-radius: 8px; text-align: center;">
      <div style="font-size: 24px; font-weight: bold; color: #92400e;">{{summary.avgOrder}}</div>
      <div style="color: #666; font-size: 14px;">Avg. Order</div>
    </div>
  </div>

  <!-- Data Table -->
  <table style="width: 100%; border-collapse: collapse; font-size: 11px;">
    <thead>
      <tr style="background-color: #1e40af; color: white;">
        <th style="padding: 10px 8px; text-align: left;">#</th>
        <th style="padding: 10px 8px; text-align: left;">Date</th>
        <th style="padding: 10px 8px; text-align: left;">Order ID</th>
        <th style="padding: 10px 8px; text-align: left;">Customer</th>
        <th style="padding: 10px 8px; text-align: left;">Product</th>
        <th style="padding: 10px 8px; text-align: right;">Qty</th>
        <th style="padding: 10px 8px; text-align: right;">Price</th>
        <th style="padding: 10px 8px; text-align: right;">Total</th>
        <th style="padding: 10px 8px; text-align: center;">Status</th>
      </tr>
    </thead>
    <tbody>
      {{#each rows}}
      <tr style="{{this.rowStyle}}">
        <td style="padding: 8px; border-bottom: 1px solid #e5e7eb;">{{this.index}}</td>
        <td style="padding: 8px; border-bottom: 1px solid #e5e7eb;">{{this.date}}</td>
        <td style="padding: 8px; border-bottom: 1px solid #e5e7eb; font-family: monospace;">{{this.orderId}}</td>
        <td style="padding: 8px; border-bottom: 1px solid #e5e7eb;">{{this.customer}}</td>
        <td style="padding: 8px; border-bottom: 1px solid #e5e7eb;">{{this.product}}</td>
        <td style="padding: 8px; border-bottom: 1px solid #e5e7eb; text-align: right;">{{this.quantity}}</td>
        <td style="padding: 8px; border-bottom: 1px solid #e5e7eb; text-align: right;">{{this.price}}</td>
        <td style="padding: 8px; border-bottom: 1px solid #e5e7eb; text-align: right; font-weight: bold;">{{this.total}}</td>
        <td style="padding: 8px; border-bottom: 1px solid #e5e7eb; text-align: center;">
          <span style="{{this.statusStyle}}">{{this.status}}</span>
        </td>
      </tr>
      {{/each}}
    </tbody>
  </table>

  <!-- Footer Summary -->
  <div style="margin-top: 30px; padding: 20px; background: #f8fafc; border-radius: 8px;">
    <h3 style="margin: 0 0 10px 0;">Report Summary</h3>
    <p style="margin: 5px 0; color: #666;">This report contains {{totalRows}} sales records.</p>
    <p style="margin: 5px 0; color: #666;">Data period: January 1, 2024 - December 31, 2024</p>
  </div>
</div>
''';
  }

  Map<String, dynamic> _getLargeReportData(int rowCount) {
    final customers = [
      'Alice Johnson',
      'Bob Smith',
      'Carol Williams',
      'David Brown',
      'Eva Martinez',
      'Frank Lee',
      'Grace Chen',
      'Henry Wilson',
    ];

    final products = [
      'Widget Pro',
      'Gadget Plus',
      'Tool Kit',
      'Service Plan',
      'Premium Bundle',
      'Basic Package',
      'Enterprise Suite',
      'Starter Kit',
    ];

    final statuses = ['Completed', 'Pending', 'Shipped', 'Processing'];
    final statusStyles = {
      'Completed':
          'background: #dcfce7; color: #166534; padding: 2px 8px; border-radius: 4px; font-size: 10px;',
      'Pending':
          'background: #fef3c7; color: #92400e; padding: 2px 8px; border-radius: 4px; font-size: 10px;',
      'Shipped':
          'background: #dbeafe; color: #1e40af; padding: 2px 8px; border-radius: 4px; font-size: 10px;',
      'Processing':
          'background: #f3e8ff; color: #7c3aed; padding: 2px 8px; border-radius: 4px; font-size: 10px;',
    };

    final rows = <Map<String, dynamic>>[];
    double totalSales = 0;

    for (var i = 0; i < rowCount; i++) {
      final quantity = (i % 10) + 1;
      final price = ((i % 50) + 10) * 9.99;
      final total = quantity * price;
      final status = statuses[i % statuses.length];

      totalSales += total;

      rows.add({
        'index': i + 1,
        'date':
            '2024-${((i % 12) + 1).toString().padLeft(2, '0')}-${((i % 28) + 1).toString().padLeft(2, '0')}',
        'orderId': 'ORD-${(10000 + i).toString()}',
        'customer': customers[i % customers.length],
        'product': products[i % products.length],
        'quantity': quantity,
        'price': '\$${price.toStringAsFixed(2)}',
        'total': '\$${total.toStringAsFixed(2)}',
        'status': status,
        'statusStyle': statusStyles[status],
        'rowStyle': i.isOdd ? 'background-color: #f9fafb;' : '',
      });
    }

    return {
      'title': 'Annual Sales Report 2024',
      'generatedDate': 'January 8, 2024',
      'totalRows': rowCount,
      'summary': {
        'totalSales': '\$${totalSales.toStringAsFixed(2)}',
        'totalOrders': rowCount,
        'avgOrder': '\$${(totalSales / rowCount).toStringAsFixed(2)}',
      },
      'rows': rows,
    };
  }
}
