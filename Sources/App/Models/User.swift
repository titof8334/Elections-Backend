import Vapor
import Fluent

final class User: Model, Content, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id) var id: UUID?
    @Field(key: "nom") var nom: String
    @Field(key: "email") var email: String
    @Field(key: "password_hash") var passwordHash: String
    @Field(key: "role") var role: String // "aucun" | "assesseur" | "delegue
    @Field(key: "is_admin") var isAdmin: Bool
    @OptionalField(key: "zitadel_sub") var zitadelSub: String? // Zitadel User ID
    @OptionalField(key: "prenom") var prenom: String?
    @OptionalParent(key: "disp_bureau_id") var dispBureau: Bureau? // Bureau d'affectation
    @OptionalField(key: "disp_assesseur") var dispAssesseur: Bool? // Disposition assesseur
    @OptionalField(key: "disp_delegue") var dispDelegue: Bool? // Disposition délégué
    @Siblings(through: UserBureau.self, from: \.$user, to: \.$bureau) var bureaux: [Bureau]
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(id: UUID? = nil, nom: String, email: String, passwordHash: String, isAdmin: Bool = false, role: String = "aucun", zitadelSub: String? = nil, prenom: String? = nil, dispAssesseur: Bool? = nil, dispDelegue: Bool? = nil) {
        self.id = id
        self.nom = nom
        self.email = email
        self.passwordHash = passwordHash
        self.role = role
        self.isAdmin = isAdmin
        self.zitadelSub = zitadelSub
        self.prenom = prenom
        self.dispAssesseur = dispAssesseur
        self.dispDelegue = dispDelegue
    }
}

final class UserBureau: Model, @unchecked Sendable {
    static let schema = "user_bureau"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Parent(key: "bureau_id") var bureau: Bureau

    init() {}
    init(userID: UUID, bureauID: UUID) {
        self.$user.id = userID
        self.$bureau.id = bureauID
    }
}
