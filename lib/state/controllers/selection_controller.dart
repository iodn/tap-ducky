import 'package:flutter_riverpod/flutter_riverpod.dart';

class SelectedPayloadIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? payloadId) => state = payloadId;
  void clear() => state = null;
}

final selectedPayloadIdProvider =
    NotifierProvider<SelectedPayloadIdNotifier, String?>(
  SelectedPayloadIdNotifier.new,
);
