import Vapor
import Fluent

// Taux de participation à différentes heures
final class Participation: Model, Content, @unchecked Sendable {
    static let schema = "participations"

    @ID(key: .id) var id: UUID?
    @Parent(key: "election_id") var election: Election
    @Parent(key: "bureau_id") var bureau: Bureau
    @Field(key: "heure") var heure: String // "09:00", "11:00", "14:00", "17:00", "final"
    @Field(key: "votants") var votants: Int
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() {}

    init(bureauID: UUID, heure: String, votants: Int) {
        self.$bureau.id = bureauID
        self.heure = heure
        self.votants = votants
    }
}

// Résultats partiels/finaux par candidat
final class Resultat: Model, Content, @unchecked Sendable {
    static let schema = "resultats"

    @ID(key: .id) var id: UUID?
    @Parent(key: "election_id") var election: Election
    @Parent(key: "bureau_id") var bureau: Bureau
    @Field(key: "candidat_id") var candidatId: UUID
    @Field(key: "voix") var voix: Int
    @Field(key: "bulletins_depouilles") var bulletinsDepouilles: Int
    @Field(key: "est_final") var estFinal: Bool
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() {}

    init(bureauID: UUID, candidatId: UUID, voix: Int, bulletinsDepouilles: Int, estFinal: Bool = false) {
        self.$bureau.id = bureauID
        self.candidatId = candidatId
        self.voix = voix
        self.bulletinsDepouilles = bulletinsDepouilles
        self.estFinal = estFinal
    }
}

// Candidats
final class Candidat: Model, Content, @unchecked Sendable {
    static let schema = "candidats"

    @ID(key: .id) var id: UUID?
    @Parent(key: "election_id") var election: Election
    @Field(key: "nom") var nom: String
    @Field(key: "prenom") var prenom: String
    @Field(key: "liste") var liste: String
    @Field(key: "couleur") var couleur: String
    @Field(key: "ordre") var ordre: Int
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(id: UUID? = nil, electionId: UUID, nom: String, prenom: String, liste: String, couleur: String, ordre: Int) {
        self.id = id
        self.$election.id = electionId
        self.nom = nom
        self.prenom = prenom
        self.liste = liste
        self.couleur = couleur
        self.ordre = ordre
    }
}
