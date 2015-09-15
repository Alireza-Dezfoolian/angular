library angular2.transform.directive_linker.linker;

import 'dart:async';

import 'package:angular2/src/transform/common/asset_reader.dart';
import 'package:angular2/src/transform/common/logging.dart';
import 'package:angular2/src/transform/common/names.dart';
import 'package:angular2/src/transform/common/model/import_export_model.pb.dart';
import 'package:angular2/src/transform/common/model/ng_deps_model.pb.dart';
import 'package:barback/barback.dart';
import 'package:code_transformers/assets.dart';

/// Checks the `.ng_deps.json` file represented by `entryPoint` and
/// determines whether it is necessary to the functioning of the Angular 2
/// Dart app.
///
/// An `.ng_deps.json` file is not necessary if:
/// 1. It does not register any `@Injectable` types with the system.
/// 2. It does not import any libraries whose `.ng_deps.json` files register
///    any `@Injectable` types with the system.
///
/// Since `@Directive` and `@Component` inherit from `@Injectable`, we know
/// we will not miss processing any classes annotated with those tags.
Future<bool> isNecessary(AssetReader reader, AssetId entryPoint) async {
  if (!(await reader.hasInput(entryPoint))) return false;
  var jsonString = await reader.readAsString(entryPoint);
  if (jsonString == null || jsonString.isEmpty) return false;
  var ngDepsModel = new NgDepsModel.fromJson(jsonString);

  if (ngDepsModel.reflectables != null &&
      ngDepsModel.reflectables.isNotEmpty) return true;

  // We do not register any @Injectables, do we call any dependencies?
  var linkedDepsMap = await _processNgImports(reader, entryPoint, ngDepsModel);
  return linkedDepsMap.isNotEmpty;
}

/// Modifies the [NgDepsModel] represented by `entryPoint` to import its
/// dependencies' associated `.ng_deps.dart` files.
///
/// For example, if entry_point.ng_deps.dart imports dependency.dart, this
/// will check if dependency.ng_deps.json exists. If it does, we add an import
/// to dependency.ng_deps.dart to the entry_point [NgDepsModel] and set
/// `isNgDeps` to `true` to signify that it is a dependency on which we need to
/// call `initReflector`.
Future<NgDepsModel> linkNgDeps(AssetReader reader, AssetId entryPoint) async {
  if (!(await reader.hasInput(entryPoint))) return null;
  var jsonString = await reader.readAsString(entryPoint);
  if (jsonString.isEmpty) return null;
  var ngDepsModel = new NgDepsModel.fromJson(jsonString);

  var linkedDepsMap = await _processNgImports(reader, entryPoint, ngDepsModel);

  if (linkedDepsMap.isEmpty) {
    // We are not calling `initReflector` on any other libraries, but we still
    // return the model to ensure it is written to code.
    // TODO(kegluneq): Continue using the protobuf format after this phase.
    return ngDepsModel;
  }

  for (var i = ngDepsModel.imports.length - 1; i >= 0; --i) {
    if (linkedDepsMap.containsKey(ngDepsModel.imports[i])) {
      var linkedModel = new ImportModel()
        ..isNgDeps = true
        ..uri = toDepsExtension(linkedDepsMap[ngDepsModel.imports[i]])
        ..prefix = 'i$i';
      // TODO(kegluneq): Preserve combinators?
      ngDepsModel.imports.insert(i + 1, linkedModel);
    }
  }
  for (var i = 0, iLen = ngDepsModel.exports.length; i < iLen; ++i) {
    if (linkedDepsMap.containsKey(ngDepsModel.exports[i])) {
      var linkedModel = new ImportModel()
        ..isNgDeps = true
        ..uri = toDepsExtension(linkedDepsMap[ngDepsModel.exports[i]])
        ..prefix = 'i${ngDepsModel.imports.length}';
      // TODO(kegluneq): Preserve combinators?
      ngDepsModel.imports.add(linkedModel);
    }
  }

  return ngDepsModel;
}

bool _isNotDartDirective(dynamic model) {
  return !model.uri.startsWith('dart:');
}

/// Maps each input [ImportModel] or [ExportModel] to its associated
/// `.ng_deps.json` file, if one exists.
Future<Map<dynamic, String>> _processNgImports(
    AssetReader reader, AssetId entryPoint, NgDepsModel model) {
  final nullFuture = new Future.value(null);
  final importsAndExports = new List.from(model.imports)..addAll(model.exports);
  final retVal = <dynamic, String>{};
  return Future
      .wait(
          importsAndExports.where(_isNotDartDirective).map((dynamic directive) {
    var ngDepsUri = toJsonExtension(directive.uri);
    var spanArg = null;
    var ngDepsAsset = uriToAssetId(entryPoint, ngDepsUri, logger, spanArg,
        errorOnAbsolute: false);
    if (ngDepsAsset == entryPoint) return nullFuture;
    return reader.hasInput(ngDepsAsset).then((hasInput) {
      if (hasInput) {
        retVal[directive] = ngDepsUri;
      }
    }, onError: (_) => null);
  }))
      .then((_) => retVal);
}
