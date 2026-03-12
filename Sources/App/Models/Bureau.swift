import Vapor
import Fluent

final class Bureau: Model, Content, @unchecked Sendable {
    static let schema = "bureaux"

    @ID(key: .id) var id: UUID?
    @Parent(key: "election_id") var election: Election
    @Field(key: "numero") var numero: Int
    @Field(key: "nom") var nom: String
    @Field(key: "adresse") var adresse: String
    @Field(key: "inscrits") var inscrits: Int
    @Field(key: "votants") var votants: Int
    @Field(key: "exprimes") var exprimes: Int
    @Field(key: "bulletins_depouilles") var bulletinsDepouilles: Int
    @Field(key: "bulletins_nuls") var bulletinsNuls: Int
    @Field(key: "bulletins_blancs") var bulletinsBlancs: Int
    @Field(key: "depouillement_termine") var depouillementTermine: Bool
    @Children(for: \.$bureau) var participations: [Participation]
    @Children(for: \.$bureau) var resultats: [Resultat]
    @Siblings(through: UserBureau.self, from: \.$bureau, to: \.$user) var scrutateurs: [User]
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() {}

    init(id: UUID? = nil, electionId: UUID, numero: Int, nom: String, adresse: String, inscrits: Int = 0) {
        self.id = id
        self.$election.id = electionId
        self.numero = numero
        self.nom = nom
        self.adresse = adresse
        self.inscrits = inscrits
        self.votants = 0
        self.exprimes = 0
        self.bulletinsDepouilles = 0
        self.bulletinsNuls = 0
        self.bulletinsBlancs = 0
        self.depouillementTermine = false
    }
}
