import Vapor
import Fluent

struct ParticipationController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.post("bureaux", ":bureauId", "participations", use: upsertParticipation)
        routes.get("user", ":userId", use: getUser)
        routes.post("user", ":userId", use: updateUser)

    }

    func getUser(req: Request) async throws -> UserDTO {
        guard let id = req.parameters.get("userId", as: UUID.self) else { throw Abort(.badRequest) }
        guard let user = try await User.find(id, on: req.db) else { throw Abort(.notFound) }
        return UserDTO(
            id: user.id!,
            nom: user.nom,
            email: user.email,
            role: user.role,
            isAdmin: user.isAdmin,
            bureaux: [],
            prenom: user.prenom,
            dispBureauId: user.$dispBureau.id,
            dispAssesseur: user.dispAssesseur,
            dispDelegue: user.dispDelegue
        )
    }
    func updateUser(req: Request) async throws -> UserDTO {
        guard let id = req.parameters.get("userId", as: UUID.self) else { throw Abort(.badRequest) }
        guard let user = try await User.find(id, on: req.db) else { throw Abort(.notFound) }
        let updateReq = try req.content.decode(UserDTO.self)
        user.nom = updateReq.nom
        user.prenom=updateReq.prenom
        user.dispDelegue=updateReq.dispDelegue
        user.dispAssesseur=updateReq.dispAssesseur
        user.$dispBureau.id=updateReq.dispBureauId
        try await user.save(on: req.db)
        return UserDTO(
            id: user.id!,
            nom: user.nom,
            email: user.email,
            role: user.role,
            isAdmin: user.isAdmin,
            bureaux: [],
            prenom: user.prenom,
            dispBureauId: user.$dispBureau.id,
            dispAssesseur: user.dispAssesseur,
            dispDelegue: user.dispDelegue
        )
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

    func upsertParticipation(req: Request) async throws -> ParticipationDTO {
        let payload = try req.auth.require(UserPayload.self)

        guard let bureauId = req.parameters.get("bureauId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let bureau = try await Bureau.query(on: req.db)
            .filter(\.$id == bureauId)
            .with(\.$scrutateurs)
            .first() else {
            throw Abort(.notFound)
        }

        if payload.role != "admin" {
            let canAccess = bureau.scrutateurs.contains { $0.id == payload.userId }
            guard canAccess else {
                throw Abort(.forbidden, reason: "Vous n'êtes pas assigné à ce bureau")
            }
        }

        let participationReq = try req.content.decode(UpsertParticipationRequest.self)

        // Upsert: update existing or create new
        if let existing = try await Participation.query(on: req.db)
            .filter(\.$bureau.$id == bureauId)
            .filter(\.$heure == participationReq.heure)
            .first() {
            existing.votants = participationReq.votants
            try await existing.save(on: req.db)
            let taux = bureau.inscrits > 0 ? Double(existing.votants) / Double(bureau.inscrits) * 100 : 0
            return ParticipationDTO(id: existing.id, bureauId: bureauId, heure: existing.heure,
                                   votants: existing.votants, tauxParticipation: taux,
                                   createdAt: existing.createdAt, updatedAt: existing.updatedAt)
        } else {
            let participation = Participation(bureauID: bureauId, heure: participationReq.heure, votants: participationReq.votants)
            try await participation.save(on: req.db)
            let taux = bureau.inscrits > 0 ? Double(participation.votants) / Double(bureau.inscrits) * 100 : 0
            return ParticipationDTO(id: participation.id, bureauId: bureauId, heure: participation.heure,
                                   votants: participation.votants, tauxParticipation: taux,
                                   createdAt: participation.createdAt, updatedAt: participation.updatedAt)
        }
    }
}

struct ResultatController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.post("bureaux", ":bureauId", "resultats", use: upsertResultat)
    }

    func upsertResultat(req: Request) async throws -> ResultatDTO {
        let payload = try req.auth.require(UserPayload.self)

        guard let bureauId = req.parameters.get("bureauId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let bureau = try await Bureau.query(on: req.db)
            .filter(\.$id == bureauId)
            .with(\.$scrutateurs)
            .first() else {
            throw Abort(.notFound)
        }

        if payload.role != "admin" {
            let canAccess = bureau.scrutateurs.contains { $0.id == payload.userId }
            guard canAccess else {
                throw Abort(.forbidden, reason: "Vous n'êtes pas assigné à ce bureau")
            }
        }

        let resultatReq = try req.content.decode(UpsertResultatRequest.self)

        if let existing = try await Resultat.query(on: req.db)
            .filter(\.$bureau.$id == bureauId)
            .filter(\.$candidatId == resultatReq.candidatId)
            .first() {
            existing.voix = resultatReq.voix
            existing.bulletinsDepouilles = resultatReq.bulletinsDepouilles
            if let estFinal = resultatReq.estFinal { existing.estFinal = estFinal }
            try await existing.save(on: req.db)
            return ResultatDTO(id: existing.id, bureauId: bureauId, candidatId: existing.candidatId,
                              voix: existing.voix, bulletinsDepouilles: existing.bulletinsDepouilles,
                              estFinal: existing.estFinal, updatedAt: existing.updatedAt)
        } else {
            let resultat = Resultat(bureauID: bureauId, candidatId: resultatReq.candidatId,
                                   voix: resultatReq.voix, bulletinsDepouilles: resultatReq.bulletinsDepouilles,
                                   estFinal: resultatReq.estFinal ?? false)
            try await resultat.save(on: req.db)
            return ResultatDTO(id: resultat.id, bureauId: bureauId, candidatId: resultat.candidatId,
                              voix: resultat.voix, bulletinsDepouilles: resultat.bulletinsDepouilles,
                              estFinal: resultat.estFinal, updatedAt: resultat.updatedAt)
        }
    }
}
