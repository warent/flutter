// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'app_bar.dart';
import 'debug.dart';
import 'dialog.dart';
import 'drawer_item.dart';
import 'flat_button.dart';
import 'icon.dart';
import 'icon_theme.dart';
import 'icon_theme_data.dart';
import 'page.dart';
import 'progress_indicator.dart';
import 'scaffold.dart';
import 'scrollbar.dart';
import 'theme.dart';

/// A [DrawerItem] to show an about box.
///
/// Place this in a [Drawer], specifying your preferred application name,
/// version, icon, and copyright in the appropriate fields.
///
/// The about box will include a button that shows licenses for software used by
/// the application.
///
/// If your application does not have a [Drawer], you should provide an
/// affordance to call [showAboutDialog] or (at least) [showLicensePage].
// TODO(ianh): Mention the API for registering more licenses once it exists.
class AboutDrawerItem extends StatelessWidget {
  /// Creates a drawer item for showing an about box.
  ///
  /// The arguments are all optional. The application name, if omitted, will be
  /// derived from the nearest [Title] widget. The version, icon, and legalese
  /// values default to the empty string.
  AboutDrawerItem({
    Key key,
    this.icon: const Icon(null),
    this.child,
    this.applicationName,
    this.applicationVersion,
    this.applicationIcon,
    this.applicationLegalese,
    this.aboutBoxChildren
  }) : super(key: key);

  /// The icon to show for this drawer item.
  ///
  /// By default no icon is shown.
  ///
  /// This is not necessarily the same as the image shown in the dialog box
  /// itself; which is controlled by the [applicationIcon] property.
  final Widget icon;

  /// The label to show on this drawer item.
  ///
  /// Defaults to a text widget that says "About Foo" where "Foo" is the
  /// application name specified by [applicationName].
  final Widget child;

  /// The name of the application.
  ///
  /// This string is used in the default label for this drawer item (see
  /// [child]) and as the caption of the [AboutDialog] that is shown.
  ///
  /// Defaults to the value of [Title.title], if a [Title] widget can be found.
  /// Otherwise, defaults to "this Flutter application".
  // TODO(ianh): once https://github.com/flutter/flutter/issues/3648 is fixed:
  // /// Otherwise, defaults to [Platform.resolvedExecutable].
  final String applicationName;

  /// The version of this build of the application.
  ///
  /// This string is shown under the application name in the [AboutDialog].
  ///
  /// Defaults to the empty string.
  final String applicationVersion;

  /// The icon to show next to the application name in the [AboutDialog].
  ///
  /// By default no icon is shown.
  ///
  /// Typically this will be an [ImageIcon] widget. It should honor the
  /// [IconTheme]'s [IconThemeData.size].
  ///
  /// This is not necessarily the same as the icon shown on the drawer item
  /// itself, which is controlled by the [icon] property.
  final Widget applicationIcon;

  /// A string to show in small print in the [AboutDialog].
  ///
  /// Typically this is a copyright notice.
  ///
  /// Defaults to the empty string.
  final String applicationLegalese;

  /// Widgets to add to the [AboutDialog] after the name, version, and legalese.
  ///
  /// This could include a link to a Web site, some descriptive text, credits,
  /// or other information to show in the about box.
  ///
  /// Defaults to nothing.
  final List<Widget> aboutBoxChildren;

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasMaterial(context));
    return new DrawerItem(
      icon: icon,
      child: child ?? new Text('About ${applicationName ?? _defaultApplicationName(context)}'),
      onPressed: () {
        showAboutDialog(
          context: context,
          applicationName: applicationName,
          applicationVersion: applicationVersion,
          applicationIcon: applicationIcon,
          applicationLegalese: applicationLegalese,
          children: aboutBoxChildren
        );
      }
    );
  }
}

/// Displays an [AboutDialog], which describes the application and provides a
/// button to show licenses for software used by the application.
///
/// The arguments correspond to the properties on [AboutDialog].
///
/// If the application has a [Drawer], consider using [AboutDrawerItem] instead
/// of calling this directly.
///
/// If you do not need an about box in your application, you should at least
/// provide an affordance to call [showLicensePage].
void showAboutDialog({
  @required BuildContext context,
  String applicationName,
  String applicationVersion,
  Widget applicationIcon,
  String applicationLegalese,
  List<Widget> children
}) {
  showDialog/*<Null>*/(
    context: context,
    child: new AboutDialog(
      applicationName: applicationName,
      applicationVersion: applicationVersion,
      applicationIcon: applicationIcon,
      applicationLegalese: applicationLegalese,
      children: children
    )
  );
}

