import Vapor
import Fluent

final class Election: Model, Content, @unchecked Sendable {
    static let schema = "elections"

    @ID(key: .id) var id: UUID?
    @Field(key: "nom") var nom: String
    @Children(for: \.$election) var bureaux: [Bureau]
    @Children(for: \.$election) var candidats: [Candidat]
    @Siblings(through: UserElection.self, from: \.$election, to: \.$user) var users: [User]
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() {}

    init(id: UUID? = nil, nom: String) {
        self.id = id
        self.nom = nom
    }
}
