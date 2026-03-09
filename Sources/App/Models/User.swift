import Vapor
import Fluent

final class User: Model, Content, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id) var id: UUID?
    @Field(key: "nom") var nom: String
    @Field(key: "email") var email: String
    @Field(key: "password_hash") var passwordHash: String
    @Field(key: "is_admin") var isAdmin: Bool
    @OptionalField(key: "zitadel_sub") var zitadelSub: String? // Zitadel User ID
    @OptionalField(key: "prenom") var prenom: String?
    @Siblings(through: UserBureau.self, from: \.$user, to: \.$bureau) var bureaux: [Bureau]
    @Siblings(through: UserElection.self, from: \.$user, to: \.$election) var elections: [Election]
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(id: UUID? = nil, nom: String, email: String, passwordHash: String, isAdmin: Bool = false, zitadelSub: String? = nil, prenom: String? = nil) {
        self.id = id
        self.nom = nom
        self.email = email
        self.passwordHash = passwordHash
        self.isAdmin = isAdmin
        self.zitadelSub = zitadelSub
        self.prenom = prenom
    }
}

final class UserBureau: Model, Content, @unchecked Sendable {
    static let schema = "user_bureau"

    @ID(key: .id) var id: UUID?
    @Parent(key: "election_id") var election: Election
    @Parent(key: "user_id") var user: User
    @Parent(key: "bureau_id") var bureau: Bureau
    @OptionalField(key: "periode") var periode: String? // "J" | "M" | "AM"

    init() {}
    init(userID: UUID, electionID: UUID, bureauID: UUID, role: String = "aucun", periode: String? = nil) {
        self.$election.id = electionID
        self.$user.id = userID
        self.$bureau.id = bureauID
        self.periode = periode
    }
}

final class UserElection: Model, Content, @unchecked Sendable {
    static let schema = "user_election"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Parent(key: "election_id") var election: Election
    @Field(key: "is_owner") var isOwner: Bool
    @Field(key: "role") var role: String // "aucun" | "assesseur" | "delegue
    @OptionalParent(key: "disp_bureau_id") var dispBureau: Bureau? // Bureau d'affectation
    @Field(key: "disp_assesseur") var dispAssesseur: Bool? // Disposition assesseur
    @Field(key: "disp_delegue") var dispDelegue: Bool? // Disposition délégué
    @Field(key: "periode") var periode: String? // "J" | "M" | "AM"

    init() {}
    init(userID: UUID, electionID: UUID, isOwner: Bool = false, role: String = "aucun", dispBureauId: UUID? = nil,dispAssesseur: Bool = false, dispDelegue: Bool = false, periode: String = "") {
        self.$user.id = userID
        self.$election.id = electionID
        self.isOwner = isOwner
        self.role = role
        self.$dispBureau.id = dispBureauId
        self.dispAssesseur = dispAssesseur
        self.dispDelegue = dispDelegue
        self.periode = periode
    }
}
