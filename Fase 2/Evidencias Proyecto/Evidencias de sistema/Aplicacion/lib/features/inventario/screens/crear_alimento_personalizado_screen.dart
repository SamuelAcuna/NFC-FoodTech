
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CrearAlimentoPersonalizadoScreen extends StatefulWidget {
  final Map<String, dynamic> hogar;
  final List<Map<String, dynamic>> categorias;
  final String nombreInicial;
  final int? categoriaInicialId;

  const CrearAlimentoPersonalizadoScreen({
    super.key,
    required this.hogar,
    required this.categorias,
    this.nombreInicial = '',
    this.categoriaInicialId,
  });

  @override
  State<CrearAlimentoPersonalizadoScreen> createState() =>
      _CrearAlimentoPersonalizadoScreenState();
}

class _CrearAlimentoPersonalizadoScreenState
    extends State<CrearAlimentoPersonalizadoScreen> {
  static const Color verde = Color(0xFF236B4A);
  static const Color fondo = Color(0xFFF3F7F3);

  bool get _modoOscuro => Theme.of(context).brightness == Brightness.dark;

  Color get _colorFondo =>
      _modoOscuro ? Theme.of(context).scaffoldBackgroundColor : fondo;

  Color get _colorAcento =>
      _modoOscuro ? Theme.of(context).colorScheme.primary : verde;

  Color get _colorTextoSecundario => _modoOscuro
      ? Theme.of(context).colorScheme.onSurfaceVariant
      : Colors.black54;

  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  late final TextEditingController _nombreController;

  int? _categoriaId;
  String _unidadBase = 'g';
  bool _esPerecible = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();

    _nombreController = TextEditingController(
      text: widget.nombreInicial.trim(),
    );

    final idsCategorias = widget.categorias
        .map((categoria) => (categoria['id'] as num).toInt())
        .toSet();

    if (widget.categoriaInicialId != null &&
        idsCategorias.contains(widget.categoriaInicialId)) {
      _categoriaId = widget.categoriaInicialId;
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    super.dispose();
  }

  String? _validarNombre(String? valor) {
    final nombre = (valor ?? '').trim();

    if (nombre.length < 2) {
      return 'Ingresa un nombre de al menos 2 caracteres';
    }

    if (nombre.length > 100) {
      return 'Máximo 100 caracteres';
    }

    return null;
  }

  Future<void> _guardarAlimento() async {
    if (_guardando) return;

    if (!_formKey.currentState!.validate()) return;

    if (_categoriaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona una categoría'),
        ),
      );
      return;
    }

    final hogarId = widget.hogar['id']?.toString();

    if (hogarId == null || hogarId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay un hogar válido'),
        ),
      );
      return;
    }

    final nombre = _nombreController.text
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');

    FocusScope.of(context).unfocus();

    setState(() {
      _guardando = true;
    });

    try {
      // Usa la sesión del usuario actual.
      // Supabase debe validar los permisos mediante RLS.
      final respuesta = await _supabase
          .from('alimento')
          .insert({
            'nombre': nombre,
            'categoria_id': _categoriaId,
            'unidad_base': _unidadBase,
            'es_perecible': _esPerecible,
            'estado': 'LOCAL',
            'hogar_id': hogarId,
            'activo': true,
          })
          .select(
            'id, nombre, categoria_id, unidad_base, '
            'estado, hogar_id',
          )
          .single();

      if (!mounted) return;

      // Entregamos al catálogo el alimento recién creado.
      Navigator.of(context).pop(
        Map<String, dynamic>.from(respuesta),
      );
    } on PostgrestException catch (error) {
      if (!mounted) return;

      String mensaje = error.message;

      if (error.code == '23505') {
        mensaje =
            'Ya existe un alimento con ese nombre '
            'en este catálogo.';
      } else if (error.code == '42501' ||
          error.message.toLowerCase().contains(
                'row-level security',
              )) {
        mensaje =
            'No tienes permiso para crear alimentos '
            'en este hogar. Debemos revisar las '
            'políticas RLS de Supabase.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensaje),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo crear el alimento: $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final nombreHogar =
        widget.hogar['nombre']?.toString() ?? 'Hogar';

    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        title: const Text('Crear alimento'),
        backgroundColor: verde,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Alimento personalizado',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Estará disponible para los miembros '
              'de $nombreHogar, sin necesidad de '
              'aprobación del administrador.',
              style: TextStyle(
                color: _colorTextoSecundario,
              ),
            ),

            const SizedBox(height: 24),

            TextFormField(
              controller: _nombreController,
              textCapitalization:
                  TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Nombre del alimento',
                hintText: 'Ej: Pan amasado casero',
                prefixIcon: Icon(Icons.restaurant),
                border: OutlineInputBorder(),
              ),
              validator: _validarNombre,
            ),

            const SizedBox(height: 12),

            DropdownButtonFormField<int>(
              initialValue: _categoriaId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Categoría',
                prefixIcon: Icon(Icons.category_outlined),
                border: OutlineInputBorder(),
              ),
              items: widget.categorias.map((categoria) {
                final id =
                    (categoria['id'] as num).toInt();

                final nombre =
                    categoria['nombre']?.toString() ?? '';

                return DropdownMenuItem<int>(
                  value: id,
                  child: Text(
                    nombre,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: _guardando
                  ? null
                  : (valor) {
                      setState(() {
                        _categoriaId = valor;
                      });
                    },
              validator: (valor) {
                if (valor == null) {
                  return 'Selecciona una categoría';
                }
                return null;
              },
            ),

            const SizedBox(height: 20),

            const Text(
              '¿Cómo medirás este alimento?',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 8),

            DropdownButtonFormField<String>(
              initialValue: _unidadBase,
              decoration: const InputDecoration(
                labelText: 'Unidad base',
                prefixIcon: Icon(Icons.scale_outlined),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'g',
                  child: Text('Gramos (g)'),
                ),
                DropdownMenuItem(
                  value: 'ml',
                  child: Text('Mililitros (ml)'),
                ),
                DropdownMenuItem(
                  value: 'un',
                  child: Text('Unidades (un)'),
                ),
              ],
              onChanged: _guardando
                  ? null
                  : (valor) {
                      if (valor == null) return;

                      setState(() {
                        _unidadBase = valor;
                      });
                    },
            ),

            const SizedBox(height: 8),

            Text(
              'Al registrarlo en la despensa podrás '
              'usar kg, L o fracciones, según '
              'la unidad base elegida.',
              style: TextStyle(
                fontSize: 12,
                color: _colorTextoSecundario,
              ),
            ),

            const SizedBox(height: 16),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Alimento perecible'),
              subtitle: const Text(
                'Desactívalo si corresponde '
                'a un alimento de larga conservación.',
              ),
              value: _esPerecible,
              activeThumbColor: _colorAcento,
              onChanged: _guardando
                  ? null
                  : (valor) {
                      setState(() {
                        _esPerecible = valor;
                      });
                    },
            ),

            const SizedBox(height: 24),

            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: verde,
                  foregroundColor: Colors.white,
                ),
                onPressed: _guardando
                    ? null
                    : _guardarAlimento,
                icon: _guardando
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_circle_outline),
                label: Text(
                  _guardando
                      ? 'Creando alimento...'
                      : 'Crear y seleccionar alimento',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
