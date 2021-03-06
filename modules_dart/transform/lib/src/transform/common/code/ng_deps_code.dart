library angular2.transform.common.code.ng_deps_code;

import 'package:analyzer/analyzer.dart';
import 'package:angular2/src/transform/common/annotation_matcher.dart';
import 'package:angular2/src/transform/common/model/ng_deps_model.pb.dart';
import 'package:angular2/src/transform/common/model/import_export_model.pb.dart';
import 'package:angular2/src/transform/common/names.dart';
import 'package:barback/barback.dart' show AssetId;
import 'package:path/path.dart' as path;

import 'annotation_code.dart';
import 'import_export_code.dart';
import 'reflection_info_code.dart';
import 'parameter_code.dart';

/// Visitor responsible for parsing source Dart files (that is, not
/// `.ng_deps.dart` files) into [NgDepsModel] objects.
class NgDepsVisitor extends RecursiveAstVisitor<Object> {
  final AssetId processedFile;
  final ImportVisitor _importVisitor = new ImportVisitor();
  final ExportVisitor _exportVisitor = new ExportVisitor();
  final ReflectionInfoVisitor _reflectableVisitor;

  bool _isPart = false;
  NgDepsModel _model = null;

  NgDepsVisitor(AssetId processedFile, AnnotationMatcher annotationMatcher)
      : this.processedFile = processedFile,
        _reflectableVisitor =
            new ReflectionInfoVisitor(processedFile, annotationMatcher);

  bool get isPart => _isPart;
  NgDepsModel get model {
    if (_model == null) {
      _createModel('');
    }
    return _model;
  }

  void _createModel(String libraryUri) {
    _model = new NgDepsModel()..libraryUri = libraryUri;

    // We need to import & export the original file.
    var origDartFile = path.basename(processedFile.path);
    _model.imports.add(new ImportModel()..uri = origDartFile);
    _model.exports.add(new ExportModel()..uri = origDartFile);

    // Used to register reflective information.
    _model.imports.add(new ImportModel()
      ..uri = REFLECTOR_IMPORT
      ..prefix = REFLECTOR_PREFIX);
  }

  @override
  Object visitClassDeclaration(ClassDeclaration node) {
    var reflectableModel = _reflectableVisitor.visitClassDeclaration(node);
    if (reflectableModel != null) {
      model.reflectables.add(reflectableModel);
    }
    return null;
  }

  @override
  Object visitExportDirective(ExportDirective node) {
    var export = _exportVisitor.visitExportDirective(node);
    if (export != null) {
      model.exports.add(export);
    }
    return null;
  }

  @override
  Object visitImportDirective(ImportDirective node) {
    var import = _importVisitor.visitImportDirective(node);
    if (import != null) {
      model.imports.add(import);
    }
    return null;
  }

  @override
  Object visitLibraryDirective(LibraryDirective node) {
    if (node != null) {
      assert(_model == null);
      _createModel('${node.name}');
    }
    return null;
  }

  @override
  Object visitPartDirective(PartDirective node) {
    model.partUris.add(stringLiteralToString(node.uri));
    return null;
  }

  @override
  Object visitPartOfDirective(PartOfDirective node) {
    _isPart = true;
    return null;
  }

  @override
  Object visitFunctionDeclaration(FunctionDeclaration node) {
    var reflectableModel = _reflectableVisitor.visitFunctionDeclaration(node);
    if (reflectableModel != null) {
      model.reflectables.add(reflectableModel);
    }
    return null;
  }
}

/// Defines the format in which an [NgDepsModel] is expressed as Dart code
/// in a `.ng_deps.dart` file.
class NgDepsWriter extends Object
    with
        AnnotationWriterMixin,
        ExportWriterMixin,
        ImportWriterMixin,
        NgDepsWriterMixin,
        ParameterWriterMixin,
        ReflectionWriterMixin {
  final StringBuffer buffer;

  NgDepsWriter([StringBuffer buffer])
      : this.buffer = buffer != null ? buffer : new StringBuffer();
}

abstract class NgDepsWriterMixin
    implements
        AnnotationWriterMixin,
        ExportWriterMixin,
        ImportWriterMixin,
        ParameterWriterMixin,
        ReflectionWriterMixin {
  StringBuffer get buffer;

  void writeNgDepsModel(NgDepsModel model) {
    if (model.libraryUri.isNotEmpty) {
      buffer.writeln('library ${model.libraryUri}${DEPS_EXTENSION};\n');
    }

    // We do not support `partUris`, so skip outputting them.
    model.imports.forEach((importModel) {
      // Ignore deferred imports here so as to not load the deferred libraries
      // code in the current library causing much of the code to not be
      // deferred. Instead `DeferredRewriter` will rewrite the code as to load
      // `ng_deps` in a deferred way.
      if (importModel.isDeferred) return;

      writeImportModel(importModel);
    });
    model.exports.forEach(writeExportModel);

    buffer
      ..writeln('var _visited = false;')
      ..writeln('void ${SETUP_METHOD_NAME}() {')
      ..writeln('if (_visited) return; _visited = true;');

    if (model.reflectables != null && model.reflectables.isNotEmpty) {
      buffer.writeln('$REFLECTOR_PREFIX.$REFLECTOR_VAR_NAME');
      model.reflectables.forEach(writeRegistration);
      buffer.writeln(';');
    }

    buffer.writeln('}');
  }
}
