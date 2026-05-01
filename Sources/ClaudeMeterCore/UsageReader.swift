import Foundation

public final class UsageReader: @unchecked Sendable {
    public let projectsRoot: URL
    public var dailyBudgetUSD: Double

    private let lock = NSLock()
    private var fileCache: [URL: FileCacheEntry] = [:]

    private struct FileCacheEntry {
        let mtime: TimeInterval
        let size: Int64
        let events: [AssistantEvent]
    }

    public init(projectsRoot: URL = URL(fileURLWithPath: NSString(string: "~/.claude/projects").expandingTildeInPath),
                dailyBudgetUSD: Double = 20.0) {
        self.projectsRoot = projectsRoot
        self.dailyBudgetUSD = dailyBudgetUSD
    }

    public func apiStats(now: Date = Date()) -> ApiStats {
        let events = collectAssistantEvents()
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)

        let todayEvents = events.filter { $0.timestamp >= startOfDay && $0.timestamp <= now }
        let weekEvents = events.filter { $0.timestamp >= weekAgo && $0.timestamp <= now }

        let today = PeriodStats(events: todayEvents)
        let week = PeriodStats(events: weekEvents)

        var byModel: [String: (msgs: Int, cost: Double)] = [:]
        var byProject: [String: (msgs: Int, cost: Double)] = [:]
        for e in weekEvents {
            let m = e.model ?? "unknown"
            let c = Pricing.cost(input: e.inputTokens, output: e.outputTokens, cacheCreate: e.cacheCreate, cacheRead: e.cacheRead, model: e.model)
            var mv = byModel[m, default: (0, 0)]; mv.msgs += 1; mv.cost += c; byModel[m] = mv
            let p = e.project ?? "—"
            var pv = byProject[p, default: (0, 0)]; pv.msgs += 1; pv.cost += c; byProject[p] = pv
        }
        let topModels = byModel
            .map { ModelTotal(model: $0.key, messages: $0.value.msgs, costUSD: $0.value.cost) }
            .sorted { $0.costUSD > $1.costUSD }
        let topProjects = byProject
            .map { ProjectTotal(name: $0.key, messages: $0.value.msgs, costUSD: $0.value.cost) }
            .sorted { $0.costUSD > $1.costUSD }

        return ApiStats(
            today: today, week: week,
            dailyBudgetUSD: dailyBudgetUSD,
            topModels: Array(topModels.prefix(5)),
            topProjects: Array(topProjects.prefix(5))
        )
    }

    struct AssistantEvent {
        let timestamp: Date
        let model: String?
        let project: String?
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreate: Int
        let cacheRead: Int
    }

    private func collectAssistantEvents() -> [AssistantEvent] {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(at: projectsRoot, includingPropertiesForKeys: nil) else {
            return []
        }
        var allEvents: [AssistantEvent] = []
        var seenURLs: Set<URL> = []

        for project in projects {
            let projectName = decodeProjectName(project.lastPathComponent)
            guard let files = try? fm.contentsOfDirectory(
                at: project,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
            ) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                seenURLs.insert(file)
                let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let mtime = attrs?.contentModificationDate?.timeIntervalSince1970 ?? 0
                let size = Int64(attrs?.fileSize ?? 0)

                lock.lock(); let cached = fileCache[file]; lock.unlock()
                if let c = cached, c.mtime == mtime, c.size == size {
                    allEvents.append(contentsOf: c.events)
                    continue
                }
                let parsed = parseFile(file, project: projectName)
                lock.lock(); fileCache[file] = FileCacheEntry(mtime: mtime, size: size, events: parsed); lock.unlock()
                allEvents.append(contentsOf: parsed)
            }
        }
        lock.lock()
        for url in fileCache.keys where !seenURLs.contains(url) { fileCache.removeValue(forKey: url) }
        lock.unlock()
        allEvents.sort { $0.timestamp < $1.timestamp }
        return allEvents
    }

    private func decodeProjectName(_ encoded: String) -> String {
        // Claude encodes cwd as "-Users-jacklutz-Desktop" — last segment is a useful label.
        let parts = encoded.split(separator: "-")
        return parts.last.map(String.init) ?? encoded
    }

    private func parseFile(_ file: URL, project: String?) -> [AssistantEvent] {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter(); isoNoFrac.formatOptions = [.withInternetDateTime]

        var events: [AssistantEvent] = []
        for line in text.split(separator: "\n") {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            guard (obj["type"] as? String) == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let ts = obj["timestamp"] as? String else { continue }
            let date = iso.date(from: ts) ?? isoNoFrac.date(from: ts)
            guard let date else { continue }
            events.append(AssistantEvent(
                timestamp: date,
                model: message["model"] as? String,
                project: project,
                inputTokens: (usage["input_tokens"] as? Int) ?? 0,
                outputTokens: (usage["output_tokens"] as? Int) ?? 0,
                cacheCreate: (usage["cache_creation_input_tokens"] as? Int) ?? 0,
                cacheRead: (usage["cache_read_input_tokens"] as? Int) ?? 0
            ))
        }
        return events
    }
}

extension PeriodStats {
    init(events: [UsageReader.AssistantEvent]) {
        var input = 0, output = 0, cc = 0, cr = 0
        var cost = 0.0
        for e in events {
            input += e.inputTokens
            output += e.outputTokens
            cc += e.cacheCreate
            cr += e.cacheRead
            cost += Pricing.cost(input: e.inputTokens, output: e.outputTokens, cacheCreate: e.cacheCreate, cacheRead: e.cacheRead, model: e.model)
        }
        self.init(messages: events.count, inputTokens: input, outputTokens: output, cacheCreate: cc, cacheRead: cr, costUSD: cost)
    }
}
