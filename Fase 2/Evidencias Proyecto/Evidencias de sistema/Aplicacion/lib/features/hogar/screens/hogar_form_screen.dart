
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HogarFormScreen extends StatefulWidget {
  final Map<String, dynamic>? hogar;

  const HogarFormScreen({
    super.key,
    this.hogar,
  });

  @override
  State<HogarFormScreen> createState() =>
      _HogarFormScreenState();
}

class _HogarFormScreenState extends State<HogarFormScreen> {
  static const verde = Color(0xFF236B4A);

  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _adultos = TextEditingController();
  final _menores = TextEditingController();

  bool _guardando = false;

  bool get _editando => widget.hogar != null;

  @override
  void initState() {
    super.initState();

    final hogar = widget.hogar;

    if (hogar != null) {
      _nombre.text = hogar['nombre']?.toString() ?? '';
      _adultos.text = hogar['adultos']?.toString() ?? '';
      _menores.text = hogar['menores']?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _adultos.dispose();
    _menores.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando || !_formKey.currentState!.validate()) {
      return;
    }

    if (Supabase.instance.client.auth.currentUser == null) {
      return;
    }

    setState(() => _guardando = true);

    try {
      int? numeroOpcional(String valor) {
        if (valor.trim().isEmpty) return null;
        return int.parse(valor.trim());
      }

      await Supabase.instance.client.rpc(
        'm15_guardar_hogar',
        params: {
          'p_hogar_id': widget.hogar?['id'],
          'p_nombre': _nombre.text.trim(),
          'p_adultos': numeroOpcional(_adultos.text),
          'p_menores': numeroOpcional(_menores.text),
        },
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo guardar el hogar: ${error.message}',
          ),
        ),
      );
    } catch (error) {
      debugPrint('Error al guardar hogar: $error');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar el hogar.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editando ? 'Editar hogar' : 'Crear hogar',
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.home_outlined,
                    color: tema.brightness == Brightness.dark
                        ? tema.colorScheme.primary
                        : verde,
                    size: 56,
                  ),
                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _nombre,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del hogar',
                      hintText: 'Ej. Mi familia',
                      border: OutlineInputBorder(),
                    ),
                    validator: (valor) {
                      final nombre = valor?.trim() ?? '';

                      if (nombre.length < 2) {
                        return 'Ingresa al menos 2 caracteres.';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _adultos,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cantidad de adultos (opcional)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (valor) {
                      if (valor == null || valor.trim().isEmpty) {
                        return null;
                      }

                      final numero = int.tryParse(valor.trim());
                      if (numero == null || numero < 0 || numero > 32767) {
                        return 'Ingresa un número válido.';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _menores,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cantidad de menores (opcional)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (valor) {
                      if (valor == null || valor.trim().isEmpty) {
                        return null;
                      }

                      final numero = int.tryParse(valor.trim());
                      if (numero == null || numero < 0 || numero > 32767) {
                        return 'Ingresa un número válido.';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 24),

                  FilledButton.icon(
                    onPressed: _guardando ? null : _guardar,
                    icon: _guardando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      _guardando
                          ? 'Guardando...'
                          : _editando
                              ? 'Guardar cambios'
                              : 'Crear hogar',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: verde,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
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
