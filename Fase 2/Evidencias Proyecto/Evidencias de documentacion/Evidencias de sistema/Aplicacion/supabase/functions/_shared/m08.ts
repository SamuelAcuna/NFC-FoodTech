export const BORRADO_REAL_HABILITADO = false;
type Json = Record<string, any>;
type Config = { url: string; publica: string; administrativa: string };
type Transporte = typeof fetch;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const reciboValido = /^[0-9a-f]{64}$/;
const estados = new Set(["RECIBIDA", "SIMULADA", "BLOQUEADA", "RECHAZADA", "ERROR", "EXPIRADA"]);
const cabeceras = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
class Fallo extends Error {
  codigo: string;
  estado: number;
  constructor(codigo: string, estado = 400) { super(codigo); this.codigo = codigo; this.estado = estado; }
}
function responder(datos: Json, estado = 200) {
  return new Response(JSON.stringify({ ...datos, borrado_real_habilitado: false }), { status: estado, headers: cabeceras });
}
async function hash(texto: string, clave?: string): Promise<string> {
  const datos = new TextEncoder().encode(texto);
  const resultado = clave
    ? await crypto.subtle.sign("HMAC", await crypto.subtle.importKey("raw", new TextEncoder().encode(clave), {name: "HMAC", hash: "SHA-256"}, false, ["sign"]), datos)
    : await crypto.subtle.digest("SHA-256", datos);
  return Array.from(new Uint8Array(resultado), b => b.toString(16).padStart(2, "0")).join("");
}
function sesionDelToken(token: string): string {
  try {
    const parte = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const datos = JSON.parse(atob(parte));
    if (!uuid.test(datos.session_id)) throw new Error();
    return datos.session_id;
  } catch { throw new Fallo("SESION_NO_IDENTIFICADA", 401); }
}
function totpReciente(token: string): boolean {
  try {
    const datos = JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
    const ahora = Math.floor(Date.now() / 1000);
    return datos.aal === 'aal2' && Array.isArray(datos.amr) && datos.amr.some((a: Json) =>
      a.method === 'totp' && Number.isFinite(a.timestamp) && a.timestamp <= ahora && ahora - a.timestamp <= 300);
  } catch { return false; }
}
export function autenticacion(usuario: Json, sesionCreada: string | null, sesionFactor: string | null = null) {
  const proveedores = (usuario.identities ?? []).map((i: Json) => i.provider);
  const factores = (usuario.factors ?? []).filter((f: Json) => f.factor_type === "totp" && f.status === "verified");
  const anteriores = factores.filter((f: Json) =>
    Number.isFinite(Date.parse(f.created_at)) && sesionCreada != null &&
    Date.parse(f.created_at) <= Date.parse(sesionCreada));
  const correo = proveedores.includes("email") && !!usuario.email_confirmed_at;
  const google = proveedores.includes("google");
  return {
    contrasena: correo,
    requiere_totp: factores.length > 0,
    google,
    totp_en_sesion: !correo && google,
    disponible: correo || (google && anteriores.some((f: Json) => f.id === sesionFactor)),
    factor: (correo ? factores[0] : anteriores[0])?.id as string | undefined,
  };
}
export function crearM08(config: Config, transporte: Transporte = fetch) {
  async function llamar(ruta: string, cuerpo: Json | null, token: string, admin = false): Promise<Json> {
    const respuesta = await transporte(`${config.url}${ruta}`, {
      method: cuerpo == null ? "GET" : "POST",
      headers: { apikey: admin ? config.administrativa : config.publica, Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      ...(cuerpo == null ? {} : { body: JSON.stringify(cuerpo) }),
      signal: AbortSignal.timeout(15000),
    });
    if (!respuesta.ok) throw new Fallo(ruta.startsWith("/auth/") ? "VERIFICACION_AUTH_RECHAZADA" : "SERVIDOR_NO_DISPONIBLE", respuesta.status === 429 ? 429 : ruta.startsWith("/auth/") ? 401 : 503);
    const datos = await respuesta.json();
    if (!datos || typeof datos !== "object" || Array.isArray(datos)) throw new Fallo("RESPUESTA_INVALIDA", 502);
    return datos;
  }
  const rpc = (nombre: string, datos: Json) => llamar(`/rest/v1/rpc/${nombre}`, datos, config.administrativa, true);
  async function finalizar(solicitud: string, propietario: string, estado: string, codigo: string) {
    const resultado = await rpc("m08_local_finalizar", {p_solicitud: solicitud, p_propietario_hash: propietario, p_estado: estado, p_codigo: codigo});
    if (resultado.estado !== estado || resultado.codigo !== codigo) throw new Fallo("RESULTADO_DESCONOCIDO", 503);
  }
  async function revisar(usuario: Json, sesion: string) {
    const revision = await rpc("m08_local_preflight", { p_usuario: usuario.id, p_sesion: sesion });
    if (typeof revision.apto !== "boolean" || !Array.isArray(revision.bloqueos) || !revision.resumen) throw new Fallo("RESPUESTA_INVALIDA", 502);
    const auth = autenticacion(usuario, revision.sesion_creada ?? null, revision.sesion_factor ?? null);
    if (!auth.disponible) revision.bloqueos.push({ codigo: "REAUTENTICACION_PENDIENTE", mensaje: "No hay un mecanismo reciente habilitado. Google requiere un TOTP previamente configurado y una sesión iniciada después de configurarlo." });
    revision.apto = revision.apto && auth.disponible;
    return { revision, auth };
  }
  return async function manejar(req: Request, modo: "preflight" | "confirmar"): Promise<Response> {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cabeceras });
    if (req.method !== "POST") return responder({ codigo: "METODO_NO_PERMITIDO" }, 405);
    let solicitud: string | undefined;
    let propietario: string | undefined;
    let sesionEfimera: string | undefined;
    try {
      if (!config.url || !config.publica || !config.administrativa) throw new Fallo("CONFIGURACION_PENDIENTE", 503);
      const texto = await req.text();
      if (texto.length > 8192) throw new Fallo("SOLICITUD_INVALIDA");
      let datos: Json;
      try { datos = JSON.parse(texto); } catch { throw new Fallo("SOLICITUD_INVALIDA"); }
      if (!datos || typeof datos !== "object" || Array.isArray(datos)) throw new Fallo("SOLICITUD_INVALIDA");
      if (Object.keys(datos).some(k => !["accion", "solicitud", "recibo", "confirmacion", "contrasena", "codigo"].includes(k))) throw new Fallo("CAMPO_NO_PERMITIDO");
      if (modo === "confirmar" && datos.accion === "ESTADO") {
        if (!uuid.test(datos.solicitud) || !reciboValido.test(datos.recibo)) throw new Fallo("RECIBO_INVALIDO", 404);
        const estado = await rpc("m08_local_estado", { p_solicitud: datos.solicitud, p_recibo_hash: await hash(datos.recibo) });
        if (!estados.has(estado.estado)) throw new Fallo("RECIBO_INVALIDO", 404);
        return responder({ modo: "SIMULACION_SEGURA", estado: estado.estado, codigo: estado.codigo });
      }
      const token = /^Bearer (\S+)$/i.exec(req.headers.get("Authorization") ?? "")?.[1];
      if (!token) throw new Fallo("SESION_REQUERIDA", 401);
      const usuario = await llamar("/auth/v1/user", null, token);
      if (!uuid.test(usuario.id)) throw new Fallo("SESION_INVALIDA", 401);
      const sesion = sesionDelToken(token);
      if (modo === "preflight") {
        const { revision, auth } = await revisar(usuario, sesion);
        return responder({ modo: "SOLO_REVISION", revision: {apto: revision.apto, bloqueos: revision.bloqueos, resumen: revision.resumen, consecuencias: revision.consecuencias}, autenticacion: { contrasena: auth.contrasena, requiere_totp: auth.requiere_totp, disponible: auth.disponible, google: auth.google, totp_en_sesion: auth.totp_en_sesion } });
      }
      if (datos.accion !== "SIMULAR" || datos.confirmacion !== "ELIMINAR" || !uuid.test(datos.solicitud) || !reciboValido.test(datos.recibo)) throw new Fallo("CONFIRMACION_INVALIDA");
      const propietarioHash = await hash(`m08-local-v1:${usuario.id}`, config.administrativa);
      const reserva = await rpc("m08_local_reservar", {p_solicitud: datos.solicitud, p_propietario_hash: propietarioHash, p_recibo_hash: await hash(datos.recibo)});
      if (!estados.has(reserva.estado) || typeof reserva.nueva !== "boolean") throw new Fallo("RESPUESTA_INVALIDA", 502);
      if (!reserva.nueva) return responder({modo: "SIMULACION_SEGURA", estado: reserva.estado, codigo: reserva.codigo, duplicada: true});
      solicitud = datos.solicitud;
      propietario = propietarioHash;
      let { revision, auth } = await revisar(usuario, sesion);
      const identidadInicial = JSON.stringify(auth);
      if (!revision.apto) {
        await finalizar(solicitud!, propietario!, "BLOQUEADA", "REQUISITOS_PENDIENTES");
        return responder({modo: "SIMULACION_SEGURA", estado: "BLOQUEADA", codigo: "REQUISITOS_PENDIENTES", bloqueos: revision.bloqueos});
      }
      let tokenTotp = token;
      if (auth.contrasena) {
        if (typeof datos.contrasena !== "string" || datos.contrasena.length === 0 || datos.contrasena.length > 1024) throw new Fallo("CONTRASENA_REQUERIDA", 401);
        const acceso = await llamar("/auth/v1/token?grant_type=password", {email: usuario.email, password: datos.contrasena}, config.publica);
        if (acceso.user?.id !== usuario.id || typeof acceso.access_token !== "string") throw new Fallo("IDENTIDAD_NO_COINCIDE", 401);
        tokenTotp = acceso.access_token;
        sesionEfimera = acceso.access_token;
      }
      if (auth.totp_en_sesion && !totpReciente(token)) throw new Fallo("TOTP_SESION_RECIENTE_REQUERIDO", 401);
      if (auth.requiere_totp && !auth.totp_en_sesion) {
        if (!auth.factor || typeof datos.codigo !== "string" || !/^\d{6}$/.test(datos.codigo)) throw new Fallo("TOTP_REQUERIDO", 401);
        const desafio = await llamar(`/auth/v1/factors/${auth.factor}/challenge`, {}, tokenTotp);
        if (!uuid.test(desafio.id)) throw new Fallo("DESAFIO_INVALIDO", 502);
        const verificacion = await llamar(`/auth/v1/factors/${auth.factor}/verify`, {challenge_id: desafio.id, code: datos.codigo}, tokenTotp);
        if (typeof verificacion.access_token !== "string") throw new Fallo("IDENTIDAD_NO_COINCIDE", 401);
        sesionEfimera = verificacion.access_token;
        const verificado = await llamar("/auth/v1/user", null, verificacion.access_token);
        if (verificado.id !== usuario.id) throw new Fallo("IDENTIDAD_NO_COINCIDE", 401);
      }
      ({ revision, auth } = await revisar(await llamar("/auth/v1/user", null, token), sesion));
      if (!revision.apto || JSON.stringify(auth) !== identidadInicial) {
        await finalizar(solicitud!, propietario!, "BLOQUEADA", "REQUISITOS_CAMBIARON");
        return responder({modo: "SIMULACION_SEGURA", estado: "BLOQUEADA", codigo: "REQUISITOS_CAMBIARON", bloqueos: revision.bloqueos});
      }
      await finalizar(solicitud!, propietario!, "SIMULADA", "BORRADO_DESHABILITADO");
      return responder({modo: "SIMULACION_SEGURA", estado: "SIMULADA", codigo: "BORRADO_DESHABILITADO"});
    } catch (e) {
      const fallo = e instanceof Fallo ? e : new Fallo("RESULTADO_DESCONOCIDO", 503);
      if (solicitud && propietario && fallo.estado < 500) {
        try { await rpc("m08_local_finalizar", {p_solicitud: solicitud, p_propietario_hash: propietario, p_estado: "RECHAZADA", p_codigo: fallo.codigo}); } catch { return responder({codigo: "RESULTADO_DESCONOCIDO"}, 503); }
      }
      return responder({codigo: fallo.codigo}, fallo.estado);
    } finally {
      if (sesionEfimera) {
        try {
          await transporte(`${config.url}/auth/v1/logout?scope=local`, {
            method: "POST", headers: {apikey: config.publica, Authorization: `Bearer ${sesionEfimera}`},
            signal: AbortSignal.timeout(3000),
          });
        } catch {}
      }
    }
  };
}
export function servir(modo: "preflight" | "confirmar") {
  const runtime = (globalThis as unknown as {Deno: {env: {get(k: string): string | undefined}; serve(f: (r: Request) => Promise<Response>): void}}).Deno;
  const manejar = crearM08({url: runtime.env.get("SUPABASE_URL") ?? "", publica: runtime.env.get("SUPABASE_ANON_KEY") ?? "", administrativa: runtime.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""});
  runtime.serve(req => manejar(req, modo));
}
