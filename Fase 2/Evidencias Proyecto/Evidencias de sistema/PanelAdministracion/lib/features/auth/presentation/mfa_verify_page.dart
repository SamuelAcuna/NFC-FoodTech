import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_layout.dart';
import 'auth_providers.dart';

class TotpCodeForm extends ConsumerStatefulWidget {
  const TotpCodeForm({required this.factorId, super.key});
  final String factorId;
  @override
  ConsumerState<TotpCodeForm> createState() => _TotpCodeFormState();
}

class _TotpCodeFormState extends ConsumerState<TotpCodeForm> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      ref.read(authControllerProvider).verify(widget.factorId, _code.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _code,
            enabled: !auth.busy,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: const InputDecoration(
              labelText: 'Código de verificación',
              hintText: '6 dígitos',
            ),
            validator: (value) => RegExp(r'^\d{6}$').hasMatch(value ?? '')
                ? null
                : 'Ingresa un código de 6 dígitos.',
            onFieldSubmitted: (_) {
              if (!auth.busy) _submit();
            },
          ),
          const SizedBox(height: 24),
          AuthSubmitButton(
            busy: auth.busy,
            label: 'Verificar y entrar',
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

class MfaVerifyPage extends ConsumerWidget {
  const MfaVerifyPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return AuthLayout(
      title: 'Verificación en dos pasos',
      description: 'Ingresa el código de tu aplicación de autenticación.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthMessage(auth.message),
          if (auth.factores.isNotEmpty)
            TotpCodeForm(factorId: auth.factores.first),
          TextButton(
            onPressed: auth.busy ? null : auth.logout,
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}
