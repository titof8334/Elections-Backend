import Vapor
import JWT

struct AuthController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.post("login", use: login)
        routes.post("register", use: register) // Admin only via admin controller
    }

    func login(req: Request) async throws -> LoginResponse {
        let loginReq = try req.content.decode(LoginRequest.self)

        guard let user = try await User.query(on: req.db)
            .filter(\.$email == loginReq.email)
            .with(\.$bureaux)
            .first() else {
            throw Abort(.unauthorized, reason: "Email ou mot de passe incorrect")
        }

        guard try Bcrypt.verify(loginReq.password, created: user.passwordHash) else {
            throw Abort(.unauthorized, reason: "Email ou mot de passe incorrect")
        }

        let payload = UserPayload(
            sub: .init(value: user.id!.uuidString),
            exp: .init(value: Date().addingTimeInterval(60 * 60 * 12)), // 12h
            userId: user.id!,
            email: user.email,
            role: user.role,
            nom: user.nom
        )

        let token = try req.jwt.sign(payload)
        let bureauIds = user.bureaux.compactMap { $0.id }

        return LoginResponse(
            token: token,
            user: UserDTO(id: user.id!, nom: user.nom, email: user.email, role: user.role, bureaux: bureauIds)
        )
    }

    func register(req: Request) async throws -> UserDTO {
        let createReq = try req.content.decode(CreateUserRequest.self)

        let existingUser = try await User.query(on: req.db)
            .filter(\.$email == createReq.email)
            .first()

        if existingUser != nil {
            throw Abort(.conflict, reason: "Cet email est déjà utilisé")
        }

        let hash = try Bcrypt.hash(createReq.password)
        let user = User(nom: createReq.nom, email: createReq.email, passwordHash: hash, role: createReq.role ?? "scrutateur")
        try await user.save(on: req.db)

        // Associate bureaux if provided
        if let bureauIds = createReq.bureauIds {
            for bureauId in bureauIds {
                if let bureau = try await Bureau.find(bureauId, on: req.db) {
                    try await user.$bureaux.attach(bureau, on: req.db)
                }
            }
        }

        return UserDTO(id: user.id!, nom: user.nom, email: user.email, role: user.role, bureaux: createReq.bureauIds ?? [])
    }
}
