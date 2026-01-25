import Foundation

// MARK: - Debug Timing Helper
/// Simple timer for measuring startup performance. Emits ms-level metrics at each phase.
/// Used by both devdug-gui and devdug CLI to understand where time is spent.
/// Logs format: [total: XXXms delta: XXms] <label>
public class DebugTimer {
    private let startTime = Date()
    private var lastTime = Date()
    private let prefix: String
    
    public init(_ prefix: String = "⏱️ ") {
        self.prefix = prefix
    }
    
    /// Log elapsed time since initialization and since last call
    public func elapsed(_ label: String) {
        let now = Date()
        let totalMs = Int(now.timeIntervalSince(startTime) * 1000)
        let deltaMs = Int(now.timeIntervalSince(lastTime) * 1000)
        print("\(prefix)[total: \(totalMs)ms delta: \(deltaMs)ms] \(label)")
        lastTime = now
    }
}

// MARK: - Public Types

public struct Config {
    public let dryRun: Bool
    public let listOnly: Bool
    public let verbose: Bool
    public let confirmationCount: Int
    public let useBlocks: Bool

    public init(dryRun: Bool = true, listOnly: Bool = false, verbose: Bool = false, confirmationCount: Int = 0, useBlocks: Bool = false) {
        self.dryRun = dryRun
        self.listOnly = listOnly
        self.verbose = verbose
        self.confirmationCount = confirmationCount
        self.useBlocks = useBlocks
    }
}

public enum GitHost: Hashable, Equatable, Sendable {
    case github
    case gitlab
    case codeberg
    case gitea
    case custom(hostname: String)
    case unknown
    
    public var displayName: String {
        switch self {
        case .github: return "GitHub"
        case .gitlab: return "GitLab"
        case .codeberg: return "Codeberg"
        case .gitea: return "Gitea"
        case .custom(let hostname): return hostname
        case .unknown: return "Git"
        }
    }
    
    public var icon: String {
        switch self {
        case .github: return "🐙"
        case .gitlab: return "🦊"
        case .codeberg: return "🦆"
        case .gitea: return "🍵"
        case .custom: return "📦"
        case .unknown: return "🔗"
        }
    }
    
    /// Convert to string for Codable serialization
    public func toString() -> String {
        switch self {
        case .github: return "github"
        case .gitlab: return "gitlab"
        case .codeberg: return "codeberg"
        case .gitea: return "gitea"
        case .custom(let hostname): return "custom:\(hostname)"
        case .unknown: return "unknown"
        }
    }
    
    /// Parse from string (used by Codable deserialization)
    public static func fromString(_ str: String) -> GitHost {
        switch str {
        case "github": return .github
        case "gitlab": return .gitlab
        case "codeberg": return .codeberg
        case "gitea": return .gitea
        case "unknown": return .unknown
        default:
            // Handle custom:hostname format
            if str.starts(with: "custom:") {
                let hostname = String(str.dropFirst("custom:".count))
                return .custom(hostname: hostname)
            }
            return .unknown
        }
    }
}

public struct ProjectInfo: Hashable, Sendable, Codable {
    public let path: String
    public let name: String
    public let type: String
    public let size: UInt64
    public let lastModified: Date
    public let isGitRepo: Bool
    public let gitHost: GitHost
    public let gitOriginURL: String?

    public init(
        path: String,
        name: String,
        type: String,
        size: UInt64,
        lastModified: Date,
        isGitRepo: Bool = false,
        gitHost: GitHost = .unknown,
        gitOriginURL: String? = nil
    ) {
        self.path = path
        self.name = name
        self.type = type
        self.size = size
        self.lastModified = lastModified
        self.isGitRepo = isGitRepo
        self.gitHost = gitHost
        self.gitOriginURL = gitOriginURL
    }
    
    // MARK: - Codable Implementation
    /// Custom Codable to handle GitHost enum encoding/decoding
    enum CodingKeys: String, CodingKey {
        case path, name, type, size, lastModified
        case isGitRepo, gitHost, gitOriginURL
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        size = try container.decode(UInt64.self, forKey: .size)
        lastModified = try container.decode(Date.self, forKey: .lastModified)
        isGitRepo = try container.decode(Bool.self, forKey: .isGitRepo)
        gitOriginURL = try container.decodeIfPresent(String.self, forKey: .gitOriginURL)
        
        // Decode gitHost as a string and convert back to enum
        let gitHostStr = try container.decode(String.self, forKey: .gitHost)
        gitHost = GitHost.fromString(gitHostStr)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(size, forKey: .size)
        try container.encode(lastModified, forKey: .lastModified)
        try container.encode(isGitRepo, forKey: .isGitRepo)
        try container.encode(gitHost.toString(), forKey: .gitHost)
        try container.encodeIfPresent(gitOriginURL, forKey: .gitOriginURL)
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
    "tauri": "🚀",
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
    // Extract primary type (first one if comma-separated)
    let primaryType = type.split(separator: ",").first.map(String.init) ?? type
    let trimmed = primaryType.trimmingCharacters(in: .whitespaces)
    return projectEmojis[trimmed] ?? "📦"
}