/// Displays a [LicensePage], which shows licenses for software used by the
/// application.
///
/// The arguments correspond to the properties on [LicensePage].
///
/// If the application has a [Drawer], consider using [AboutDrawerItem] instead
/// of calling this directly.
///
/// The [AboutDialog] shown by [showAboutDialog] includes a button that calls
/// [showLicensePage].
// TODO(ianh): Mention the API for registering more licenses once it exists.
void showLicensePage({
  @required BuildContext context,
  String applicationName,
  String applicationVersion,
  Widget applicationIcon,
  String applicationLegalese
}) {
  // TODO(ianh): remove pop once https://github.com/flutter/flutter/issues/4667 is fixed
  Navigator.pop(context);
  Navigator.push(context, new MaterialPageRoute<Null>(
    builder: (BuildContext context) => new LicensePage(
      applicationName: applicationName,
      applicationVersion: applicationVersion,
      applicationLegalese: applicationLegalese
    )
  ));
}

/// An about box. This is a dialog box with the application's icon, name,
/// version number, and copyright, plus a button to show licenses for software
/// used by the application.
///
/// To show an [AboutDialog], use [showAboutDialog].
class AboutDialog extends StatelessWidget {
  /// Creates an about box.
  ///
  /// The arguments are all optional. The application name, if omitted, will be
  /// derived from the nearest [Title] widget. The version, icon, and legalese
  /// values default to the empty string.
  AboutDialog({
    Key key,
    this.applicationName,
    this.applicationVersion,
    this.applicationIcon,
    this.applicationLegalese,
    this.children,
  }) : super(key: key);

  /// The name of the application.
  ///
  /// Defaults to the value of [Title.title], if a [Title] widget can be found.
  /// Otherwise, defaults to "this Flutter application".
  // TODO(ianh): once https://github.com/flutter/flutter/issues/3648 is fixed:
  // /// Otherwise, defaults to [Platform.resolvedExecutable].
  final String applicationName;

  /// The version of this build of the application.
  ///
  /// This string is shown under the application name.
  ///
  /// Defaults to the empty string.
  final String applicationVersion;

  /// The icon to show next to the application name.
  ///
  /// By default no icon is shown.
  ///
  /// Typically this will be an [ImageIcon] widget. It should honor the
  /// [IconTheme]'s [IconThemeData.size].
  final Widget applicationIcon;

  /// A string to show in small print.
  ///
  /// Typically this is a copyright notice.
  ///
  /// Defaults to the empty string.
  final String applicationLegalese;

  /// Widgets to add to the dialog box after the name, version, and legalese.
  ///
  /// This could include a link to a Web site, some descriptive text, credits,
  /// or other information to show in the about box.
  ///
  /// Defaults to nothing.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final String name = applicationName ?? _defaultApplicationName(context);
    final String version = applicationVersion ?? _defaultApplicationVersion(context);
    final Widget icon = applicationIcon ?? _defaultApplicationIcon(context);
    List<Widget> body = <Widget>[];
    if (icon != null)
      body.add(new IconTheme(data: new IconThemeData(size: 48.0), child: icon));
    body.add(new Flexible(
      child: new Padding(
        padding: new EdgeInsets.symmetric(horizontal: 24.0),
        child: new BlockBody(
          children: <Widget>[
            new Text(name, style: Theme.of(context).textTheme.headline),
            new Text(version, style: Theme.of(context).textTheme.body1),
            new Container(height: 18.0),
            new Text(applicationLegalese ?? '', style: Theme.of(context).textTheme.caption)
          ]
        )
      )
    ));
    body = <Widget>[
      new Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: body
      ),
    ];
    if (children != null)
      body.addAll(children);
    return new AlertDialog(
      content: new Block(
        children: body
      ),
      actions: <Widget>[
        new FlatButton(
          child: new Text('VIEW LICENSES'),
          onPressed: () {
            showLicensePage(
              context: context,
              applicationName: applicationName,
              applicationVersion: applicationVersion,
              applicationIcon: applicationIcon,
              applicationLegalese: applicationLegalese
            );
          }
        ),
        new FlatButton(
          child: new Text('CLOSE'),
          onPressed: () {
            Navigator.pop(context);
          }
        ),
      ]
    );
  }
}

/// A page that shows licenses for software used by the application.
///
/// To show a [LicensePage], use [showLicensePage].
// TODO(ianh): Mention the API for registering more licenses once it exists.
class LicensePage extends StatefulWidget {
  /// Creates a page that shows licenses for software used by the application.
  ///
  /// The arguments are all optional. The application name, if omitted, will be
  /// derived from the nearest [Title] widget. The version and legalese values
  /// default to the empty string.
  // TODO(ianh): Mention the API for registering more licenses once it exists.
  const LicensePage({
    Key key,
    this.applicationName,
    this.applicationVersion,
    this.applicationLegalese
  }) : super(key: key);

