import Foundation

struct GitBranchService {
    func isGitRepository(at repositoryURL: URL) -> Bool {
        do {
            let output = try runGitCommand(["-C", repositoryURL.path, "rev-parse", "--is-inside-work-tree"], at: repositoryURL)
            return output == "true"
        } catch {
            return false
        }
    }

    func currentBranchDisplay(at repositoryURL: URL) throws -> String {
        let branchName = try runGitCommand(["-C", repositoryURL.path, "rev-parse", "--abbrev-ref", "HEAD"], at: repositoryURL)

        if branchName == "HEAD" {
            let hash = try runGitCommand(["-C", repositoryURL.path, "rev-parse", "--short", "HEAD"], at: repositoryURL)
            return "DETACHED(\(hash))"
        }

        return branchName
    }

    private func runGitCommand(_ arguments: [String], at _: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw NSError(
                domain: "GitBranchServiceError",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
