import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem

// capsled — drives the green LED on the Caps Lock key (MacBook and external keyboards).
//
// Two backends, tried in this order:
//  1) HID: write straight to the LED element (usage page kHIDPage_LEDs / usage
//     kHIDUsage_LED_CapsLock). Leaves the Caps Lock modifier alone, so typing stays
//     lowercase while the light is on.
//  2) IOHIDSystem: IOHIDSetModifierLockState — a reliable fallback, but it genuinely
//     toggles Caps Lock, so text would jump to CAPS while blinking.

enum Backend: String {
    case hid
    case modifier
}

// MARK: - Backend 1: direct write to the HID LED element

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

// MARK: - Backend 2: toggle the Caps Lock modifier itself

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

// MARK: - Dispatch

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

// MARK: - Blink mode

/// Blinks until SIGTERM/SIGINT arrives, then turns the LED off and exits.
///
/// `maxSeconds` is a dead-man's switch: a blinker that loses its parent — a crashed
/// session, a `kill -9`, anything that skips the cleanup path — would otherwise blink
/// forever with nothing left to stop it. Whoever is still driving the LED restarts it,
/// so the cap costs nothing while a session is genuinely alive. Zero disables it.
func blink(interval: Double, dutyCycle: Double, maxSeconds: Double) -> Never {
    for sig in [SIGTERM, SIGINT, SIGHUP] {
        signal(sig) { _ in
            setLED(false)
            exit(0)
        }
    }

    let onTime = interval * dutyCycle
    let offTime = interval - onTime
    let deadline = maxSeconds > 0 ? Date().addingTimeInterval(maxSeconds) : Date.distantFuture

    while true {
        if Date() >= deadline {
            setLED(false)
            exit(0)
        }
        setLED(true)
        Thread.sleep(forTimeInterval: onTime)
        setLED(false)
        Thread.sleep(forTimeInterval: offTime)
    }
}

// MARK: - CLI

func usage() -> Never {
    let text = """
    capsled — control the Caps Lock LED

    Usage:
      capsled on                      turn the LED on
      capsled off                     turn the LED off
      capsled blink [interval] [duty] [max-seconds]
                                      blink (defaults: 0.6s, duty 0.5) until killed;
                                      max-seconds gives up after that long (0 = never)
      capsled pulse [times] [interval] flash N times, then exit
      capsled state                   print the Caps Lock modifier state
      capsled probe                   report which backends work on this machine

    Flags:
      --backend hid|modifier          force a backend (default: hid, falling back to modifier)
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
        FileHandle.standardError.write(Data("capsled: could not turn the LED on\n".utf8))
        exit(1)
    }
    if ProcessInfo.processInfo.environment["CAPSLED_VERBOSE"] != nil { print("backend: \(backend.rawValue)") }

case "off":
    guard let backend = setLED(false) else {
        FileHandle.standardError.write(Data("capsled: could not turn the LED off\n".utf8))
        exit(1)
    }
    if ProcessInfo.processInfo.environment["CAPSLED_VERBOSE"] != nil { print("backend: \(backend.rawValue)") }

case "blink":
    let interval = rest.first.flatMap(Double.init) ?? 0.6
    let duty = rest.dropFirst().first.flatMap(Double.init) ?? 0.5
    let maxSeconds = rest.dropFirst(2).first.flatMap(Double.init) ?? 0
    blink(
        interval: max(0.05, interval),
        dutyCycle: min(0.95, max(0.05, duty)),
        maxSeconds: max(0, maxSeconds)
    )

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
    print("hid:      \(hidOK ? "works" : "unavailable")")
    print("modifier: \(modOK ? "works" : "unavailable")")

default:
    usage()
}
