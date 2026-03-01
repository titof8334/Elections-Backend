import Vapor
import Fluent

struct ParticipationController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.post("bureaux", ":bureauId", "participations", use: upsertParticipation)
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
