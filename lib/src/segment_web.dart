import 'dart:js';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

class SegmentWeb {
  static void registerWith(Registrar registrar) {
    final MethodChannel channel = MethodChannel(
      'flutter_segment_analytics',
      const StandardMethodCodec(),
      registrar, // the registrar is used as the BinaryMessenger
    );
    final SegmentWeb instance = SegmentWeb();
    channel.setMethodCallHandler(instance.handleMethodCall);
  }

Future<dynamic> handleMethodCall(MethodCall call) async {
    final JsObject analytics = JsObject.fromBrowserObject(context['analytics'] as Object);
    final Map<String, dynamic> args = call.arguments as Map<String, dynamic>;

    switch (call.method) {
      case 'identify':
        analytics.callMethod('identify', [
          args['userId'],
          JsObject.jsify(args['traits'] as Object),
          JsObject.jsify(args['options'] as Object),
        ]);
      case 'track':
        analytics.callMethod('track', [
          args['eventName'],
          JsObject.jsify(args['properties'] as Object),
          JsObject.jsify(args['options'] as Object),
        ]);
      case 'screen':
        analytics.callMethod('page', [
          args['screenName'],
          JsObject.jsify(args['properties'] as Object),
          JsObject.jsify(args['options'] as Object),
        ]);
      case 'group':
        analytics.callMethod('group', [
          args['groupId'],
          JsObject.jsify(args['traits'] as Object),
          JsObject.jsify(args['options'] as Object),
        ]);
      case 'alias':
        analytics.callMethod('alias', [
          args['alias'],
          JsObject.jsify(args['options'] as Object),
        ]);
      case 'getAnonymousId':
        final JsObject user = analytics.callMethod('user') as JsObject;
        final anonymousId = user.callMethod('anonymousId');
        return anonymousId;
      case 'reset':
        analytics.callMethod('reset');
      case 'debug':
        analytics.callMethod('debug', [
          args['debug'],
        ]);
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details:
              "The segment plugin for web doesn't implement the method '${call.method}'",
        );
    }
  }
}
