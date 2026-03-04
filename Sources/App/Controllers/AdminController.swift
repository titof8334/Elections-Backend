import Vapor

struct AdminController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let admin = routes.grouped(AdminMiddleware())

        // Bureaux management
        admin.post("bureaux", use: createBureau)
        admin.delete("bureaux", ":bureauId", use: deleteBureau)
        admin.post("bureaux", ":bureauId", "scrutateurs", ":userId", use: assignScrutateur)
        admin.delete("bureaux", ":bureauId", "scrutateurs", ":userId", use: removeScrutateur)

        // Users management
        admin.get("users", use: getUsers)
        admin.post("users", use: createUser)
        admin.put("users", ":userId", use: updateUser)
        admin.delete("users", ":userId", use: deleteUser)

        // Candidats management
        admin.post("candidats", use: createCandidat)
        admin.put("candidats", ":candidatId", use: updateCandidat)
        admin.delete("candidats", ":candidatId", use: deleteCandidat)

        // Reset
        admin.delete("reset", use: resetElection)
    }

    // MARK: Bureaux
    func createBureau(req: Request) async throws -> Bureau {
        let createReq = try req.content.decode(CreateBureauRequest.self)
        let bureau = Bureau(numero: createReq.numero, nom: createReq.nom, adresse: createReq.adresse, inscrits: createReq.inscrits)
        try await bureau.save(on: req.db)
        return bureau
    }

    func deleteBureau(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("bureauId", as: UUID.self) else { throw Abort(.badRequest) }
        guard let bureau = try await Bureau.find(id, on: req.db) else { throw Abort(.notFound) }
        try await bureau.delete(on: req.db)
        return .noContent
    }

    func assignScrutateur(req: Request) async throws -> HTTPStatus {
        guard let bureauId = req.parameters.get("bureauId", as: UUID.self),
              let userId = req.parameters.get("userId", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        guard let bureau = try await Bureau.find(bureauId, on: req.db),
              let user = try await User.find(userId, on: req.db) else {
            throw Abort(.notFound)
        }
        try await bureau.$scrutateurs.attach(user, on: req.db)
        return .ok
    }

    func removeScrutateur(req: Request) async throws -> HTTPStatus {
        guard let bureauId = req.parameters.get("bureauId", as: UUID.self),
              let userId = req.parameters.get("userId", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        guard let bureau = try await Bureau.find(bureauId, on: req.db),
              let user = try await User.find(userId, on: req.db) else {
            throw Abort(.notFound)
        }
        try await bureau.$scrutateurs.detach(user, on: req.db)
        return .ok
    }

    // MARK: Users
    func getUsers(req: Request) async throws -> [UserDTO] {
        let users = try await User.query(on: req.db).with(\.$bureaux).all()
        return users.compactMap { u in
            guard let id = u.id else { return nil }
            return UserDTO(
                id: id,
                nom: u.nom,
                email: u.email,
                role: u.role,
                isAdmin: u.isAdmin,
                bureaux: u.bureaux.compactMap { $0.id },
                prenom: u.prenom,
                dispBureauId: u.$dispBureau.id,
                dispAssesseur: u.dispAssesseur,
                dispDelegue: u.dispDelegue
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
        user.role = updateReq.role
        
//        user.bureaux = updateReq.bureaux
        try await user.save(on: req.db)
        return .noContent
    }

    func deleteUser(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("userId", as: UUID.self) else { throw Abort(.badRequest) }
        guard let user = try await User.find(id, on: req.db) else { throw Abort(.notFound) }
        // Don't allow deleting admin account
        guard user.email != "admin@elections.local" else {
            throw Abort(.forbidden, reason: "Impossible de supprimer le compte admin principal")
        }
        try await user.delete(on: req.db)
        return .noContent
    }

    // MARK: Candidats
    func createCandidat(req: Request) async throws -> CandidatDTO {
        let createReq = try req.content.decode(CreateCandidatRequest.self)
        let candidat = Candidat(nom: createReq.nom, prenom: createReq.prenom, liste: createReq.liste,
                                couleur: createReq.couleur, ordre: createReq.ordre)
        try await candidat.save(on: req.db)
        return CandidatDTO(id: candidat.id, nom: candidat.nom, prenom: candidat.prenom,
                          liste: candidat.liste, couleur: candidat.couleur, ordre: candidat.ordre)
    }

    func updateCandidat(req: Request) async throws -> CandidatDTO {
        guard let id = req.parameters.get("candidatId", as: UUID.self) else { throw Abort(.badRequest) }
        guard let candidat = try await Candidat.find(id, on: req.db) else { throw Abort(.notFound) }
        let updateReq = try req.content.decode(CreateCandidatRequest.self)
        candidat.nom = updateReq.nom
        candidat.prenom = updateReq.prenom
        candidat.liste = updateReq.liste
        candidat.couleur = updateReq.couleur
        candidat.ordre = updateReq.ordre
        try await candidat.save(on: req.db)
        return CandidatDTO(id: candidat.id, nom: candidat.nom, prenom: candidat.prenom,
                          liste: candidat.liste, couleur: candidat.couleur, ordre: candidat.ordre)
    }

    func deleteCandidat(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("candidatId", as: UUID.self) else { throw Abort(.badRequest) }
        guard let candidat = try await Candidat.find(id, on: req.db) else { throw Abort(.notFound) }
        try await candidat.delete(on: req.db)
        return .noContent
    }

    // MARK: Reset
    func resetElection(req: Request) async throws -> HTTPStatus {
        try await Resultat.query(on: req.db).delete()
        try await Participation.query(on: req.db).delete()
        let bureaux = try await Bureau.query(on: req.db).all()
        for bureau in bureaux {
            bureau.bulletinsDepouilles = 0
            bureau.bulletinsNuls = 0
            bureau.bulletinsBlancs = 0
            bureau.depouillementTermine = false
            try await bureau.save(on: req.db)
        }
        return .ok
    }
}
