Future<String> buildSupportDiagnostics() async => 'Platform: web\n';

Future<String> buildSupportCopyPayload(String memoryLog) async {
  return [
    'YoLoIT Support Logs',
    'Generated: ${DateTime.now().toIso8601String()}',
    'App log path: unavailable on web',
    '',
    '== System diagnostics ==',
    'Platform: web\n',
    '',
    '== Recent support events ==',
    memoryLog,
  ].join('\n');
}
