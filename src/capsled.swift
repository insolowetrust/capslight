import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem

// capsled — керування зеленим LED на клавіші Caps Lock (MacBook / зовнішні клавіатури).
//
// Два способи, у порядку спроби:
//  1) HID: пишемо напряму в LED-елемент (usage page kHIDPage_LEDs / usage kHIDUsage_LED_CapsLock).
//     Не змінює стан модифікатора Caps Lock — друк лишається у нижньому регістрі.
//  2) IOHIDSystem: IOHIDSetModifierLockState — надійний fallback, але реально вмикає Caps Lock.

enum Backend: String {
    case hid
    case modifier
}

// MARK: - Backend 1: прямий запис у HID LED-елемент

func setLEDViaHID(_ on: Bool) -> Bool {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matching: [String: Any] = [
        kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
        kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
    ]
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

    guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
          let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>
    else { return false }
    defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

    let ledMatching: [String: Any] = [
        kIOHIDElementUsagePageKey: kHIDPage_LEDs,
        kIOHIDElementUsageKey: kHIDUsage_LED_CapsLock,
    ]

    var anySucceeded = false
    for device in devices {
        guard let elements = IOHIDDeviceCopyMatchingElements(
            device, ledMatching as CFDictionary, IOOptionBits(kIOHIDOptionsTypeNone)
        ) as? [IOHIDElement] else { continue }

        for element in elements {
            let value = IOHIDValueCreateWithIntegerValue(
                kCFAllocatorDefault, element, mach_absolute_time(), on ? 1 : 0
            )
            if IOHIDDeviceSetValue(device, element, value) == kIOReturnSuccess {
                anySucceeded = true
            }
        }
    }
    return anySucceeded
}

// MARK: - Backend 2: перемикання самого модифікатора Caps Lock

func setModifierLock(_ on: Bool) -> Bool {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
    guard service != 0 else { return false }
    defer { IOObjectRelease(service) }

    var connect: io_connect_t = 0
    guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS
    else { return false }
    defer { IOServiceClose(connect) }

    return IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), on) == KERN_SUCCESS
}

func modifierLockState() -> Bool? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }

    var connect: io_connect_t = 0
    guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS
    else { return nil }
    defer { IOServiceClose(connect) }

    var state = false
    guard IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &state) == KERN_SUCCESS
    else { return nil }
    return state
}

// MARK: - Диспетчер

var forcedBackend: Backend?

@discardableResult
func setLED(_ on: Bool) -> Backend? {
    switch forcedBackend {
    case .hid:
        return setLEDViaHID(on) ? .hid : nil
    case .modifier:
        return setModifierLock(on) ? .modifier : nil
    case nil:
        if setLEDViaHID(on) { return .hid }
        if setModifierLock(on) { return .modifier }
        return nil
    }
}

// MARK: - Режим блимання

/// Блимає до отримання SIGTERM/SIGINT, після чого гасить LED і виходить.
func blink(interval: Double, dutyCycle: Double) -> Never {
    for sig in [SIGTERM, SIGINT, SIGHUP] {
        signal(sig) { _ in
            setLED(false)
            exit(0)
        }
    }

    let onTime = interval * dutyCycle
    let offTime = interval - onTime
    while true {
        setLED(true)
        Thread.sleep(forTimeInterval: onTime)
        setLED(false)
        Thread.sleep(forTimeInterval: offTime)
    }
}

// MARK: - CLI

func usage() -> Never {
    let text = """
    capsled — керування LED на Caps Lock

    Використання:
      capsled on                     увімкнути
      capsled off                    вимкнути
      capsled blink [інтервал] [duty]  блимати (за замовч. 0.6с, duty 0.5), доки не вб'ють процес
      capsled pulse [разів] [інтервал] коротко блимнути N разів і вийти
      capsled state                  показати стан модифікатора Caps Lock
      capsled probe                  перевірити, який backend працює

    Прапорці:
      --backend hid|modifier         примусовий backend (за замовч. hid з fallback на modifier)
    """
    print(text)
    exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())

if let i = args.firstIndex(of: "--backend") {
    guard i + 1 < args.count, let backend = Backend(rawValue: args[i + 1]) else { usage() }
    forcedBackend = backend
    args.removeSubrange(i...(i + 1))
}

guard let command = args.first else { usage() }
let rest = Array(args.dropFirst())

switch command {
case "on":
    guard let backend = setLED(true) else {
        FileHandle.standardError.write(Data("capsled: не вдалося увімкнути LED\n".utf8))
        exit(1)
    }
    if ProcessInfo.processInfo.environment["CAPSLED_VERBOSE"] != nil { print("backend: \(backend.rawValue)") }

case "off":
    guard let backend = setLED(false) else {
        FileHandle.standardError.write(Data("capsled: не вдалося вимкнути LED\n".utf8))
        exit(1)
    }
    if ProcessInfo.processInfo.environment["CAPSLED_VERBOSE"] != nil { print("backend: \(backend.rawValue)") }

case "blink":
    let interval = rest.first.flatMap(Double.init) ?? 0.6
    let duty = rest.dropFirst().first.flatMap(Double.init) ?? 0.5
    blink(interval: max(0.05, interval), dutyCycle: min(0.95, max(0.05, duty)))

case "pulse":
    let times = rest.first.flatMap(Int.init) ?? 3
    let interval = rest.dropFirst().first.flatMap(Double.init) ?? 0.12
    for _ in 0..<max(1, times) {
        setLED(true)
        Thread.sleep(forTimeInterval: interval)
        setLED(false)
        Thread.sleep(forTimeInterval: interval)
    }

case "state":
    if let state = modifierLockState() {
        print(state ? "on" : "off")
    } else {
        print("unknown")
        exit(1)
    }

case "probe":
    let hidOK = setLEDViaHID(true)
    Thread.sleep(forTimeInterval: 0.4)
    _ = setLEDViaHID(false)
    let modOK = setModifierLock(true)
    Thread.sleep(forTimeInterval: 0.4)
    _ = setModifierLock(false)
    print("hid:      \(hidOK ? "працює" : "недоступний")")
    print("modifier: \(modOK ? "працює" : "недоступний")")

default:
    usage()
}
