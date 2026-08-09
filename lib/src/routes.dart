import 'package:flutter/material.dart';

/// Central route names for the OpenMinis Flutter app.
class Routes {
  // Screens
  static const String home = '/';
  static const String chat = '/chat'; // args: sessionId (String?)
  static const String providers = '/settings/providers';
  static const String modelGroups = '/settings/model-groups';
  static const String syncSettings = '/settings/sync';
  static const String soulSettings = '/settings/soul';
  static const String skills = '/settings/skills';
  static const String memory = '/settings/memory';
  static const String mcp = '/settings/mcp';
  static const String environments = '/settings/environments';
  static const String mountedFolders = '/settings/mounted-folders';
  static const String storage = '/settings/storage';
  static const String about = '/settings/about';
  static const String settings = '/settings';
  static const String wiki = '/wiki';
  static const String shareInbox = '/share';
}

/// Builds the chat route URI with an optional session id.
String chatRoute([String? sessionId]) =>
    sessionId == null ? Routes.chat : '${Routes.chat}?id=$sessionId';

/// Pushes a route by name; if it's the chat route it carries optional args.
void pushNamed(BuildContext context, String route, {Object? args}) {
  Navigator.of(context).pushNamed(route, arguments: args);
}
