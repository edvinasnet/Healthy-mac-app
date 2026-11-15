import Foundation

struct DockerContainer: Identifiable, Hashable {
    let id: String
    let name: String
    let image: String
    let state: String
    let status: String
    let ports: String
    let project: String
    var cpu: String = ""
    var memory: String = ""

    var isRunning: Bool { state == "running" || state == "restarting" || state == "paused" }
}

enum DockerClient {
    enum Action: String {
        case stop, kill, start, restart, rm, pause, unpause
    }

    static let binary: String? = {
        let home = NSHomeDirectory()
        let candidates = [
            "/usr/local/bin/docker", "/opt/homebrew/bin/docker", "\(home)/.orbstack/bin/docker",
            "\(home)/.docker/bin/docker", "\(home)/.rd/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    static func list(all: Bool) -> Result<[DockerContainer], DockerError> {
        guard let bin = binary else { return .failure(DockerError(message: "Docker CLI not found")) }
        var args = ["ps", "--no-trunc", "--format", "{{json .}}"]
        if all { args.insert("-a", at: 1) }
        let out = Shell.run(bin, args, timeout: 10)
        guard out.ok else {
            let msg = out.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(DockerError(message: msg.isEmpty ? "docker ps failed" : msg))
        }

        var containers: [DockerContainer] = []
        for line in out.stdout.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let labels = (json["Labels"] as? String) ?? ""
            let project = labels.split(separator: ",")
                .first { $0.hasPrefix("com.docker.compose.project=") }
                .map { String($0.dropFirst("com.docker.compose.project=".count)) } ?? ""
            containers.append(DockerContainer(
                id: json["ID"] as? String ?? "",
                name: json["Names"] as? String ?? "",
                image: json["Image"] as? String ?? "",
                state: json["State"] as? String ?? "",
                status: json["Status"] as? String ?? "",
                ports: json["Ports"] as? String ?? "",
                project: project))
        }

        if containers.contains(where: \.isRunning) {
            let stats = Shell.run(bin, ["stats", "--no-stream", "--no-trunc", "--format", "{{json .}}"], timeout: 10)
            var byID: [String: (String, String)] = [:]
            for line in stats.stdout.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = json["ID"] as? String
                else { continue }
                byID[id] = (json["CPUPerc"] as? String ?? "", json["MemUsage"] as? String ?? "")
            }
            for i in containers.indices {
                if let s = byID.first(where: { containers[i].id.hasPrefix($0.key) || $0.key.hasPrefix(containers[i].id) })?.value {
                    containers[i].cpu = s.0
                    containers[i].memory = s.1
                }
            }
        }
        return .success(containers)
    }

    static func perform(_ action: Action, ids: [String]) -> Shell.Output {
        guard let bin = binary, !ids.isEmpty else { return Shell.Output(status: -1, stdout: "", stderr: "Docker CLI not found") }
        var args = [action.rawValue]
        if action == .rm { args.append("-f") }
        return Shell.run(bin, args + ids, timeout: 60)
    }
}

struct DockerError: Error {
    let message: String
    var daemonDown: Bool {
        message.localizedCaseInsensitiveContains("cannot connect") || message.localizedCaseInsensitiveContains("is the docker daemon running")
    }
}
