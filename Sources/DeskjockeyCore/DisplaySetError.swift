import Foundation

public enum DisplaySetError: Error, CustomStringConvertible {
    case displayNotFound(runtimeID: String)
    case modeNotAvailable(width: Int, height: Int)
    case operationFailed(String)

    public var description: String {
        switch self {
        case .displayNotFound(let id):
            return "Display not found: \(id)"
        case .modeNotAvailable(let w, let h):
            return "No matching display mode for \(w)x\(h)"
        case .operationFailed(let reason):
            return "Display set operation failed: \(reason)"
        }
    }
}

