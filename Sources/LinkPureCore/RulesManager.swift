import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum RulesManager {
    /// 加载打进包里的共享规则库。
    public static func loadBundledRuleSet() throws -> RuleSet {
        guard let url = Bundle.module.url(forResource: "shared-rules", withExtension: "json") else {
            throw LinkPureError.resourceMissing("shared-rules.json")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RuleSet.self, from: data)
    }

    public static func loadBundledRules(includeRedirects: Bool = true) throws -> [Rule] {
        let set = try loadBundledRuleSet()
        guard !includeRedirects else { return set.rules }
        return set.rules.filter { $0.followRedirect != true }
    }
}

/// 默认的重定向跟随实现：手动逐跳请求，不自动跟随。
public struct URLSessionRedirectFollower: RedirectFollower {
    public let maxRedirects: Int
    public let timeout: TimeInterval

    public init(maxRedirects: Int = 10, timeout: TimeInterval = 5) {
        self.maxRedirects = maxRedirects
        self.timeout = timeout
    }

    public func follow(_ url: String) async -> String? {
        guard var current = URL(string: url) else { return nil }
        let session = URLSession(
            configuration: .ephemeral,
            delegate: NoRedirectDelegate(),
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }

        for _ in 0..<maxRedirects {
            var request = URLRequest(url: current)
            request.httpMethod = "GET"
            request.timeoutInterval = timeout
            do {
                let (_, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { return current.absoluteString }
                guard (300..<400).contains(http.statusCode),
                      let location = http.value(forHTTPHeaderField: "Location"),
                      let next = URL(string: location, relativeTo: current)
                else { return current.absoluteString }
                current = next.absoluteURL
            } catch {
                // 网络/超时等错误 → 视为规则不匹配
                return nil
            }
        }
        return current.absoluteString
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil) // 不自动跟随，交由上层逐跳处理
    }
}
