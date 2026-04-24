import Foundation

public enum DisplayError: Error, CustomStringConvertible {
    case displayNotFound(runtimeID: String)
    case modeNotAvailable(width: Int, height: Int)
    case configurationFailed(String)

    public var description: String {
        switch self {
        case .displayNotFound(let id):
            return "Display not found: \(id)"
        case .modeNotAvailable(let w, let h):
            return "No matching display mode for \(w)x\(h)"
        case .configurationFailed(let reason):
            return "Display configuration failed: \(reason)"
        }
    }
}

public enum ProfileError: Error, CustomStringConvertible {
    case noDisplaysConnected
    case profileNotFound(signature: String)
    case storageFailure(underlying: Error)

    public var description: String {
        switch self {
        case .noDisplaysConnected:
            return "No displays connected"
        case .profileNotFound(let sig):
            return "No saved profile for signature: \(sig)"
        case .storageFailure(let err):
            return "Profile storage error: \(err)"
        }
    }
}
