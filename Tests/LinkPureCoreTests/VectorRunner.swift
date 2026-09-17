import Foundation
import LinkPureCore

// MARK: - 向量格式（见 LinkPure 仓库 conformance/README.md）

struct VectorFile: Decodable {
    let name: String?
    let cases: [VectorCase]
}

struct VectorCase: Decodable {
    let name: String?
    let rules: [Rule]?
    let ruleRef: String?
    let input: String
    let expect: Expect?

    struct Expect: Decodable {
        let status: String
        let output: String
    }
}

enum VectorRunner {
    struct Outcome {
        var total = 0
        var failed = 0
        var failures: [String] = []
        var perFile: [(String, Int, Int)] = [] // (file, cases, failed)
    }

    /// 跑完 `Tests/LinkPureCoreTests/Vectors/` 下的全部向量。
    static func run(shared: RuleSet, stripRedirects: Bool = true) async throws -> Outcome {
        guard let dir = Bundle.module.url(forResource: "Vectors", withExtension: nil) else {
            throw LinkPureError.resourceMissing("Vectors")
        }
        let files = try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var outcome = Outcome()
        for file in files {
            let doc = try JSONDecoder().decode(VectorFile.self, from: Data(contentsOf: file))
            var fileFailed = 0

            for c in doc.cases {
                outcome.total += 1
                var rules: [Rule]
                if let inline = c.rules {
                    rules = inline
                } else if let ref = c.ruleRef {
                    rules = shared.rules.filter { $0.id == ref }
                } else {
                    rules = shared.rules
                }
                if stripRedirects {
                    rules = rules.filter { $0.followRedirect != true }
                }

                let result = await UrlCleaner(rules: rules).check(c.input)
                guard let expect = c.expect else { continue }

                if result.status.rawValue != expect.status || result.url != expect.output {
                    outcome.failed += 1
                    fileFailed += 1
                    outcome.failures.append(
                        """
                        \(file.lastPathComponent) :: \(c.name ?? "(unnamed)")
                                input : \(c.input)
                                expect: \(expect.status)  \(expect.output)
                                actual: \(result.status.rawValue)  \(result.url)
                        """
                    )
                }
            }
            outcome.perFile.append((file.lastPathComponent, doc.cases.count, fileFailed))
        }
        return outcome
    }
}
