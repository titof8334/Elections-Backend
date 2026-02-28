import Vapor
import Fluent

final class User: Model, Content {
    static let schema = "users"

    @ID(format: .uuid) var id: UUID?
    @Field(key: "nom") var nom: String
    @Field(key: "email") var email: String
    @Field(key: "password_hash") var passwordHash: String
    @Field(key: "role") var role: String // "admin" | "scrutateur"
    @Siblings(through: UserBureau.self, from: \.$user, to: \.$bureau) var bureaux: [Bureau]
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(id: UUID? = nil, nom: String, email: String, passwordHash: String, role: String = "scrutateur") {
        self.id = id
        self.nom = nom
        self.email = email
        self.passwordHash = passwordHash
        self.role = role
    }
}

final class UserBureau: Model {
    static let schema = "user_bureau"

    @ID(format: .uuid) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Parent(key: "bureau_id") var bureau: Bureau

    init() {}
    init(userID: UUID, bureauID: UUID) {
        self.$user.id = userID
        self.$bureau.id = bureauID
    }
}
