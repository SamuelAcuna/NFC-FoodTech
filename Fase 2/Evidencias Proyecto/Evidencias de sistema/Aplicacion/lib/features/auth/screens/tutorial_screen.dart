
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TutorialScreen extends StatefulWidget {
  final VoidCallback onFinalizado;

  const TutorialScreen({
    super.key,
    required this.onFinalizado,
  });

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  static const Color verde = Color(0xFF236B4A);

  final PageController _pageController = PageController();

  int _paginaActual = 0;
  bool _guardando = false;

  // --------------------------------------------------
  // COLORES ADAPTADOS AL TEMA
  // --------------------------------------------------

  bool get _modoOscuro =>
      Theme.of(context).brightness == Brightness.dark;

  Color get _colorPrincipal {
    final esquema = Theme.of(context).colorScheme;
    return _modoOscuro ? esquema.onSurface : verde;
  }

  Color get _colorAcento {
    final esquema = Theme.of(context).colorScheme;
    return _modoOscuro ? esquema.primary : verde;
  }

  Color get _colorSecundario =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  // --------------------------------------------------
  // PASOS DEL TUTORIAL
  // Se conserva el contenido original.
  // --------------------------------------------------

  static const List<_PasoTutorial> _pasos = [
    _PasoTutorial(
      icono: Icons.eco_rounded,
      titulo: '¡Bienvenido a NFC-FoodTech!',
      descripcion:
          'Organiza los alimentos de tu hogar y descubre '
          'cómo aprovecharlos mejor para reducir '
          'el desperdicio alimentario.',
    ),
    _PasoTutorial(
      icono: Icons.home_outlined,
      titulo: 'Organiza tu hogar',
      descripcion:
          'Crea un hogar e invita a otros integrantes '
          'para administrar juntos los alimentos, '
          'las compras y el inventario.',
    ),
    _PasoTutorial(
      icono: Icons.inventory_2_outlined,
      titulo: 'Controla tus alimentos',
      descripcion:
          'Registra los alimentos manualmente, indica '
          'sus cantidades y dónde los guardas. '
          'También podrás revisar sus fechas '
          'estimadas de caducidad.',
    ),
    _PasoTutorial(
      icono: Icons.restaurant_outlined,
      titulo: 'Registra lo que utilizas',
      descripcion:
          'Actualiza las cantidades cuando consumas '
          'alimentos y registra lo que desperdicies. '
          'Así podrás mantener tu inventario '
          'actualizado.',
    ),
    _PasoTutorial(
      icono: Icons.bar_chart_rounded,
      titulo: 'Conoce tus hábitos',
      descripcion:
          'Consulta estadísticas sobre consumo, '
          'desperdicio y pérdidas económicas '
          'estimadas para tomar mejores decisiones.',
    ),
  ];

  // --------------------------------------------------
  // CICLO DE VIDA
  // --------------------------------------------------

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // --------------------------------------------------
  // MENSAJES DE ERROR
  // --------------------------------------------------

  void _mostrarError(String mensaje) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            mensaje,
            style: _modoOscuro ? const TextStyle(color: Colors.white) : null,
          ),
          backgroundColor: const Color(0xFFB83D3D),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // --------------------------------------------------
  // NAVEGACIÓN
  // --------------------------------------------------

  void _siguientePagina() {
    if (_guardando) return;

    if (_paginaActual == _pasos.length - 1) {
      _finalizarTutorial();
      return;
    }

    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _paginaAnterior() {
    if (_guardando || _paginaActual == 0) return;

    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // --------------------------------------------------
  // FINALIZAR TUTORIAL
  //
  // Se mantiene el registro existente en
  // los metadatos de autenticación del usuario.
  // No requiere cambiar tablas ni políticas.
  // --------------------------------------------------

  Future<void> _finalizarTutorial() async {
    if (_guardando) return;

    setState(() {
      _guardando = true;
    });

    try {
      final auth = Supabase.instance.client.auth;
      final usuario = auth.currentUser;

      if (usuario == null) {
        _mostrarError(
          'Tu sesión no está disponible. '
          'Inicia sesión nuevamente.',
        );
        return;
      }

      final respuesta = await auth.updateUser(
        UserAttributes(
          data: {
            'tutorial_completado': true,
          },
        ),
      );

      if (respuesta.user == null) {
        throw Exception(
          'No se pudo confirmar el guardado.',
        );
      }

      if (!mounted) return;

      widget.onFinalizado();
    } on AuthException catch (error) {
      _mostrarError(error.message);
    } catch (error) {
      debugPrint(
        'Error al finalizar tutorial: $error',
      );

      _mostrarError(
        'No se pudo guardar el progreso del tutorial. '
        'Comprueba tu conexión e inténtalo nuevamente.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }

  // --------------------------------------------------
  // TARJETA DE CADA PASO
  // --------------------------------------------------

  Widget _construirPaso(_PasoTutorial paso) {
    final esquema = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        child: Container(
          width: double.infinity,

          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 36,
          ),

          decoration: BoxDecoration(
            color: esquema.surface,

            borderRadius: BorderRadius.circular(26),

            border: Border.all(
              color: esquema.outlineVariant,
            ),
          ),

          child: Column(
            mainAxisSize: MainAxisSize.min,

            children: [
              // Ícono del paso
              Container(
                width: 110,
                height: 110,

                decoration: BoxDecoration(
                  color: _modoOscuro
                      ? esquema.surfaceContainerHighest
                      : const Color(0xFFE1F1E6),

                  borderRadius:
                      BorderRadius.circular(32),
                ),

                child: Icon(
                  paso.icono,
                  size: 56,
                  color: _colorAcento,
                ),
              ),

              const SizedBox(height: 30),

              // Título
              Text(
                paso.titulo,
                textAlign: TextAlign.center,

                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                  color: _colorPrincipal,
                ),
              ),

              const SizedBox(height: 18),

              // Descripción
              Text(
                paso.descripcion,
                textAlign: TextAlign.center,

                style: TextStyle(
                  fontSize: 16,
                  height: 1.6,
                  color: _colorSecundario,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------
  // INDICADORES DE PÁGINA
  // --------------------------------------------------

  Widget _construirIndicadores() {
    final esquema = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,

      children: List.generate(
        _pasos.length,
        (index) {
          final seleccionada =
              index == _paginaActual;

          return AnimatedContainer(
            duration:
                const Duration(milliseconds: 250),

            margin: const EdgeInsets.symmetric(
              horizontal: 4,
            ),

            height: 9,
            width: seleccionada ? 26 : 9,

            decoration: BoxDecoration(
              color: seleccionada
                  ? _colorAcento
                  : esquema.outlineVariant,

              borderRadius:
                  BorderRadius.circular(20),
            ),
          );
        },
      ),
    );
  }

  // --------------------------------------------------
  // PANTALLA
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final esquema = tema.colorScheme;

    final ultimaPagina =
        _paginaActual == _pasos.length - 1;

    return Scaffold(
      backgroundColor:
          tema.scaffoldBackgroundColor,

      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 520,
            ),

            child: Padding(
              padding: const EdgeInsets.all(22),

              child: Column(
                children: [
                  // -----------------------
                  // ENCABEZADO
                  // -----------------------

                  Row(
                    children: [
                      Container(
                        width: 45,
                        height: 45,

                        decoration: BoxDecoration(
                          color: verde,

                          borderRadius:
                              BorderRadius.circular(14),
                        ),

                        child: const Icon(
                          Icons.eco_rounded,
                          color: Colors.white,
                          size: 27,
                        ),
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: Text(
                          'NFC-FoodTech',

                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                            color: _colorPrincipal,
                          ),
                        ),
                      ),

                      TextButton(
                        onPressed: _guardando
                            ? null
                            : _finalizarTutorial,

                        child: Text(
                          'Omitir',

                          style: TextStyle(
                            color: _colorAcento,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // -----------------------
                  // CONTADOR DE PASOS
                  // -----------------------

                  Align(
                    alignment: Alignment.centerLeft,

                    child: Text(
                      'Paso ${_paginaActual + 1} '
                      'de ${_pasos.length}',

                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _colorSecundario,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // -----------------------
                  // BARRA DE PROGRESO
                  // -----------------------

                  LinearProgressIndicator(
                    value:
                        (_paginaActual + 1) / _pasos.length,

                    minHeight: 6,

                    backgroundColor:
                        esquema.outlineVariant,

                    color: _colorAcento,

                    borderRadius:
                        BorderRadius.circular(8),
                  ),

                  const SizedBox(height: 16),

                  // -----------------------
                  // CONTENIDO DEL TUTORIAL
                  // -----------------------

                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,

                      physics: _guardando
                          ? const NeverScrollableScrollPhysics()
                          : const PageScrollPhysics(),

                      itemCount: _pasos.length,

                      onPageChanged: (pagina) {
                        setState(() {
                          _paginaActual = pagina;
                        });
                      },

                      itemBuilder: (context, index) {
                        final paso = _pasos[index];

                        return _construirPaso(paso);
                      },
                    ),
                  ),

                  const SizedBox(height: 20),

                  // -----------------------
                  // INDICADORES
                  // -----------------------

                  _construirIndicadores(),

                  const SizedBox(height: 24),

                  // -----------------------
                  // BOTONES DE NAVEGACIÓN
                  // -----------------------

                  Row(
                    children: [
                      if (_paginaActual > 0)
                        OutlinedButton(
                          onPressed: _guardando
                              ? null
                              : _paginaAnterior,

                          style:
                              OutlinedButton.styleFrom(
                            foregroundColor:
                                _colorAcento,

                            side: BorderSide(
                              color: _colorAcento,
                            ),

                            padding:
                                const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),

                            shape:
                                RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(15),
                            ),
                          ),

                          child: const Text('Atrás'),
                        ),

                      if (_paginaActual > 0)
                        const SizedBox(width: 12),

                      Expanded(
                        child: SizedBox(
                          height: 54,

                          child: ElevatedButton(
                            onPressed: _guardando
                                ? null
                                : _siguientePagina,

                            style:
                                ElevatedButton.styleFrom(
                              backgroundColor: verde,
                              foregroundColor:
                                  Colors.white,

                              disabledBackgroundColor:
                                  verde.withValues(
                                alpha: 0.6,
                              ),

                              elevation: 0,

                              shape:
                                  RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(15),
                              ),
                            ),

                            child: _guardando
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,

                                    child:
                                        CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(
                                    ultimaPagina
                                        ? 'Comenzar'
                                        : 'Siguiente',

                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------
// MODELO LOCAL PARA CONTENIDO DEL TUTORIAL
// --------------------------------------------------

class _PasoTutorial {
  final IconData icono;
  final String titulo;
  final String descripcion;

  const _PasoTutorial({
    required this.icono,
    required this.titulo,
    required this.descripcion,
  });
}
