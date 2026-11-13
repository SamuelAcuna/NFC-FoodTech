import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StockCompra {
  final double? disponible;
  final double? solicitadaEnBase;
  final String? unidadBase;
  final bool alimentoPermitido;

  const StockCompra({
    this.disponible,
    this.solicitadaEnBase,
    this.unidadBase,
    this.alimentoPermitido = true,
  });

  bool? get suficiente {
    if (disponible == null || solicitadaEnBase == null) return null;
    return disponible! + 0.0000001 >= solicitadaEnBase!;
  }
}

double? _numero(dynamic valor) {
  final numero = valor is num
      ? valor.toDouble()
      : double.tryParse(valor?.toString() ?? '');
  return numero != null && numero.isFinite ? numero : null;
}

double? cantidadCompraEnBase(
  dynamic cantidad,
  String unidad,
  String unidadBase,
) {
  final numero = _numero(cantidad);
  if (numero == null || numero <= 0) return null;

  final origen = unidad.trim().toLowerCase();
  final base = unidadBase.trim().toLowerCase();
  double factor;

  if ((base == 'g' && origen == 'g') ||
      (base == 'ml' && origen == 'ml') ||
      (base == 'un' && origen == 'un')) {
    factor = 1;
  } else if ((base == 'g' && origen == 'kg') ||
      (base == 'ml' && origen == 'l')) {
    factor = 1000;
  } else {
    return null;
  }

  final resultado = numero * factor;
  return resultado.isFinite ? resultado : null;
}

Future<StockCompra> consultarStockCompra({
  required SupabaseClient supabase,
  required String hogarId,
  required int alimentoId,
  required dynamic cantidad,
  required String unidad,
}) async {
  if (hogarId.isEmpty) {
    return const StockCompra(alimentoPermitido: false);
  }

  const espera = Duration(seconds: 8);
  final alimento = await supabase
      .from('alimento')
      .select('id, hogar_id, unidad_base')
      .eq('id', alimentoId)
      .maybeSingle()
      .timeout(espera);

  // El catálogo global es compartido; los alimentos locales son del hogar.
  if (alimento == null ||
      alimento['id']?.toString() != alimentoId.toString() ||
      (alimento['hogar_id'] != null &&
          alimento['hogar_id'].toString() != hogarId)) {
    return const StockCompra(alimentoPermitido: false);
  }

  final base = alimento['unidad_base']?.toString();
  final solicitada = cantidadCompraEnBase(cantidad, unidad, base ?? '');
  var disponible = 0.0;
  var cantidadesValidas = true;
  const pagina = 400;
  var desde = 0;

  while (true) {
    final respuesta = await supabase
        .from('despensa_item')
        .select('id, hogar_id, alimento_id, estado, cantidad_restante')
        .eq('hogar_id', hogarId)
        .eq('alimento_id', alimentoId)
        .eq('estado', 'DISPONIBLE')
        .gt('cantidad_restante', 0)
        .order('id')
        .range(desde, desde + pagina - 1)
        .timeout(espera);

    for (final item in respuesta) {
      if (item['hogar_id']?.toString() != hogarId ||
          item['alimento_id']?.toString() != alimentoId.toString() ||
          item['estado'] != 'DISPONIBLE') {
        continue;
      }
      final restante = _numero(item['cantidad_restante']);
      if (restante == null || restante < 0) {
        cantidadesValidas = false;
      } else {
        disponible += restante;
      }
    }

    if (respuesta.length < pagina) break;
    desde += pagina;
  }

  return StockCompra(
    disponible: cantidadesValidas && disponible.isFinite ? disponible : null,
    solicitadaEnBase: solicitada,
    unidadBase: base,
  );
}

String _cantidadTexto(dynamic valor, String unidad) {
  final numero = _numero(valor);
  if (numero == null) return 'Sin datos';
  final texto = numero
      .toStringAsFixed(6)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '')
      .replaceAll('.', ',');
  return '$texto ${unidad == 'l' ? 'L' : unidad}';
}

Future<bool> confirmarStockCompra({
  required BuildContext context,
  required SupabaseClient supabase,
  required String hogarId,
  required int alimentoId,
  required String nombre,
  required dynamic cantidad,
  required String unidad,
}) async {
  StockCompra stock;
  try {
    stock = await consultarStockCompra(
      supabase: supabase,
      hogarId: hogarId,
      alimentoId: alimentoId,
      cantidad: cantidad,
      unidad: unidad,
    );
  } catch (error) {
    debugPrint('No se pudo comprobar el stock de compra: $error');
    stock = const StockCompra();
  }

  if (!context.mounted) return false;
  if (stock.alimentoPermitido && stock.suficiente == false) return true;

  final permitido = stock.alimentoPermitido;
  final suficiente = stock.suficiente == true;
  final existencias = stock.disponible == null || stock.unidadBase == null
      ? 'No disponible'
      : _cantidadTexto(stock.disponible, stock.unidadBase!);
  var respondido = false;

  return await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (dialogContext) {
          void responder(bool continuar) {
            if (respondido) return;
            respondido = true;
            Navigator.of(dialogContext).pop(continuar);
          }

          return AlertDialog(
            title: Text(
              !permitido
                  ? 'Alimento no disponible para este hogar'
                  : suficiente
                  ? 'Este alimento ya está en tu despensa'
                  : 'No se pudo comprobar el stock',
            ),
            content: Text(
              !permitido
                  ? 'No pudimos verificar que $nombre esté disponible '
                        'para el hogar seleccionado. Actualiza la lista.'
                  : '$nombre\n\n'
                        'Stock disponible: $existencias.\n'
                        'Cantidad que deseas comprar: '
                        '${_cantidadTexto(cantidad, unidad)}.\n\n'
                        '${suficiente ? 'Ya existe stock suficiente para esa cantidad.' : 'No podemos determinar si el stock es suficiente. No se comparan unidades incompatibles.'}\n\n'
                        '¿Quieres continuar igualmente?',
            ),
            actions: [
              TextButton(
                onPressed: () => responder(false),
                child: Text(permitido ? 'Cancelar' : 'Cerrar'),
              ),
              if (permitido)
                ElevatedButton(
                  onPressed: () => responder(true),
                  child: const Text('Continuar igualmente'),
                ),
            ],
          );
        },
      ) ??
      false;
}
