// The trackpad layer: MultitouchSupport (a private macOS framework), resolved at run time.
//
// Adapted from nospeaker.swift (github.com/os6/nospeaker, MIT, © 2026 Cody Collier). Undocumented API: it may
// change with any macOS update. The motor is never driven past its normal maximum.

import Foundation

/// The framework's functions. Function pointers are plain values, set once and never changed.
struct MultitouchAPI: @unchecked Sendable {
    typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    typealias GetID = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
    typealias IsBuiltIn = @convention(c) (UnsafeMutableRawPointer) -> Bool
    typealias ActuatorCreate = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    typealias ActuatorOpen = @convention(c) (CFTypeRef) -> Int32
    typealias ActuatorClose = @convention(c) (CFTypeRef) -> Int32
    typealias ActuationCreate = @convention(c) (CFDictionary, Int32) -> UnsafeMutableRawPointer?
    typealias ActuationPlay = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UInt32, Float, Float) -> Int32
    typealias FrameCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    typealias RegisterCallback = @convention(c) (UnsafeMutableRawPointer, FrameCallback) -> Void
    typealias DeviceStart = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    typealias DeviceStop = @convention(c) (UnsafeMutableRawPointer) -> Void

    let createList: CreateList?
    let getID: GetID?
    let isBuiltIn: IsBuiltIn?
    let actuatorCreate: ActuatorCreate?
    let actuatorOpen: ActuatorOpen?
    let actuatorClose: ActuatorClose?
    let actuationCreate: ActuationCreate?
    let actuationPlay: ActuationPlay?
    let registerCallback: RegisterCallback?
    let unregisterCallback: RegisterCallback?
    let deviceStart: DeviceStart?
    let deviceStop: DeviceStop?

    static let shared = MultitouchAPI()

    private init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
        func sym<T>(_ name: String, _: T.Type) -> T? {
            guard let handle, let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        createList = sym("MTDeviceCreateList", CreateList.self)
        getID = sym("MTDeviceGetDeviceID", GetID.self)
        isBuiltIn = sym("MTDeviceIsBuiltIn", IsBuiltIn.self)
        actuatorCreate = sym("MTActuatorCreateFromDeviceID", ActuatorCreate.self)
        actuatorOpen = sym("MTActuatorOpen", ActuatorOpen.self)
        actuatorClose = sym("MTActuatorClose", ActuatorClose.self)
        actuationCreate = sym("MTActuationCreateFromDictionary", ActuationCreate.self)
        actuationPlay = sym("MTActuationActuate", ActuationPlay.self)
        registerCallback = sym("MTRegisterContactFrameCallback", RegisterCallback.self)
        unregisterCallback = sym("MTUnregisterContactFrameCallback", RegisterCallback.self)
        deviceStart = sym("MTDeviceStart", DeviceStart.self)
        deviceStop = sym("MTDeviceStop", DeviceStop.self)
    }

    /// True when this macOS has every function needed to drive a motor.
    var canDriveMotor: Bool {
        createList != nil && getID != nil && actuatorCreate != nil && actuatorOpen != nil && actuatorClose != nil
            && actuationCreate != nil && actuationPlay != nil
    }
}

/// A Force Touch trackpad: one with a haptic motor.
public struct Trackpad: Identifiable, Hashable, Sendable {
    public let id: UInt64
    public let isBuiltIn: Bool
    public var name: String { isBuiltIn ? "MacBook trackpad" : "Magic Trackpad" }
    public init(id: UInt64, isBuiltIn: Bool) { self.id = id; self.isBuiltIn = isBuiltIn }
}

/// The devices MultitouchSupport reports, kept alive together: touch tracking needs the device pointers, and
/// they belong to the list. Immutable after init.
final class DeviceList: @unchecked Sendable {
    private let array: CFArray
    let devices: [(pointer: UnsafeMutableRawPointer, id: UInt64, isBuiltIn: Bool)]

    init?() {
        let api = MultitouchAPI.shared
        guard let createList = api.createList, let getID = api.getID,
              let list = createList()?.takeRetainedValue() else { return nil }
        array = list
        var found: [(UnsafeMutableRawPointer, UInt64, Bool)] = []
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            var id: UInt64 = 0
            if getID(device, &id) == 0 { found.append((device, id, api.isBuiltIn?(device) ?? false)) }
        }
        devices = found
    }

    func pointers(for ids: Set<UInt64>) -> [UnsafeMutableRawPointer] {
        devices.filter { ids.contains($0.id) }.map(\.pointer)
    }
}

/// Every connected trackpad whose motor opens, built-in first. Silent: it opens and closes each motor, and plays
/// nothing.
public func findTrackpads() -> [Trackpad] {
    let api = MultitouchAPI.shared
    guard api.canDriveMotor, let list = DeviceList() else { return [] }
    var pads: [Trackpad] = []
    for device in list.devices {
        guard let ref = api.actuatorCreate!(device.id)?.takeRetainedValue() else { continue }
        if api.actuatorOpen!(ref) == 0 {
            _ = api.actuatorClose!(ref)
            pads.append(Trackpad(id: device.id, isBuiltIn: device.isBuiltIn))
        }
    }
    return pads.sorted { $0.isBuiltIn && !$1.isBuiltIn }
}
