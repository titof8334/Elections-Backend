import Vapor

struct AdminController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let admin = routes.grouped("admin").grouped(AdminMiddleware())

        // Election management
        admin.post("elections", use: createElection)
        admin.post("elections", ":electionId", "owner", ":ownerId", use: createOwner)

        // Users management
        admin.get("users", use: getUsers)
        admin.post("users", use: createUser)
        admin.put("users", ":userId", use: updateUser)
        admin.delete("users", ":userId", use: deleteUser)
        
    }

    // MARK: Elections
    func createElection(req: Request) async throws -> Election {
        let createReq = try req.content.decode(CreateElectionRequest.self)
        let election = Election(nom: createReq.nom)
        try await election.save(on: req.db)
        return election
    }
    func createOwner(req: Request) async throws -> UserElection {
        guard let electionId = req.parameters.get("electionId", as: UUID.self) else { throw Abort(.badRequest) }
        guard let ownerId = req.parameters.get("ownerId", as: UUID.self) else { throw Abort(.badRequest) }
        let relation = UserElection(userID: ownerId, electionID: electionId, isOwner: true)
        try await relation.save(on: req.db)
        return relation
    }

    // MARK: Users
    func getUsers(req: Request) async throws -> [UserDTO] {
        let users = try await User.query(on: req.db).with(\.$elections).all()
        return users.compactMap { u in
            guard let id = u.id else { return nil }
            return UserDTO(
                id: id,
                nom: u.nom,
                prenom: u.prenom,
                email: u.email,
                isAdmin: u.isAdmin
            )
        }
    }

    func createUser(req: Request) async throws -> UserDTO {
        let authController = AuthController()
        return try await authController.register(req: req)
    }

    func updateUser(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("userId", as: UUID.self) else { throw Abort(.badRequest) }
        guard let user = try await User.find(id, on: req.db) else { throw Abort(.notFound) }
        let updateReq = try req.content.decode(UserDTO.self)
        user.nom = updateReq.nom ?? user.nom
        user.prenom = updateReq.prenom ?? user.prenom
        user.isAdmin = updateReq.isAdmin ?? user.isAdmin
        try await user.save(on: req.db)
        return .noContent
    }

    func deleteUser(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("userId", as: UUID.self) else { throw Abort(.badRequest) }
        guard let user = try await User.find(id, on: req.db) else { throw Abort(.notFound) }
        // Don't allow deleting admin account
        guard user.email != "christ.arnal@laposte.net" else {
            throw Abort(.forbidden, reason: "Impossible de supprimer le compte admin principal")
        }
        try await user.delete(on: req.db)
        return .noContent
    }
}

struct AdminMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let payload = try request.auth.require(UserPayload.self)
        guard payload.isAdmin == true else {
            throw Abort(.forbidden, reason: "Accès administrateur requis")
        }
        return try await next.respond(to: request)
    }
}
