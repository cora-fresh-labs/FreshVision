import Foundation
import UIKit

enum DeviceIdentity {
  static var installationID: UUID {
    let key = "freshvision.installation-id"
    if let raw = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: raw) {
      return id
    }
    let id = UUID()
    UserDefaults.standard.set(id.uuidString, forKey: key)
    return id
  }
  @MainActor static var model: String {
    var info = utsname()
    uname(&info)
    let value = Mirror(reflecting: info.machine).children.reduce(into: "") { result, item in
      guard let byte = item.value as? Int8, byte != 0 else { return }
      result.append(Character(UnicodeScalar(UInt8(byte))))
    }
    return value.isEmpty ? UIDevice.current.model : value
  }
}
