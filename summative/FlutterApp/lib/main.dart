import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String kPredictEndpoint = "";

void main() {
  runApp(const PredictorApp());
}

class PredictorApp extends StatelessWidget {
  const PredictorApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1E5F4E); // deep government-teal, distinct from generic Material blue
    return MaterialApp(
      title: 'Business Registration Predictor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF6F7F5),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: seed, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
      home: const PredictionPage(),
    );
  }
}

class PredictorField {
  final String key; // JSON key sent to the API
  final String label;
  final String hint;
  final double min;
  final double max;
  final TextEditingController controller = TextEditingController();

  PredictorField({
    required this.key,
    required this.label,
    required this.hint,
    required this.min,
    required this.max,
  });

  String? validate() {
    final raw = controller.text.trim();
    if (raw.isEmpty) return 'Required';
    final value = double.tryParse(raw);
    if (value == null) return 'Enter a valid number';
    if (value < min || value > max) {
      return 'Must be between ${min.toStringAsFixed(0)} and ${max.toStringAsFixed(0)}';
    }
    return null;
  }
}

class PredictionPage extends StatefulWidget {
  const PredictionPage({super.key});

  @override
  State<PredictionPage> createState() => _PredictionPageState();
}

class _PredictionPageState extends State<PredictionPage> {
  final _formKey = GlobalKey<FormState>();

  // One field per feature the regression model was trained on.
  late final List<PredictorField> _fields = [
    PredictorField(
      key: 'procedures',
      label: 'Number of Procedures',
      hint: 'e.g. 6',
      min: 1,
      max: 20,
    ),
    PredictorField(
      key: 'cost_pct_income',
      label: 'Cost (% of income per capita)',
      hint: 'e.g. 12.5',
      min: 0,
      max: 500,
    ),
    PredictorField(
      key: 'gdp_per_capita',
      label: 'GDP per Capita (USD)',
      hint: 'e.g. 850',
      min: 50,
      max: 150000,
    ),
    PredictorField(
      key: 'paid_in_capital_pct',
      label: 'Paid-in Minimum Capital (% of income per capita)',
      hint: 'e.g. 0',
      min: 0,
      max: 500,
    ),
  ];

  bool _loading = false;
  String? _errorMessage;
  double? _predictedDays;

  @override
  void dispose() {
    for (final f in _fields) {
      f.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _predict() async {
    setState(() {
      _errorMessage = null;
      _predictedDays = null;
    });

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    setState(() => _loading = true);

    final payload = <String, dynamic>{
      for (final f in _fields) f.key: double.parse(f.controller.text.trim()),
    };

    try {
      final response = await http
          .post(
            Uri.parse(kPredictEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final value = decoded is Map
            ? (decoded['predicted_days'] ?? decoded['prediction'])
            : null;
        if (value == null) {
          setState(() => _errorMessage = 'Server response did not include a prediction.');
        } else {
          setState(() => _predictedDays = (value as num).toDouble());
        }
      } else if (response.statusCode == 422) {
        setState(() => _errorMessage =
            'One or more values were rejected by the API (out of range or wrong type).');
      } else {
        setState(() =>
            _errorMessage = 'Request failed (status ${response.statusCode}). Please try again.');
      }
    } catch (e) {
      setState(() => _errorMessage =
          'Could not reach the prediction service. Check your connection and try again.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Business Registration Time Predictor'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Estimate how many days it will take to complete business '
                  'registration, based on government service indicators.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
                ),
                const SizedBox(height: 20),

                // Input fields
                ..._fields.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TextFormField(
                        controller: f.controller,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: f.label,
                          hintText: f.hint,
                        ),
                        validator: (_) => f.validate(),
                      ),
                    )),

                const SizedBox(height: 8),

                // Predict button
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _predict,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                          )
                        : const Text('Predict', style: TextStyle(fontSize: 16)),
                  ),
                ),

                const SizedBox(height: 24),

                // Result / error display area
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _buildResultArea(theme),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultArea(ThemeData theme) {
    if (_errorMessage != null) {
      return Container(
        key: const ValueKey('error'),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFDECEC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFF5C2C2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_errorMessage!, style: const TextStyle(color: Color(0xFF8A2C2C))),
            ),
          ],
        ),
      );
    }

    if (_predictedDays != null) {
      return Container(
        key: const ValueKey('result'),
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFE9F3EF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFBFDDD1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Estimated time to start a business',
                style: TextStyle(color: Colors.black54, fontSize: 13)),
            const SizedBox(height: 6),
            Text(
              '${_predictedDays!.toStringAsFixed(1)} days',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E5F4E),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox(key: ValueKey('empty'), height: 0);
  }
}