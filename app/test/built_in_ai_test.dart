// Run with --dart-define=AI_ENDPOINT=... to check a private build really carries its default AI.
import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/api.dart';

void main() {
  test('the default AI from the build', () {
    final api = Api();
    expect(api.builtInEndpoint, const String.fromEnvironment('AI_ENDPOINT'));
    expect(api.hasBuiltInAi, const String.fromEnvironment('AI_ENDPOINT').isNotEmpty);
    // ignore: avoid_print
    print('built-in AI: "${api.builtInEndpoint}" model "${api.builtInModel}" -> button shown: ${api.hasBuiltInAi}');
  });
}
