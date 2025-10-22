
String getBaseUrl() {
  // Usa siempre la IP local directamente
  const String localIp = "192.168.3.159"; // Tu IP local (sin / al final)
  const String puerto = "8000";

  // No se necesita manejar diferentes plataformas, siempre se usa la IP local
  return "http://$localIp:$puerto";
}

final String API_URL = getBaseUrl();
final String LOGIN_URL = "$API_URL/usuarios/login/";
final String PERFIL_URL = "$API_URL/usuarios/perfil/";
