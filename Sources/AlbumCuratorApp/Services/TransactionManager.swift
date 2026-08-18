import Foundation

public protocol TransactionManagerProtocol {
    var transactions: [MutationTransaction] { get }
    func recordTransaction(albumID: String, albumTitle: String, removedAssetIDs: [String]) -> MutationTransaction
    func undoTransaction(_ transactionID: String, photoKitService: PhotoKitServiceProtocol) async throws -> Bool
}

public class TransactionManager: TransactionManagerProtocol, ObservableObject {
    @Published public private(set) var transactions: [MutationTransaction] = []
    private let persistenceService: LocalPersistenceServiceProtocol
    
    public init(persistenceService: LocalPersistenceServiceProtocol = LocalPersistenceService()) {
        self.persistenceService = persistenceService
        self.transactions = persistenceService.loadTransactions()
    }
    
    public func recordTransaction(albumID: String, albumTitle: String, removedAssetIDs: [String]) -> MutationTransaction {
        let transaction = MutationTransaction(
            albumID: albumID,
            albumTitle: albumTitle,
            removedAssetIDs: removedAssetIDs,
            timestamp: Date()
        )
        transactions.insert(transaction, at: 0)
        persistenceService.saveTransactions(transactions)
        return transaction
    }
    
    public func undoTransaction(_ transactionID: String, photoKitService: PhotoKitServiceProtocol) async throws -> Bool {
        guard let index = transactions.firstIndex(where: { $0.id == transactionID }),
              !transactions[index].isUndone else {
            return false
        }
        
        let tx = transactions[index]
        let success = try await photoKitService.restoreAssetsToAlbum(assetIDs: tx.removedAssetIDs, albumID: tx.albumID)
        
        if success {
            transactions[index].isUndone = true
            persistenceService.saveTransactions(transactions)
        }
        return success
    }
}
