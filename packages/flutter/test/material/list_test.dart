// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MaterialList default control', (WidgetTester tester) async {
    await tester.pumpWidget(new Center(child: new MaterialList()));
  });
}
