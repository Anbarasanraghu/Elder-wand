import 'package:torch_light/torch_light.dart';

class FlashlightService {
  static Future<bool> set(bool on) async {
    try {
      if (on) {
        await TorchLight.enableTorch();
      } else {
        await TorchLight.disableTorch();
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