  /// The name of the application.
  ///
  /// Defaults to the value of [Title.title], if a [Title] widget can be found.
  /// Otherwise, defaults to "this Flutter application".
  // TODO(ianh): once https://github.com/flutter/flutter/issues/3648 is fixed:
  // /// Otherwise, defaults to [Platform.resolvedExecutable].
  final String applicationName;

  /// The version of this build of the application.
  ///
  /// This string is shown under the application name.
  ///
  /// Defaults to the empty string.
  final String applicationVersion;

  /// A string to show in small print.
  ///
  /// Typically this is a copyright notice.
  ///
  /// Defaults to the empty string.
  final String applicationLegalese;

  @override
  _LicensePageState createState() => new _LicensePageState();
}

class _LicensePageState extends State<LicensePage> {

  @override
  void initState() {
    super.initState();
    _initLicenses();
  }

  List<Widget> _licenses = <Widget>[];
  bool _loaded = false;

  Future<Null> _initLicenses() async {
    await for (LicenseEntry license in LicenseRegistry.licenses) {
      setState(() {
        _licenses.add(new Padding(
          padding: new EdgeInsets.symmetric(vertical: 18.0),
          child: new Text(
            '🍀‬', // That's U+1F340. Could also use U+2766 (❦) if U+1F340 doesn't work everywhere.
            textAlign: TextAlign.center
          )
        ));
        _licenses.add(new Container(
          decoration: new BoxDecoration(
            border: new Border(bottom: new BorderSide(width: 0.0))
          ),
          child: new Text(
            license.packages.join(', '),
            style: new TextStyle(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center
          )
        ));
        for (LicenseParagraph paragraph in license.paragraphs) {
          if (paragraph.indent == LicenseParagraph.centeredIndent) {
            _licenses.add(new Padding(
              padding: new EdgeInsets.only(top: 16.0),
              child: new Text(
                paragraph.text,
                style: new TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center
              )
            ));
          } else {
            assert(paragraph.indent >= 0);
            _licenses.add(new Padding(
              padding: new EdgeInsets.only(top: 8.0, left: 16.0 * paragraph.indent),
              child: new Text(paragraph.text)
            ));
          }
        }
      });
    }
    setState(() {
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final String name = config.applicationName ?? _defaultApplicationName(context);
    final String version = config.applicationVersion ?? _defaultApplicationVersion(context);
    final List<Widget> contents = <Widget>[
      new Text(name, style: Theme.of(context).textTheme.headline, textAlign: TextAlign.center),
      new Text(version, style: Theme.of(context).textTheme.body1, textAlign: TextAlign.center),
      new Container(height: 18.0),
      new Text(config.applicationLegalese ?? '', style: Theme.of(context).textTheme.caption, textAlign: TextAlign.center),
      new Container(height: 18.0),
      new Text('Powered by Flutter', style: Theme.of(context).textTheme.body1, textAlign: TextAlign.center),
      new Container(height: 24.0),
    ];
    contents.addAll(_licenses);
    if (!_loaded) {
      contents.add(new Padding(
        padding: new EdgeInsets.symmetric(vertical: 24.0),
        child: new Center(
          child: new CircularProgressIndicator()
        )
      ));
    }
    return new Scaffold(
      appBar: new AppBar(
        title: new Text('Licenses')
      ),
      body: new DefaultTextStyle(
        style: Theme.of(context).textTheme.caption,
        child: new Scrollbar(
          child: new LazyBlock(
            padding: new EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
            delegate: new LazyBlockChildren(
              children: contents
            )
          )
        )
      )
    );
  }
}

String _defaultApplicationName(BuildContext context) {
  Title ancestorTitle = context.ancestorWidgetOfExactType(Title);
  return ancestorTitle?.title ?? 'this Flutter application';
  // TODO(ianh): once https://github.com/flutter/flutter/issues/3648 is fixed,
  // replace the string in the previous line with:
  //   Platform.resolvedExecutable.split(Platform.pathSeparator).last
  // (then fix the dartdocs in the classes above)
}

String _defaultApplicationVersion(BuildContext context) {
  // TODO(ianh): Get this from the embedder somehow.
  return '';
}

Widget _defaultApplicationIcon(BuildContext context) {
  // TODO(ianh): Get this from the embedder somehow.
  return null;
}
