import Foundation

public protocol LocalPersistenceServiceProtocol {
    func loadCachedAnalyses() -> [String: PhotoAnalysis]
    func saveCachedAnalyses(_ analyses: [String: PhotoAnalysis])
    func loadTransactions() -> [MutationTransaction]
    func saveTransactions(_ transactions: [MutationTransaction])
    func loadSimilarityMode() -> SimilarityMode
    func saveSimilarityMode(_ mode: SimilarityMode)
    func clearCache()
}

public class LocalPersistenceService: LocalPersistenceServiceProtocol {
    private let fileManager = FileManager.default
    private let baseURL: URL
    
    private var analysesURL: URL { baseURL.appendingPathComponent("analyses_cache.json") }
    private var transactionsURL: URL { baseURL.appendingPathComponent("transactions_log.json") }
    private var settingsURL: URL { baseURL.appendingPathComponent("user_settings.json") }
    
    public init(storageDirectory: URL? = nil) {
        if let dir = storageDirectory {
            self.baseURL = dir
        } else {
            let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
            let documents = paths.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.baseURL = documents.appendingPathComponent("AlbumCuratorData", isDirectory: true)
        }
        
        try? fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }
    
    public func loadCachedAnalyses() -> [String: PhotoAnalysis] {
        guard let data = try? Data(contentsOf: analysesURL),
              let decoded = try? JSONDecoder().decode([String: PhotoAnalysis].self, from: data) else {
            return [:]
        }
        return decoded
    }
    
    public func saveCachedAnalyses(_ analyses: [String: PhotoAnalysis]) {
        guard let data = try? JSONEncoder().encode(analyses) else { return }
        try? data.write(to: analysesURL, options: .atomic)
    }
    
    public func loadTransactions() -> [MutationTransaction] {
        guard let data = try? Data(contentsOf: transactionsURL),
              let decoded = try? JSONDecoder().decode([MutationTransaction].self, from: data) else {
            return []
        }
        return decoded
    }
    
    public func saveTransactions(_ transactions: [MutationTransaction]) {
        guard let data = try? JSONEncoder().encode(transactions) else { return }
        try? data.write(to: transactionsURL, options: .atomic)
    }
    
    public func loadSimilarityMode() -> SimilarityMode {
        guard let data = try? Data(contentsOf: settingsURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let modeRaw = dict["similarityMode"],
              let mode = SimilarityMode(rawValue: modeRaw) else {
            return .balanced
        }
        return mode
    }
    
    public func saveSimilarityMode(_ mode: SimilarityMode) {
        let dict = ["similarityMode": mode.rawValue]
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }
    
    public func clearCache() {
        try? fileManager.removeItem(at: analysesURL)
    }
}
