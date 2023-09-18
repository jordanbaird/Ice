//
//  ObjectAssociation.swift
//  Ice
//

import ObjectiveC

// MARK: - AssociationPolicy

enum AssociationPolicy {
    case assign
    case copy
    case copyNonatomic
    case retain
    case retainNonatomic

    fileprivate var objcValue: objc_AssociationPolicy {
        switch self {
        case .assign:
            return .OBJC_ASSOCIATION_ASSIGN
        case .copy:
            return .OBJC_ASSOCIATION_COPY
        case .copyNonatomic:
            return .OBJC_ASSOCIATION_COPY_NONATOMIC
        case .retain:
            return .OBJC_ASSOCIATION_RETAIN
        case .retainNonatomic:
            return .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        }
    }
}

// MARK: - ObjectAssociation

final class ObjectAssociation<Value> {
    private let policy: AssociationPolicy

    private var key: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
    }

    init(policy: AssociationPolicy = .retainNonatomic) {
        self.policy = policy
    }

    subscript(object: AnyObject) -> Value? {
        get { objc_getAssociatedObject(object, key) as? Value }
        set { objc_setAssociatedObject(object, key, newValue, policy.objcValue) }
    }
}
