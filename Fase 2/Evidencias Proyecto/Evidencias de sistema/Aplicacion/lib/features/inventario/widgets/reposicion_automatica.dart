import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:nfc_foodtech_app/shared/widgets/sugerencias_compra.dart';

class ResultadoMovimientoAlimento {
  final bool registrado;
  final bool incierto;
  final String mensaje;

  const ResultadoMovimientoAlimento({
    required this.registrado,
    this.incierto = false,
    required this.mensaje,
  });
}

bool _respuestaIncierta(PostgrestException error) {
  final codigo = error.code ?? '';
  final http = RegExp(r'^\d{3}$').hasMatch(codigo)
      ? int.tryParse(codigo)
      : null;
  return codigo.isEmpty ||
      codigo.startsWith('08') ||
      (http != null && (http < 400 || http >= 500));
}

class ReposicionAutomatica {
  final SupabaseClient supabase;
  final Future<bool> Function()? verificarAcceso;
  Future<ResultadoMovimientoAlimento>? _enCurso;
  ResultadoMovimientoAlimento? _resultado;

  ReposicionAutomatica({required this.supabase, this.verificarAcceso});

  // Una instancia corresponde a una operación de la pantalla de movimiento.
  // No se repiten consumos confirmados ni solicitudes de resultado incierto.
  Future<ResultadoMovimientoAlimento> registrar({
    required String hogarId,
    required String ingresoId,
    required String tipo,
    required double cantidad,
    int? motivoDescarte,
    required Future<String?> Function(List<Map<String, dynamic>>)
    seleccionarLista,
  }) {
    if (_resultado != null) return Future.value(_resultado);
    return _enCurso ??=
        _registrar(
              hogarId: hogarId,
              ingresoId: ingresoId,
              tipo: tipo,
              cantidad: cantidad,
              motivoDescarte: motivoDescarte,
              seleccionarLista: seleccionarLista,
            )
            .then((resultado) {
              if (resultado.registrado || resultado.incierto)
                _resultado = resultado;
              return resultado;
            })
            .whenComplete(() => _enCurso = null);
  }

