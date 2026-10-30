import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../state/session.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    if (SessionScope.read(context).consumeExpiredNotice()) {
      _notice = 'Your session expired after 24 hours. Enter the password to continue.';
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _password.text;
    if (password.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SessionScope.read(context).login(password);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(26),
                      child: Image.asset('assets/icon/app_icon.png', width: 88, height: 88),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Ayoma'),
                        TextSpan(text: 'Max', style: uStyle(28, weight: FontWeight.w800, color: AppColors.green)),
                        const TextSpan(text: ' Admin'),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: uStyle(28, weight: FontWeight.w800, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 28),
                  if (_notice != null) ...[
                    _Banner(icon: LucideIcons.clock3, text: _notice!, color: AppColors.amber),
                    const SizedBox(height: 14),
                  ],
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    autofocus: true,
                    enabled: !_busy,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _submit(),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(LucideIcons.lockKeyhole, size: 18),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show' : 'Hide',
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eyeOff, size: 18),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _Banner(icon: LucideIcons.circleAlert, text: _error!, color: AppColors.error),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _password.text.isEmpty || _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.ink),
                          )
                        : const Text('Log in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.ink),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: uStyle(13, color: AppColors.ink, height: 1.35))),
        ],
      ),
    );
  }
}
