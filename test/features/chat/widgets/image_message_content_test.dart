import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/chat/widgets/message_content/image_message_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

Future<Uint8List> _createPortraitPngBytes() async {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 400, 1000),
    Paint()..color = const Color(0xFFFF6600),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(400, 1000);
  final byteData = await image.toByteData(format: ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return byteData!.buffer.asUint8List();
}

class _InMemoryImageHttpOverrides extends HttpOverrides {
  final Uint8List pngBytes;
  _InMemoryImageHttpOverrides(this.pngBytes);

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _InMemoryImageHttpClient(pngBytes);
}

class _InMemoryImageHttpClient implements HttpClient {
  final Uint8List pngBytes;
  _InMemoryImageHttpClient(this.pngBytes);

  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _InMemoryImageHttpRequest(pngBytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InMemoryImageHttpRequest implements HttpClientRequest {
  final Uint8List pngBytes;
  _InMemoryImageHttpRequest(this.pngBytes);

  @override
  final HttpHeaders headers = _EmptyHttpHeaders();

  @override
  Future<HttpClientResponse> close() async =>
      _InMemoryImageHttpResponse(pngBytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _InMemoryImageHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  final Uint8List pngBytes;
  _InMemoryImageHttpResponse(this.pngBytes);

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => pngBytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(pngBytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'Full-screen image dialog keeps close icon in front of tall photo and dismisses on tap',
    (WidgetTester tester) async {
      // Simulate a portrait phone screen (matching the reported full-screen photo issue).
      tester.view.physicalSize = const Size(400, 880);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late Uint8List pngBytes;
      await tester.runAsync(() async {
        pngBytes = await _createPortraitPngBytes();
      });

      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = _InMemoryImageHttpOverrides(pngBytes);
      addTearDown(() {
        HttpOverrides.global = previousOverrides;
        PaintingBinding.instance.imageCache.clear();
      });

      const message = Message(
        id: 'msg_img_1',
        chatId: 'chat_1',
        senderId: 'user_1',
        senderName: 'Test User',
        content: '',
        type: 'image',
        timestamp: 1700000000000,
        status: 'sent',
        imageUrl: 'https://example.com/portrait.png',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 300,
                child: ImageMessageContent(message: message, isOwn: true),
              ),
            ),
          ),
        ),
      );

      // Wait for the in-memory PNG codec to resolve and lay out the image.
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
        if (tester.getSize(find.byType(Hero)).height > 0) break;
      }
      expect(tester.getSize(find.byType(Hero)).height, greaterThan(0));

      // Open the full-screen image dialog.
      await tester.tap(find.byType(Hero));
      await tester.pumpAndSettle();

      // Verify blurred backdrop is present.
      expect(find.byType(BackdropFilter), findsOneWidget);
      final backdrop = tester.widget<BackdropFilter>(
        find.byType(BackdropFilter),
      );
      expect(backdrop.filter, ImageFilter.blur(sigmaX: 10, sigmaY: 10));

      // Verify the close button is rendered LAST in the Stack (in front of the image).
      final dialogStack = tester.widget<Stack>(
        find.descendant(
          of: find.byType(BackdropFilter),
          matching: find.byType(Stack),
        ),
      );
      expect(dialogStack.children.length, 3);
      expect(dialogStack.children.last, isA<Positioned>());

      final closeButtonFinder = find.descendant(
        of: find.byType(BackdropFilter),
        matching: find.byIcon(LucideIcons.x),
      );
      expect(closeButtonFinder, findsOneWidget);

      // Tapping on the photo itself should NOT dismiss the dialog.
      await tester.tap(find.byType(InteractiveViewer));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);

      // Tapping the close button in front of the tall photo dismisses the dialog.
      await tester.tap(closeButtonFinder);
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(InteractiveViewer), findsNothing);

      // Re-open and verify tapping outside the photo on the dark backdrop dismisses.
      await tester.tap(find.byType(Hero));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
    },
  );
}
