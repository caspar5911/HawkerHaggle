import 'dart:async';

import 'package:hawker_haggle/core/game.dart';

/// Every test file runs through this. Most tests are about other things and buy far more in a day than Mum's pocket
/// money: the wallet is off for them. test/wallet_test.dart switches it back on (and checks the app has it on).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Game.testWallet = false;
  await testMain();
}
