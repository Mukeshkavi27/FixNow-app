import 'dart:convert';
import 'dart:io';

Never _fail(String message) {
  stderr.writeln('RELEASE CONFIGURATION ERROR: $message');
  exit(1);
}

void main(List<String> arguments) {
  final values = <String, String>{};
  for (final argument in arguments) {
    if (!argument.startsWith('--') || !argument.contains('=')) {
      _fail('Arguments must use --name=value.');
    }
    final separator = argument.indexOf('=');
    values[argument.substring(2, separator)] =
        argument.substring(separator + 1);
  }

  final environment = values['environment'];
  if (environment != 'staging' && environment != 'production') {
    _fail('Release environment must be staging or production.');
  }

  for (final name in ['auth-api-url', 'admin-api-url']) {
    final raw = values[name];
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
      _fail('$name must be a public HTTPS URL.');
    }
    if (uri.host == 'localhost' || uri.host == '127.0.0.1') {
      _fail('$name cannot use localhost.');
    }
  }

  for (final name in ['google-services', 'keystore']) {
    final path = values[name];
    if (path == null ||
        !File(path).existsSync() ||
        File(path).lengthSync() == 0) {
      _fail('$name file is missing or empty.');
    }
  }

  final googleServices =
      jsonDecode(File(values['google-services']!).readAsStringSync())
          as Map<String, dynamic>;
  final projectInfo = googleServices['project_info'] as Map<String, dynamic>?;
  final projectId = projectInfo?['project_id'] as String?;
  final expectedProjectId = values['firebase-project-id'];
  if (projectId == null || projectId != expectedProjectId) {
    _fail(
        'google-services.json project "$projectId" does not match "$expectedProjectId".');
  }

  final clients = googleServices['client'] as List<dynamic>? ?? const [];
  final packages = clients.map((client) {
    final info = (client as Map<String, dynamic>)['client_info']
        as Map<String, dynamic>?;
    final android = info?['android_client_info'] as Map<String, dynamic>?;
    return android?['package_name'];
  });
  if (!packages.contains(values['application-id'])) {
    _fail(
        'google-services.json does not contain Android package ${values['application-id']}.');
  }

  stdout.writeln('Release configuration is valid for $environment.');
}
