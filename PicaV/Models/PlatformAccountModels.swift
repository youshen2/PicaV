import Foundation

struct PlatformAccountSession: Codable, Equatable {
    let platformID: AnimePlatformID
    let account: String
    let displayName: String
    let userID: String?
    let loggedInAt: Date
}

enum PlatformAccountAction {
    case login
    case register

    var title: String {
        switch self {
        case .login: return "登录"
        case .register: return "注册"
        }
    }
}