  Future<ResultadoMovimientoAlimento> _registrar({
    required String hogarId,
    required String ingresoId,
    required String tipo,
    required double cantidad,
    int? motivoDescarte,
    required Future<String?> Function(List<Map<String, dynamic>>)
    seleccionarLista,
  }) async {
    final usuarioId = supabase.auth.currentUser?.id;
    var enviado = false;
    int? alimentoId;
    try {
      if (usuarioId == null ||
          hogarId.isEmpty ||
          ingresoId.isEmpty ||
          !cantidad.isFinite ||
          cantidad <= 0 ||
          !['CONSUMO', 'DESCARTE'].contains(tipo)) {
        throw StateError('Los datos del movimiento no son válidos.');
      }
      final ingreso = await supabase
          .from('despensa_item')
          .select('id, hogar_id, alimento_id')
          .eq('id', ingresoId)
          .eq('hogar_id', hogarId)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));
      alimentoId = int.tryParse(ingreso?['alimento_id']?.toString() ?? '');
      if (ingreso == null ||
          ingreso['id']?.toString() != ingresoId ||
          ingreso['hogar_id']?.toString() != hogarId ||
          alimentoId == null ||
          supabase.auth.currentUser?.id != usuarioId) {
        throw StateError(
          'El ingreso no está disponible en este hogar o cambió la sesión.',
        );
      }
      if (verificarAcceso != null && !await verificarAcceso!()) {
        throw StateError('No se pudo confirmar el acceso al hogar.');
      }
      enviado = true;
      await supabase
          .rpc(
            'registrar_movimiento_despensa',
            params: {
              'p_despensa_item_id': ingresoId,
              'p_tipo': tipo,
              'p_cantidad': cantidad,
              'p_tipo_desperdicio_id': tipo == 'DESCARTE'
                  ? motivoDescarte
                  : null,
            },
          )
          .timeout(const Duration(seconds: 8));
    } catch (error) {
      final incierto =
          enviado &&
          (error is! PostgrestException || _respuestaIncierta(error));
      return ResultadoMovimientoAlimento(
        registrado: false,
        incierto: incierto,
        mensaje: incierto
            ? 'No se confirmó el movimiento. Comprueba el inventario antes de realizar otra operación. No se reenviará desde esta pantalla.'
            : 'No se pudo registrar: ${error is PostgrestException ? error.message : error}',
      );
    }

    if (tipo != 'CONSUMO') {
      return const ResultadoMovimientoAlimento(
        registrado: true,
        mensaje: 'Descarte registrado.',
      );
    }
    final reposicion = await _reponer(
      hogarId: hogarId,
      alimentoId: alimentoId,
      usuarioId: usuarioId,
      seleccionarLista: seleccionarLista,
    );
    return ResultadoMovimientoAlimento(
      registrado: true,
      mensaje: 'Consumo registrado. $reposicion',
    );
  }

  Future<bool> _stockCero(String hogarId, int alimentoId) async {
    const pagina = 400;
    var total = 0.0;
    final vistos = <String>{};
    for (var desde = 0; ; desde += pagina) {
      final filas = await supabase
          .from('despensa_item')
          .select('id, hogar_id, alimento_id, estado, cantidad_restante')
          .eq('hogar_id', hogarId)
          .eq('alimento_id', alimentoId)
          .order('id')
          .range(desde, desde + pagina - 1)
          .timeout(const Duration(seconds: 8));
      for (final fila in filas) {
        final id = fila['id']?.toString() ?? '';
        final cantidad = double.tryParse(
          fila['cantidad_restante']?.toString() ?? '',
        );
        final estado = fila['estado'];
        if (id.isEmpty ||
            fila['hogar_id']?.toString() != hogarId ||
            fila['alimento_id']?.toString() != alimentoId.toString() ||
            cantidad == null ||
            !cantidad.isFinite ||
            cantidad < 0 ||
            !['DISPONIBLE', 'AGOTADO', 'DESECHADO'].contains(estado) ||
            (estado != 'DISPONIBLE' && cantidad != 0)) {
          throw StateError(
            'No se pudo verificar el stock completo del alimento.',
          );
        }
        if (vistos.add(id) && estado == 'DISPONIBLE') total += cantidad;
      }
      if (filas.length < pagina) break;
    }
    if (!total.isFinite) throw StateError('Stock fuera de rango.');
    return total == 0;
  }

  Future<String> _reponer({
    required String hogarId,
    required int alimentoId,
    required String usuarioId,
    required Future<String?> Function(List<Map<String, dynamic>>)
    seleccionarLista,
  }) async {
    var insertando = false;
    try {
      if (!await _stockCero(hogarId, alimentoId)) {
        return 'Reposición omitida: todavía existe stock disponible.';
      }
      final listas = <Map<String, dynamic>>[];
      const pagina = 400;
      for (var desde = 0; ; desde += pagina) {
        final filas = await supabase
            .from('lista_compra')
            .select('id, nombre, hogar_id, estado')
            .eq('hogar_id', hogarId)
            .eq('estado', 'ABIERTA')
            .order('id')
            .range(desde, desde + pagina - 1)
            .timeout(const Duration(seconds: 8));
        for (final fila in filas) {
          if (fila['hogar_id']?.toString() != hogarId ||
              fila['estado'] != 'ABIERTA' ||
              (fila['id']?.toString() ?? '').isEmpty) {
            throw StateError('No se pudieron verificar las listas del hogar.');
          }
        }
        listas.addAll(filas);
        if (filas.length < pagina) break;
      }
      if (listas.isEmpty)
        return 'Reposición omitida: no hay una lista abierta.';
      final listaId = listas.length == 1
          ? listas.single['id'].toString()
          : await seleccionarLista(listas);
      if (listaId == null)
        return 'Reposición omitida: no se seleccionó una lista.';
      if (!listas.any((lista) => lista['id'].toString() == listaId)) {
        throw StateError(
          'La lista elegida no pertenece a las opciones del hogar.',
        );
      }

      final resultado = await consultarSugerenciasCompra(
        supabase: supabase,
        hogarId: hogarId,
        listaId: listaId,
        alimentoId: alimentoId,
      );
      if (resultado.pendientes.contains(alimentoId)) {
        return 'Reposición omitida: ya existe un producto pendiente.';
      }
      if (resultado.registrosInvalidos > 0 ||
          resultado.sugerencias.length != 1) {
        return 'Reposición omitida: no hay historial habitual válido para este alimento.';
      }
      final sugerencia = resultado.sugerencias.single;
      if (sugerencia.alimentoId != alimentoId ||
          sugerencia.disponible != 0 ||
          !await _stockCero(hogarId, alimentoId)) {
        return 'Reposición omitida: las existencias cambiaron.';
      }
      await validarListaSugerenciasCompra(
        supabase: supabase,
        hogarId: hogarId,
        listaId: listaId,
      );
      if (await existePendienteSugerido(
        supabase: supabase,
        listaId: listaId,
        alimentoId: alimentoId,
      )) {
        return 'Reposición omitida: ya existe un producto pendiente.';
      }
      if (supabase.auth.currentUser?.id != usuarioId) {
        return 'Reposición omitida: la sesión cambió.';
      }
      // Se reutiliza el origen de consumo ya admitido por el modelo actual.
      // Las consultas previas no garantizan exclusión entre dispositivos.
      if (verificarAcceso != null && !await verificarAcceso!()) {
        return 'Reposición omitida: no se pudo confirmar el acceso al hogar.';
      }
      insertando = true;
      await supabase
          .from('lista_compra_item')
          .insert({
            'lista_id': listaId,
            'alimento_id': alimentoId,
            'cantidad': sugerencia.sugerido,
            'unidad': sugerencia.unidadBase,
            'origen': 'SUGERIDO_CONSUMO',
            'estado': 'PENDIENTE',
            'agregado_por': usuarioId,
          })
          .timeout(const Duration(seconds: 8));
      return 'Reposición agregada: ${sugerencia.nombre}, ${sugerencia.sugerido} ${sugerencia.unidadBase}.';
    } catch (error) {
      if (insertando &&
          (error is! PostgrestException || _respuestaIncierta(error))) {
        return 'Reposición no confirmada. Revisa la lista antes de agregar el producto; no se reenviará automáticamente.';
      }
      return 'Reposición omitida: ${error is PostgrestException ? error.message : error}';
    }
  }
}
