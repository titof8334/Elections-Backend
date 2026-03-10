import Vapor
import Fluent

struct DelegueController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let delegue = routes.grouped("delegue").grouped(DelegueMiddleware())
        delegue.get("elections", ":electionId", "bureaux", use: getBureaux)
        delegue.put("elections", ":electionId", "bureaux", ":bureauId", use: updateBureau)
        delegue.post("elections", ":electionId", "bureaux", ":bureauId", "participations", use: upsertParticipation)
        delegue.post("elections", ":electionId", "bureaux", ":bureauId", "resultats", use: upsertResultat)
    }
    
    func upsertParticipation(req: Request) async throws -> ParticipationDTO {
        guard let electionId = req.parameters.get("electionId", as: UUID.self),
              let bureauId = req.parameters.get("bureauId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let bureau = try await Bureau.query(on: req.db)
            .filter(\.$id == bureauId)
            .with(\.$scrutateurs)
            .first() else {
            throw Abort(.notFound)
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
            let participation = Participation(electionID: electionId, bureauID: bureauId, heure: participationReq.heure, votants: participationReq.votants)
            try await participation.save(on: req.db)
            let taux = bureau.inscrits > 0 ? Double(participation.votants) / Double(bureau.inscrits) * 100 : 0
            return ParticipationDTO(id: participation.id, bureauId: bureauId, heure: participation.heure,
                                   votants: participation.votants, tauxParticipation: taux,
                                   createdAt: participation.createdAt, updatedAt: participation.updatedAt)
        }
    }

    func updateBureau(req: Request) async throws -> BureauDTO {
        print("updateBureau")
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
            participations: participations, resultats: resultats, users: nil
        )
    }
    
    func getBureaux(req: Request) async throws -> [BureauDTO] {
        print("Delegue getBureaux")
        let payload = try req.auth.require(UserPayload.self)
        guard let electionId = req.parameters.get("electionId", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let userElection = try await UserElection.query(on: req.db)
            .filter(\.$election.$id == electionId)
            .filter(\.$user.$id == payload.userId)
            .first()
        print("Delegue 1")
        let usersBureaux = try await UserBureau.query(on: req.db)
            .filter(\.$election.$id == electionId)
            .filter(\.$user.$id == payload.userId)
            .with(\.$bureau)
            .all()
        print("Delegue 2")
        if let ue = userElection, ue.isOwner || (ue.role == "delegue" && usersBureaux.isEmpty) {
            print("Delegue 3 \(electionId)")
            return try await Bureau.query(on: req.db)
                .filter(\.$election.$id == electionId)
                .with(\.$participations)
                .with(\.$resultats)
                .sort(\.$numero)
                .all().map { try toBureauDTO($0) }
        } else {
            print("Delegue 4")
            let bureauIds = usersBureaux.compactMap { $0.$bureau.id }
            print("Delegue 5")
            return try await Bureau.query(on: req.db)
                .filter(\.$id ~~ bureauIds)
                .with(\.$participations)
                .with(\.$resultats)
                .sort(\.$numero)
                .all().map { try toBureauDTO($0) }
        }
    }

    func upsertResultat(req: Request) async throws -> ResultatDTO {
        guard let electionId = req.parameters.get("electionId", as: UUID.self),
              let bureauId = req.parameters.get("bureauId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard (try await Bureau.query(on: req.db)
            .filter(\.$id == bureauId)
            .with(\.$scrutateurs)
            .first()) != nil else {
            throw Abort(.notFound)
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
            let resultat = Resultat(electionID: electionId, bureauID: bureauId, candidatId: resultatReq.candidatId,
                                   voix: resultatReq.voix, bulletinsDepouilles: resultatReq.bulletinsDepouilles,
                                   estFinal: resultatReq.estFinal ?? false)
            try await resultat.save(on: req.db)
            return ResultatDTO(id: resultat.id, bureauId: bureauId, candidatId: resultat.candidatId,
                              voix: resultat.voix, bulletinsDepouilles: resultat.bulletinsDepouilles,
                              estFinal: resultat.estFinal, updatedAt: resultat.updatedAt)
        }
    }
    
    private func toBureauDTO(_ bureau: Bureau) throws -> BureauDTO {
        print("toBureauDTO \(bureau)")
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
            id: bureau.id,
            numero: bureau.numero,
            nom: bureau.nom,
            adresse: bureau.adresse,
            inscrits: bureau.inscrits,
            bulletinsDepouilles: bureau.bulletinsDepouilles,
            bulletinsNuls: bureau.bulletinsNuls,
            bulletinsBlancs: bureau.bulletinsBlancs,
            depouillementTermine: bureau.depouillementTermine,
            participations: participations,
            resultats: resultats,
            users: nil
        )
    }
}

struct DelegueMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let electionId = request.parameters.get("electionId", as: UUID.self) else { throw Abort(.badRequest) }
        let payload = try request.auth.require(UserPayload.self)
        
        // Check if user is owner or has delegue role for this election
        guard let userElection = try await UserElection.query(on: request.db)
            .filter(\.$user.$id == payload.userId)
            .filter(\.$election.$id == electionId)
            .first() else {
            throw Abort(.forbidden, reason: "Accès à l'élection requis")
        }
        
            // Accès autorisé aux propriétaires et délégués de l'élection
        if(!userElection.isOwner && userElection.role != "delegue") {
            // Accès autorisé au délégué du bureau
            
            // Verify user is a delegue for this election AND is assigned to this bureau
            guard userElection.role == "assesseur" else {
                throw Abort(.forbidden, reason: "Accès délégué ou assesseur requis")
            }
            if let bureauId = request.parameters.get("bureauId", as: UUID.self) {
                // Check if user is assigned to this specific bureau
                let userBureau = try await UserBureau.query(on: request.db)
                    .filter(\.$bureau.$id == bureauId)
                    .filter(\.$user.$id == payload.userId)
                    .first()
                guard userBureau != nil else {
                    throw Abort(.forbidden, reason: "Vous n'êtes pas assigné à ce bureau")
                }
            }
            
        }
        return try await next.respond(to: request)
    }
}

