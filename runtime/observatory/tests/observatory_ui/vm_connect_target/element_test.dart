// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:html';
import 'dart:async';
import 'package:unittest/unittest.dart';
import 'package:observatory/service_html.dart';
import 'package:observatory/src/elements/helpers/rendering_queue.dart';
import 'package:observatory/src/elements/vm_connect_target.dart';

main() {
  VMConnectTargetElement.tag.ensureRegistration();

  final TimedRenderingBarrier barrier = new TimedRenderingBarrier();
  final RenderingQueue queue = new RenderingQueue.fromBarrier(barrier);

  WebSocketVMTarget t;
  setUp(() {
    t = new WebSocketVMTarget("a network address");
  });
  group('instantiation', () {
    test('no other parameters', () {
      final VMConnectTargetElement e = new VMConnectTargetElement(t);
      expect(e, isNotNull, reason: 'element correctly created');
      expect(e.target, t, reason: 'target not setted');
      expect(e.current, isFalse, reason: 'default to not current');
    });
    test('isCurrent: false', () {
      final VMConnectTargetElement e = new VMConnectTargetElement(t,
                                            current:false);
      expect(e, isNotNull, reason: 'element correctly created');
      expect(e.target, t, reason: 'target not setted');
      expect(e.current, isFalse, reason: 'default to not current');
    });
    test('isCurrent: true', () {
      final VMConnectTargetElement e = new VMConnectTargetElement(t,
                                            current:true);
      expect(e, isNotNull, reason: 'element correctly created');
      expect(e.target, t, reason: 'target not setted');
      expect(e.current, isTrue, reason: 'default to not current');
    });
  });
  test('elements created after attachment', () async {
    final VMConnectTargetElement e = new VMConnectTargetElement(t,
        queue: queue);
    document.body.append(e);
    await e.onRendered.first;
    expect(e.children.length, isNonZero, reason: 'has elements');
    e.remove();
    await e.onRendered.first;
    expect(e.children.length, isZero, reason: 'is empty');
  });
  group('events are fired', () {
    VMConnectTargetElement e;
    StreamSubscription sub;
    setUp(() async {
      e = new VMConnectTargetElement(t, queue: queue);
      document.body.append(e);
      await e.onRendered.first;
    });
    tearDown(() async {
      sub.cancel();
      e.remove();
      await e.onRendered.first;
    });
    test('navigation after connect', () async {
      sub = window.onPopState.listen(expectAsync((_) {}, count: 1,
        reason: 'event is fired'));
      e.querySelector('a').click();
    });
    test('onConnect events (DOM)', () async {
      sub = e.onConnect.listen(expectAsync((TargetEvent event) {
        expect(event, isNotNull, reason: 'event is passed');
        expect(event.target, t, reason: 'target is the same');
      }, count: 1, reason: 'event is fired'));
      e.querySelector('a').click();
    });
    test('onConnect events (code)', () async {
      sub = e.onConnect.listen(expectAsync((TargetEvent event) {
        expect(event, isNotNull, reason: 'event is passed');
        expect(event.target, t, reason: 'target is the same');
      }, count: 1, reason: 'event is fired'));
      e.connect();
    });
    test('onRemove events (DOM)', () async {
      sub = e.onDelete.listen(expectAsync((TargetEvent event) {
        expect(event, isNotNull, reason: 'event is passed');
        expect(event.target, t, reason: 'target is the same');
      }, count: 1, reason: 'event is fired'));
      e.querySelector('button').click();
    });
    test('onRemove events (code)', () async {
      sub = e.onDelete.listen(expectAsync((TargetEvent event) {
        expect(event, isNotNull, reason: 'event is passed');
        expect(event.target, t, reason: 'target is the same');
      }, count: 1, reason: 'event is fired'));
      e.delete();
    });
  });
}
