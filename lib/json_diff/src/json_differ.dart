// Copyright 2014 Google Inc. All Rights Reserved.
// Licensed under the Apache License, Version 2.0, found in the LICENSE file.

part of '../json_diff.dart';

/// A configurable class that can produce a diff of two JSON Strings.
class JsonDiffer {
  /// Constructs a new JsonDiffer using [leftJson] and [rightJson], two
  /// JSON objects.
  JsonDiffer(this.leftJson, this.rightJson);

  final Map<String, dynamic> leftJson;
  final Map<String, dynamic> rightJson;
  final List<String> atomics = <String>[];
  final List<String> metadataToKeep = <String>[];
  final List<String> ignored = <String>[];

  /// Throws an exception if the values of each of the [topLevelFields] are not
  /// equal.
  ///
  /// This is useful as a sanity check before diffing two JSON objects that are
  /// expected to be partially identical. For example, if you are comparing
  /// two historical versions of the same object, then each one should have the
  /// same "name" field:
  ///
  ///     // Instantiate differ.
  ///     differ.ensureIdentical(['name']);
  ///     // Perform diff.
  void ensureIdentical(List<String> topLevelFields) {
    for (final field in topLevelFields) {
      if (!leftJson.containsKey(field)) {
        throw UncomparableJsonException('left does not contain field "$field"');
      }
      if (!rightJson.containsKey(field)) {
        throw UncomparableJsonException(
            'right does not contain field "$field"');
      }
      if (leftJson[field] != rightJson[field]) {
        throw UncomparableJsonException(
          'Unequal values for field "$field":'
          ' ${leftJson[field]} vs ${rightJson[field]}',
        );
      }
    }
  }

  /// Compare the two JSON Strings, producing a [DiffNode].
  ///
  /// The differ will walk the entire object graph of each JSON object,
  /// tracking all additions, deletions, and changes. Please see the
  /// documentation for [DiffNode] to understand how to access the differences
  /// found between the two JSON Strings.
  DiffNode diff() => _diffObjects(leftJson, rightJson)..prune();

  DiffNode _diffObjects(Map<String, dynamic> left, Map<String, dynamic> right) {
    final node = DiffNode();
    _keepMetadata(node, left, right);
    left.forEach((key, dynamic leftValue) {
      if (ignored.contains(key)) {
        return;
      }

      if (!right.containsKey(key)) {
        // key is missing from right.
        node.removed[key] = leftValue as Object;
        return;
      }

      final dynamic rightValue = right[key];
      if (atomics.contains(key) &&
          leftValue.toString() != rightValue.toString()) {
        // Treat leftValue and rightValue as atomic objects, even if they are
        // deep maps or some such thing.
        node.changed[key] = [leftValue as Object, rightValue as Object];
      } else if (leftValue is List && rightValue is List) {
        node[key] = _diffLists(
          leftValue as List<Object>,
          rightValue as List<Object>,
          key,
        );
      } else if (leftValue is Map && rightValue is Map) {
        node[key] = _diffObjects(
          leftValue as Map<String, dynamic>,
          rightValue as Map<String, dynamic>,
        );
      } else if (leftValue != rightValue) {
        // value is different between [left] and [right]
        node.changed[key] = [leftValue as Object, rightValue as Object];
      }
    });

    right.forEach((key, dynamic value) {
      if (ignored.contains(key)) {
        return;
      }

      if (!left.containsKey(key)) {
        // key is missing from left.
        node.added[key] = value as Object;
      }
    });

    return node;
  }

  bool _deepEquals(List<Object> e1, List<Object> e2) =>
      const DeepCollectionEquality().equals(e1, e2);

  DiffNode _diffLists(
    List<Object> left,
    List<Object> right,
    String? parentKey,
  ) {
    final node = DiffNode();
    var leftHand = 0;
    var leftFoot = 0;
    var rightHand = 0;
    var rightFoot = 0;
    while (leftHand < left.length && rightHand < right.length) {
      if (!_deepEquals(
        left[leftHand] as List<Object>,
        right[rightHand] as List<Object>,
      )) {
        var foundMissing = false;
        // Walk hands up one at a time. Feet keep track of where we were.
        while (true) {
          rightHand++;
          if (rightHand < right.length &&
              _deepEquals(
                left[leftFoot] as List<Object>,
                right[rightHand] as List<Object>,
              )) {
            // Found it: the right elements at [rightFoot, rightHand-1] were
            // added in right.
            for (var i = rightFoot; i < rightHand; i++) {
              node.added[i.toString()] = right[i];
            }
            rightFoot = rightHand;
            leftHand = leftFoot;
            foundMissing = true;
            break;
          }

          leftHand++;
          if (leftHand < left.length &&
              _deepEquals(
                left[leftHand] as List<Object>,
                right[rightFoot] as List<Object>,
              )) {
            // Found it: The left elements at [leftFoot, leftHand-1] were
            // removed from left.
            for (var i = leftFoot; i < leftHand; i++) {
              node.removed[i.toString()] = left[i];
            }
            leftFoot = leftHand;
            rightHand = rightFoot;
            foundMissing = true;
            break;
          }

          if (leftHand >= left.length && rightHand >= right.length) {
            break;
          }
        }

        if (!foundMissing) {
          // Never found left[leftFoot] in right, nor right[rightFoot] in left.
          // This must just be a changed value.
          // NOTE: This notation is wrong for a case such as:
          //     [1,2,3,4,5,6] => [1,4,5,7]
          //     changed.first = [[5, 6], [3,7]
          if (parentKey != null &&
              atomics.contains('$parentKey[]') &&
              left[leftFoot].toString() != right[rightFoot].toString()) {
            // Treat leftValue and rightValue as atomic objects, even if they
            // are deep maps or some such thing.
            node.changed[leftFoot.toString()] = [
              left[leftFoot],
              right[rightFoot]
            ];
          } else if (left[leftFoot] is Map && right[rightFoot] is Map) {
            node[leftFoot.toString()] = _diffObjects(
              left[leftFoot] as Map<String, dynamic>,
              right[rightFoot] as Map<String, dynamic>,
            );
          } else if (left[leftFoot] is List && right[rightFoot] is List) {
            node[leftFoot.toString()] = _diffLists(
              left[leftFoot] as List<Object>,
              right[rightFoot] as List<Object>,
              null,
            );
          } else {
            node.changed[leftFoot.toString()] = [
              left[leftFoot],
              right[rightFoot]
            ];
          }
        }
      }
      leftHand++;
      rightHand++;
      leftFoot++;
      rightFoot++;
    }

    // Any new elements at the end of right.
    for (var i = rightHand; i < right.length; i++) {
      node.added[i.toString()] = right[i];
    }

    // Any removed elements at the end of left.
    for (var i = leftHand; i < left.length; i++) {
      node.removed[i.toString()] = left[i];
    }

    return node;
  }

  void _keepMetadata(
    DiffNode node,
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    for (final key in metadataToKeep) {
      if (left.containsKey(key) &&
          right.containsKey(key) &&
          left[key] == right[key]) {
        node.metadata[key] = left[key] as String;
      }
    }
  }
}

/// An exception that is thrown when two JSON Strings did not pass a basic
/// sanity test.
class UncomparableJsonException implements Exception {
  const UncomparableJsonException(this.msg);
  final String msg;
  @override
  String toString() => 'UncomparableJsonException: $msg';
}
