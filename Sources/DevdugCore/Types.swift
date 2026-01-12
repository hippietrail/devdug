import Foundation

// MARK: - Public Types

public struct Config {
    public let dryRun: Bool
    public let listOnly: Bool
    public let verbose: Bool
    public let confirmationCount: Int

    public init(dryRun: Bool = true, listOnly: Bool = false, verbose: Bool = false, confirmationCount: Int = 0) {
        self.dryRun = dryRun
        self.listOnly = listOnly
        self.verbose = verbose
        self.confirmationCount = confirmationCount
    }
}

public struct ProjectInfo: Hashable {
    public let path: String
    public let name: String
    public let type: String
    public let size: UInt64
    public let lastModified: Date

    public init(path: String, name: String, type: String, size: UInt64, lastModified: Date) {
        self.path = path
        self.name = name
        self.type = type
        self.size = size
        self.lastModified = lastModified
    }
}

public struct CleanupAction {
    public let type: ActionType
    public let description: String
    public let explanation: String?
    public let estimatedSize: UInt64?

    public enum ActionType {
        case safeCommand
        case tentativeCommand
        case pathDelete
    }

    public init(type: ActionType, description: String, explanation: String? = nil, estimatedSize: UInt64? = nil) {
        self.type = type
        self.description = description
        self.explanation = explanation
        self.estimatedSize = estimatedSize
    }
}

// MARK: - Project Emoji Map

public let projectEmojis: [String: String] = [
    "cargo": "🦀",
    "npm": "📦",
    "python-pip": "🐍",
    "python-poetry": "🐍",
    "python-setuptools": "🐍",
    "gradle": "☕️",
    "maven": "☕️",
    "swift-spm": "🍎",
    "xcode": "🍎",
    "cmake": "📐",
    "make": "🔨",
    "go": "🐹",
    "intellij-idea": "💡",
    "android-studio": "🤖",
    "rustrover": "🦀",
    "clion": "⚙️",
    "goland": "🐹",
    "pycharm": "🐍",
    "webstorm": "⚡️",
    "appcode": "🍎",
    "visual-studio": "🔷",
    "eclipse-workspace": "🌀",
    "zig": "⚡️",
    "git-repo": "🔗",
    "generic": "📁",
]

public func projectEmoji(_ type: String) -> String {
    return projectEmojis[type] ?? "📦"
}
