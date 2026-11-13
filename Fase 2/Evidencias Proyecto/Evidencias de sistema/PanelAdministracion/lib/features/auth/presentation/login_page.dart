import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_layout.dart';
import 'auth_providers.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      ref
          .read(authControllerProvider)
          .login(_email.text.trim(), _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return AuthLayout(
      title: 'Iniciar sesión',
      description: 'Acceso exclusivo para administradores de la plataforma',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthMessage(auth.message),
            TextFormField(
              controller: _email,
              enabled: !auth.busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.username],
              decoration: const InputDecoration(
                labelText: 'Correo administrativo',
              ),
              validator: (value) =>
                  RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                      .hasMatch(value?.trim() ?? '')
                  ? null
                  : 'Ingresa un correo válido.',
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              enabled: !auth.busy,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Contraseña'),
              validator: (value) => value == null || value.isEmpty
                  ? 'Ingresa tu contraseña.'
                  : null,
              onFieldSubmitted: (_) {
                if (!auth.busy) _submit();
              },
            ),
            const SizedBox(height: 28),
            AuthSubmitButton(
              busy: auth.busy,
              label: 'Acceder al panel',
              onPressed: _submit,
            ),
            if (auth.hasSession && auth.contexto == null && !auth.busy)
              TextButton(
                onPressed: auth.refresh,
                child: const Text('Reintentar validación de sesión'),
              ),
          ],
        ),
      ),
    );
  }
}
