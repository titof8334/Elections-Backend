import Vapor
import Fluent

struct OwnerController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let owner = routes.grouped("owner").grouped(OwnerMiddleware())

        // Reset
        owner.delete("elections", ":electionId", "reset", use: resetElection)

        // Election management
        owner.delete("elections", ":electionId", use: deleteElection)
        owner.put("elections", ":electionId", use: updateElection)

        // Bureaux management
        owner.get("elections", ":electionId", "bureaux", use: getBureaux)
        owner.get("elections", ":electionId", "bureaux", ":bureauId", use: getBureau)
        owner.post("elections", ":electionId", "bureaux", use: createBureau)
        owner.delete("elections", ":electionId", "bureaux", ":bureauId", use: deleteBureau)
        owner.post("elections", ":electionId", "bureaux", ":bureauId", "assesseurs", ":userId", use: assignAssesseur)
        owner.delete("elections", ":electionId", "bureaux", ":bureauId", "assesseurs", ":userId", use: removeRole)
        owner.post("elections", ":electionId", "bureaux", ":bureauId", "delegue", ":userId", use: assignDelegue)
        owner.delete("elections", ":electionId", "bureaux", ":bureauId", "delegue", ":userId", use: removeRole)

        // Users management
        owner.get("elections", ":electionId", "users", use: getUsers)
        owner.post("elections", ":electionId", "users", use: createUser)
        owner.put("elections", ":electionId", "users", ":userId", use: updateUser)
        owner.delete("elections", ":electionId", "users", ":userId", use: blacklistUser)

        // Candidats management
        owner.post("elections", ":electionId", "candidats", use: createCandidat)
        owner.put("elections", ":electionId", "candidats", ":candidatId", use: updateCandidat)
        owner.delete("elections", ":electionId", "candidats", ":candidatId", use: deleteCandidat)

    }

    // MARK: Elections

    func deleteElection(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("electionId", as: UUID.self) else { throw Abort(.badRequest) }
        guard let election = try await Election.find(id, on: req.db) else { throw Abort(.notFound) }
        try await election.delete(on: req.db)
        return .noContent
    }
    
    func updateElection(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("electionId", as: UUID.self) else { throw Abort(.badRequest) }
        guard let election = try await Election.find(id, on: req.db) else { throw Abort(.notFound) }
        let updateReq = try req.content.decode(ElectionDTO.self)
        election.nom = updateReq.nom
        try await election.save(on: req.db)
        return .noContent
    }

    // MARK: Bureaux
    func getBureaux(req: Request) async throws -> [BureauDTO] {
        guard let electionId = req.parameters.get("electionId", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let usersBureaux = try await UserBureau.query(on: req.db)
            .filter(\.$election.$id == electionId)
            .all()
        let usersElection = try await UserElection.query(on: req.db)
            .filter(\.$election.$id == electionId)
            .with(\.$user)
            .all()
        let bureaux = try await Bureau.query(on: req.db)
            .filter(\.$election.$id == electionId)
            .sort(\.$numero)
            .all()

        return try bureaux.map { try toBureauDTO($0,usersBureaux: usersBureaux,usersElection: usersElection) }
    }

    func getBureau(req: Request) async throws -> BureauDTO {
        guard let id = req.parameters.get("bureauId", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        guard let bureau = try await Bureau.find(id,on: req.db) else {
            throw Abort(.notFound)
        }
        let userBureaux = try await UserBureau.query(on: req.db)
            .filter(\.$bureau.$id == id)
            .all()
        let usersElection = try await UserElection.query(on: req.db)
            .filter(\.$election.$id == bureau.$election.id)
            .with(\.$user)
            .all()
        return try toBureauDTO(bureau,usersBureaux: userBureaux,usersElection: usersElection)
    }

    func createBureau(req: Request) async throws -> Bureau {
        guard let id = req.parameters.get("electionId", as: UUID.self) else { throw Abort(.badRequest) }
        let createReq = try req.content.decode(CreateBureauRequest.self)
        let bureau = Bureau(electionId: id, numero: createReq.numero, nom: createReq.nom, adresse: createReq.adresse, inscrits: createReq.inscrits)
        try await bureau.save(on: req.db)
        return bureau
    }

    func deleteBureau(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("bureauId", as: UUID.self) else { throw Abort(.badRequest) }
        guard let bureau = try await Bureau.find(id, on: req.db) else { throw Abort(.notFound) }
        try await bureau.delete(on: req.db)
        return .noContent
    }

    func assignDelegue(req: Request) async throws -> HTTPStatus {
        guard let bureauId = req.parameters.get("bureauId", as: UUID.self),
              let userId = req.parameters.get("userId", as: UUID.self),
              let electionId = req.parameters.get("electionId", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        guard (try await Bureau.find(bureauId, on: req.db)) != nil else {
            throw Abort(.notFound, reason: "Bureau non trouvé")
        }
        
        guard (try await User.find(userId, on: req.db)) != nil else {
            throw Abort(.notFound, reason: "Utilisateur non trouvé")
        }
        
        // Check current user-election preferences
        guard let userElection = try await UserElection.query(on: req.db)
            .filter(\.$user.$id == userId)
            .filter(\.$election.$id == electionId)
            .first() else {
            throw Abort(.notFound, reason: "Relation utilisateur-élection non trouvée")
        }
        
        // If the user is not already a delegue, remove all their UserBureau relations for this election
        if userElection.role != "delegue" {
            // Get all bureaux for this election
            let bureauxIds = try await Bureau.query(on: req.db)
                .filter(\.$election.$id == electionId)
                .all(\.$id)
            
            // Delete all UserBureau entries where user is this userId and bureau is in this election
            try await UserBureau.query(on: req.db)
                .filter(\.$user.$id == userId)
                .filter(\.$bureau.$id ~~ bureauxIds)
                .delete()
            
            // Update user role to delegue for this election
            userElection.role = "delegue"
            try await userElection.save(on: req.db)
        }
        let delegue = UserBureau(userID: userId, electionID: electionId, bureauID: bureauId, role: "delegue", periode: "J")
        // Attach user to the specified bureau
        try await delegue.save(on: req.db)
        return .ok
    }

    func assignAssesseur(req: Request) async throws -> HTTPStatus {
        guard let bureauId = req.parameters.get("bureauId", as: UUID.self),
              let userId = req.parameters.get("userId", as: UUID.self),
              let electionId = req.parameters.get("electionId", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        guard (try await Bureau.find(bureauId, on: req.db)) != nil else {
            throw Abort(.notFound, reason: "Bureau non trouvé")
        }
        
        guard (try await User.find(userId, on: req.db)) != nil else {
            throw Abort(.notFound, reason: "Utilisateur non trouvé")
        }
        
        // Check current user-election preferences
        guard let userElection = try await UserElection.query(on: req.db)
            .filter(\.$user.$id == userId)
            .filter(\.$election.$id == electionId)
            .first() else {
            throw Abort(.notFound, reason: "Relation utilisateur-élection non trouvée")
        }
        
        // Supprime toutes les affectations en cours
        let bureauxIds = try await Bureau.query(on: req.db)
            .filter(\.$election.$id == electionId)
            .all(\.$id)
        
        // Delete all UserBureau entries where user is this userId and bureau is in this election
        try await UserBureau.query(on: req.db)
            .filter(\.$user.$id == userId)
            .filter(\.$bureau.$id ~~ bureauxIds)
            .delete()
            
        // Update user role to delegue for this election
        userElection.role = "assesseur"
        try await userElection.save(on: req.db)
        
        let delegue = UserBureau(userID: userId, electionID: electionId, bureauID: bureauId, role: "assesseur", periode: "J")
        // Attach user to the specified bureau
        try await delegue.save(on: req.db)
        return .ok
    }

    func removeRole(req: Request) async throws -> HTTPStatus {
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
    func getUsers(req: Request) async throws -> [ElectionUserDTO] {
        guard let electionId = req.parameters.get("electionId", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let users = try await UserElection.query(on: req.db).filter(\.$election.$id == electionId).with(\.$user).all()
        let usersIds = users.compactMap { $0.$user.id }
        let bureaux = try await UserBureau.query(on: req.db).filter(\.$election.$id == electionId).with(\.$bureau).all()
        return users.compactMap { ue -> ElectionUserDTO? in
            guard let userId = ue.user.id else { return nil }
            let userBureaux = bureaux.filter { $0.$user.id == userId }
            return ElectionUserDTO(
                id: userId,
                nom: ue.user.nom,
                prenom: ue.user.prenom,
                email: ue.user.email,
                isAdmin: ue.user.isAdmin,
                isOwner: ue.isOwner,
                role: ue.role,
                isTitulaire: ue.isTitulaire,
                bureaux: userBureaux.map { ElectionUserBureauDTO(id: $0.bureau.id, periode: $0.periode) },
                dispBureauId: ue.$dispBureau.id,
                dispAssesseur: ue.dispAssesseur,
                dispDelegue: ue.dispDelegue,
                periode: ue.periode
            )
        }.sorted { a, b in
            if let nomA = a.nom, let nomB = b.nom {
                if nomA != nomB {
                    return nomA < nomB
                }
            }
            if let prenomA = a.prenom, let prenomB = b.prenom {
                return prenomA < prenomB
            }
            return false
        }
    }

    func createUser(req: Request) async throws -> UserDTO {
        guard let electionId = req.parameters.get("electionId", as: UUID.self) else { throw Abort(.badRequest) }
        let authController = AuthController()
        let userDto = try await authController.register(req: req)
        try await UserElection(userID: userDto.id!, electionID: electionId).save(on: req.db)
        return userDto
    }

    func updateUser(req: Request) async throws -> HTTPStatus {
        guard let electionId = req.parameters.get("electionId", as: UUID.self) else { throw Abort(.badRequest) }
        guard let userId = req.parameters.get("userId", as: UUID.self) else { throw Abort(.badRequest) }
        guard let user = try await User.find(userId, on: req.db) else { throw Abort(.notFound) }
        let updateReq = try req.content.decode(ElectionUserDTO.self)
        user.nom = updateReq.nom ?? user.nom
        user.prenom = updateReq.prenom ?? user.prenom
        user.isAdmin = updateReq.isAdmin ?? user.isAdmin
        try await user.save(on: req.db)
        try await UserElection.query(on: req.db).filter(\.$election.$id == electionId).filter(\.$user.$id == userId).delete()
        try await UserBureau.query(on: req.db).filter(\.$election.$id == electionId).filter(\.$user.$id == userId).delete()
        try await UserElection(
            userID: userId, electionID: electionId,
            isOwner: updateReq.isOwner ?? false, role: updateReq.role ?? "aucun", isTitulaire: updateReq.isTitulaire ?? false,
            dispBureauId: updateReq.dispBureauId, dispAssesseur: updateReq.dispAssesseur ?? false, dispDelegue: updateReq.dispDelegue ?? false, periode: updateReq.periode ?? "J"
        ).save(on: req.db)
        if let bureaux = updateReq.bureaux {
            for bureau in bureaux {
                guard let bureauId = bureau.id else {
                    throw Abort(.forbidden, reason: "BureauId manquant pour UserBureau")
                }
                try await UserBureau(userID: userId, electionID: electionId, bureauID: bureauId, periode: bureau.periode).save(on: req.db)
            }
        }
        return .noContent
    }

    // @TODO : Dans le futur, prévoir de conserver UserElection mais avec un statut particulier blacklisté
    // ce statut sera utilisé pour filtrer les utilisateurs dans d'autres requêtes
    func blacklistUser(req: Request) async throws -> HTTPStatus {
        guard let userId = req.parameters.get("userId", as: UUID.self) else { throw Abort(.badRequest) }
        guard let user = try await User.find(userId, on: req.db) else { throw Abort(.notFound) }
        // Don't allow deleting admin account
        
        guard user.email != "admin@elections.local" else {
            throw Abort(.forbidden, reason: "Impossible de supprimer le compte admin principal")
        }
        guard let electionId = req.parameters.get("electionId", as: UUID.self) else { throw Abort(.badRequest) }
        try await UserElection.query(on: req.db)
            .filter(\.$user.$id == userId)
            .filter(\.$election.$id == electionId)
            .delete()
        try await UserBureau.query(on: req.db)
            .filter(\.$user.$id == userId)
            .filter(\.$election.$id == electionId)
            .delete()
        return .noContent
    }

    // MARK: Candidats
    func createCandidat(req: Request) async throws -> CandidatDTO {
        guard let electionId = req.parameters.get("electionId", as: UUID.self) else { throw Abort(.badRequest) }
        let createReq = try req.content.decode(CreateCandidatRequest.self)
        let candidat = Candidat(electionId: electionId, nom: createReq.nom, prenom: createReq.prenom, liste: createReq.liste,
                                couleur: createReq.couleur, ordre: createReq.ordre)
        try await candidat.save(on: req.db)
        return CandidatDTO(id: candidat.id, nom: candidat.nom, prenom: candidat.prenom,
                          liste: candidat.liste, couleur: candidat.couleur, ordre: candidat.ordre)
    }

    func updateCandidat(req: Request) async throws -> CandidatDTO {
        guard let electionId = req.parameters.get("electionId", as: UUID.self) else { throw Abort(.badRequest) }
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
    func resetElection(req: Request) async throws -> ElectionDTO {
        guard let electionId = req.parameters.get("electionId", as: UUID.self) else { throw Abort(.badRequest) }
        guard let election = try await Election.find(electionId, on: req.db) else {
            throw Abort(.notFound)
        }
        try await Resultat.query(on: req.db).filter(\.$election.$id == electionId).delete()
        try await Participation.query(on: req.db).filter(\.$election.$id == electionId).delete()
        // Get all bureau IDs for this election
//        let bureauxIds = try await Bureau.query(on: req.db)
//            .filter(\.$election.$id == electionId)
//            .all(\.$id)
        
        // Delete all UserBureau entries for these bureaux
//        try await UserBureau.query(on: req.db)
//            .filter(\.$bureau.$id ~~ bureauxIds)
//            .delete()

        let bureaux = try await Bureau.query(on: req.db).filter(\.$election.$id == electionId).all()
        for bureau in bureaux {
            bureau.inscrits = 0
            bureau.votants = 0
            bureau.exprimes = 0
            bureau.bulletinsDepouilles = 0
            bureau.bulletinsNuls = 0
            bureau.bulletinsBlancs = 0
            bureau.depouillementTermine = false
            try await bureau.save(on: req.db)
        }
        
        var userElection: UserElection? = nil
        if let payload = req.auth.get(UserPayload.self) {
            userElection = try await UserElection.query(on: req.db)
                .filter(\.$election.$id == electionId)
                .filter(\.$user.$id == payload.userId)
                .first()
        }
        return try toElectionDTO(election,userElection: userElection)
    }
    
    private func toElectionDTO(_ election: Election, userElection: UserElection? = nil) throws -> ElectionDTO {
        if let ue = userElection {
            return ElectionDTO(
                id: election.id,
                nom: election.nom,
                isOwner: ue.isOwner,
                isScrutateur: ue.role != "aucun",
                isSubscriber : true
            )
        }
        return ElectionDTO(
            id: election.id,
            nom: election.nom,
            isOwner: false,
            isScrutateur: false,
            isSubscriber : false
        )
    }

}

struct OwnerMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let electionId = request.parameters.get("electionId", as: UUID.self) else { throw Abort(.badRequest) }
        let payload = try request.auth.require(UserPayload.self)
        if payload.isAdmin == true {
            return try await next.respond(to: request)
        }
        let ue = try await UserElection.query(on: request.db)
            .filter(\.$user.$id == payload.userId)
            .filter(\.$election.$id == electionId)
            .first()
        guard ue?.isOwner == true else {
            throw Abort(.forbidden, reason: "Accès propriétaire requis")
        }
        return try await next.respond(to: request)
    }
}
// MARK: - Helper Functions
extension OwnerController {
    private func toBureauDTO(_ bureau: Bureau,usersBureaux: [UserBureau]?,usersElection: [UserElection]?) throws -> BureauDTO {
        var users: [UserBureauDTO]? = nil
        if let ues = usersElection {
            let ubs = usersBureaux?.filter { $0.$bureau.id == bureau.id }
            users = ues.map { ue in
                let ub = ubs?.first(where: { $0.$user.id == ue.$user.id})
                return UserBureauDTO(id: ue.$user.id, nom: ue.user.nom, prenom: ue.user.prenom, role: ub != nil ? ue.role : nil, isTitulaire: ue.isTitulaire, periode: ub != nil ? ub?.periode : nil, dispAssesseur: ue.$dispBureau.id == bureau.id ? ue.dispAssesseur : false, dispDelegue: ue.$dispBureau.id == bureau.id ? ue.dispDelegue : false, dispPeriode: ue.periode)
            }
        }
        return BureauDTO(
            id: bureau.id,
            numero: bureau.numero,
            nom: bureau.nom,
            adresse: bureau.adresse,
            inscrits: nil,
            votants: nil,
            exprimes: nil,
            bulletinsDepouilles: nil,
            bulletinsNuls: nil,
            bulletinsBlancs: nil,
            depouillementTermine: nil,
            participations: nil,
            resultats: nil,
            users: users
        )
    }
}
