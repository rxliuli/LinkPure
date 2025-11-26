import 'package:flutter_test/flutter_test.dart';
import 'package:link_pure/services/clipboard_service.dart';

void main() {
  group('ClipboardService', () {
    test('should be a singleton', () {
      final instance1 = ClipboardService();
      final instance2 = ClipboardService();
      expect(identical(instance1, instance2), true);
    });

    // Note: Actual clipboard monitoring tests require platform-specific setup
    // and would need to be run on actual desktop platforms
    // The service auto-starts on desktop platforms when initialized
  });
}
