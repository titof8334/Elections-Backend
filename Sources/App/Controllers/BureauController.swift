import Vapor
import Fluent

struct BureauController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let bureaux = routes.grouped("bureaux")
        bureaux.put(":bureauId", use: updateBureau)
    }

    func updateBureau(req: Request) async throws -> BureauDTO {
        let payload = try req.auth.require(UserPayload.self)

        guard let id = req.parameters.get("bureauId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let bureau = try await Bureau.query(on: req.db)
            .filter(\.$id == id)
            .with(\.$participations)
            .with(\.$resultats)
            .with(\.$scrutateurs)
            .first() else {
            throw Abort(.notFound)
        }

        // Check authorization: admin or assigned scrutateur
        if payload.role != "admin" {
            let canAccess = bureau.scrutateurs.contains { $0.id == payload.userId }
            guard canAccess else {
                throw Abort(.forbidden, reason: "Vous n'êtes pas assigné à ce bureau")
            }
        }

        let updateReq = try req.content.decode(UpdateBureauRequest.self)

        if let numero = updateReq.numero { bureau.numero = numero }
        if let nom = updateReq.nom { bureau.nom = nom }
        if let adresse = updateReq.adresse { bureau.adresse = adresse }
        if let inscrits = updateReq.inscrits { bureau.inscrits = inscrits }
        if let bulletinsDepouilles = updateReq.bulletinsDepouilles { bureau.bulletinsDepouilles = bulletinsDepouilles }
        if let bulletinsNuls = updateReq.bulletinsNuls { bureau.bulletinsNuls = bulletinsNuls }
        if let bulletinsBlancs = updateReq.bulletinsBlancs { bureau.bulletinsBlancs = bulletinsBlancs }
        if let depouillementTermine = updateReq.depouillementTermine { bureau.depouillementTermine = depouillementTermine }

        try await bureau.save(on: req.db)

        // Reload to get fresh data
        guard let updated = try await Bureau.query(on: req.db)
            .filter(\.$id == id)
            .with(\.$participations)
            .with(\.$resultats)
            .first() else {
            throw Abort(.internalServerError)
        }

        return makeBureauDTO(updated)
    }

    private func makeBureauDTO(_ bureau: Bureau) -> BureauDTO {
        let participations = bureau.participations.map { p -> ParticipationDTO in
            let taux = bureau.inscrits > 0 ? Double(p.votants) / Double(bureau.inscrits) * 100 : 0
            return ParticipationDTO(id: p.id, bureauId: bureau.id!, heure: p.heure, votants: p.votants,
                                   tauxParticipation: taux, createdAt: p.createdAt, updatedAt: p.updatedAt)
        }.sorted { $0.heure < $1.heure }

        let resultats = bureau.resultats.map { r in
            ResultatDTO(id: r.id, bureauId: bureau.id!, candidatId: r.candidatId,
                       voix: r.voix, bulletinsDepouilles: r.bulletinsDepouilles,
                       estFinal: r.estFinal, updatedAt: r.updatedAt)
        }

        return BureauDTO(
            id: bureau.id, numero: bureau.numero, nom: bureau.nom, adresse: bureau.adresse,
            inscrits: bureau.inscrits, bulletinsDepouilles: bureau.bulletinsDepouilles,
            bulletinsNuls: bureau.bulletinsNuls, bulletinsBlancs: bureau.bulletinsBlancs,
            depouillementTermine: bureau.depouillementTermine,
            participations: participations, resultats: resultats
        )
    }
}
