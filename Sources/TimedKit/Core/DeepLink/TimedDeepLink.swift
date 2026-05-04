import Foundation

enum TimedDeepLink: Equatable {
    case authCallback(URL)
    case capture
    case invite(code: String)
    case unknown

    static func parse(_ url: URL) -> TimedDeepLink {
        guard url.scheme == "timed" else { return .unknown }
        switch (url.host, url.path) {
        case ("auth", "/callback"):
            return .authCallback(url)
        case ("capture", _), (.some(""), "/capture"):
            return .capture
        case ("invite", let path):
            let code = String(path.drop(while: { $0 == "/" }))
            return code.isEmpty ? .unknown : .invite(code: code.lowercased())
        default:
            return .unknown
        }
    }
}
