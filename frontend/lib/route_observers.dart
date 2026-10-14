import 'package:flutter/material.dart';

/// Shared [RouteObserver] for screens that need refresh when a pushed route pops.
final RouteObserver<ModalRoute<void>> mindSyncRouteObserver =
    RouteObserver<ModalRoute<void>>();
