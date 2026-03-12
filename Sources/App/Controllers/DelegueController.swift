import Vapor
import Fluent

struct DelegueController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let delegue = routes.grouped("delegue").grouped(DelegueMiddleware())
        delegue.get("elections", ":electionId", "bureaux", use: getBureaux)
        delegue.put("elections", ":electionId", "bureaux", ":bureauId", use: updateBureau)
        delegue.post("elections", ":electionId", "bureaux", ":bureauId", "participations", use: upsertParticipation)
        delegue.post("elections", ":electionId", "bureaux", ":bureauId", "resultats", use: upsertResultat)
        delegue.patch("elections", ":electionId", "bureaux", ":bureauId", "votants", use: updateVotants)
        delegue.patch("elections", ":electionId", "bureaux", ":bureauId", "inscrits", use: updateInscrits)
    }
    
    func getBureaux(req: Request) async throws -> [BureauDTO] {
        let payload = try req.auth.require(UserPayload.self)
        guard let electionId = req.parameters.get("electionId", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let userElection = try await UserElection.query(on: req.db)
            .filter(\.$election.$id == electionId)
            .filter(\.$user.$id == payload.userId)
            .first()
        let usersBureaux = try await UserBureau.query(on: req.db)
            .filter(\.$election.$id == electionId)
            .filter(\.$user.$id == payload.userId)
            .with(\.$bureau)
            .all()
        if let ue = userElection, ue.isOwner || (ue.role == "delegue" && usersBureaux.isEmpty) {
            return try await Bureau.query(on: req.db)
                .filter(\.$election.$id == electionId)
                .sort(\.$numero)
                .all().map { toBureauDTO($0) }
        } else {
            let bureauIds = usersBureaux.compactMap { $0.$bureau.id }
            return try await Bureau.query(on: req.db)
                .filter(\.$id ~~ bureauIds)
                .sort(\.$numero)
                .all().map { toBureauDTO($0) }
        }
    }

    func updateBureau(req: Request) async throws -> BureauDTO {
        guard let id = req.parameters.get("bureauId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let bureau = try await Bureau.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
    
        let updateReq = try req.content.decode(UpdateBureauRequest.self)

        if let inscrits = updateReq.inscrits { bureau.inscrits = inscrits }

        try await bureau.save(on: req.db)

        // Reload to get fresh data
        guard let updated = try await Bureau.find(id, on: req.db) else {
            throw Abort(.internalServerError)
        }

        return toBureauDTO(updated)
    }
    
    func updateInscrits(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("bureauId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let bureau = try await Bureau.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
    
        bureau.inscrits = try req.content.decode(Int.self)

        try await bureau.save(on: req.db)

        return .ok
    }
    func updateVotants(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("bureauId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let bureau = try await Bureau.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
    
        bureau.votants = try req.content.decode(Int.self)

        try await bureau.save(on: req.db)

        return .ok
    }

    func upsertParticipation(req: Request) async throws -> BureauDTO {
        guard let electionId = req.parameters.get("electionId", as: UUID.self),
              let bureauId = req.parameters.get("bureauId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let bureau = try await Bureau.find(bureauId, on: req.db) else {
            throw Abort(.notFound)
        }

        let participationReq = try req.content.decode(UpsertParticipationRequest.self)
        
        // Validate votants is non-negative
        guard participationReq.votants >= 0 else {
            throw Abort(.badRequest, reason: "Le nombre de votants ne peut pas être négatif")
        }
        var final = false
        // Initialize results when "final" participation is recorded
        if participationReq.heure == "final" {
            try await initializeResultsIfNeeded(electionId: electionId, bureauId: bureauId, on: req.db)
            final = true
            bureau.votants = participationReq.votants
            try await bureau.save(on: req.db)
        }
        
        // Perform upsert operation
        let participation: Participation
        if let existing = try await Participation.query(on: req.db)
            .filter(\.$bureau.$id == bureauId)
            .filter(\.$heure == participationReq.heure)
            .first() {
            existing.votants = participationReq.votants
            try await existing.save(on: req.db)
            participation = existing
        } else {
            participation = Participation(
                electionID: electionId,
                bureauID: bureauId,
                heure: participationReq.heure,
                votants: participationReq.votants
            )
            try await participation.save(on: req.db)
        }
        guard let finalBureau = try await Bureau.query(on: req.db).filter(\.$id == bureauId).with(\.$participations).with(\.$resultats).first() else {
            throw Abort(.badRequest, reason: "Problème lors du rechargement du bureau avec participations")
        }
        
        return toBureauDTO(finalBureau, withParticipation: true, withResultat: final)
    }
    
    private func initializeResultsIfNeeded(electionId: UUID, bureauId: UUID, on database: Database) async throws {
        // Check if results already exist for this bureau
        let existingCount = try await Resultat.query(on: database)
            .filter(\.$election.$id == electionId)
            .filter(\.$bureau.$id == bureauId)
            .count()
        
        guard existingCount == 0 else { return }
        
        // Create initial results for all candidates
        let candidats = try await Candidat.query(on: database)
            .filter(\.$election.$id == electionId)
            .all()
        
        for candidat in candidats {
            guard let candidatId = candidat.id else { continue }
            let resultat = Resultat(
                electionID: electionId,
                bureauID: bureauId,
                candidatId: candidatId,
                voix: 0
            )
            try await resultat.save(on: database)
        }
    }
    
    func upsertResultat(req: Request) async throws -> BureauDTO {
        guard let bureauId = req.parameters.get("bureauId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let bureau = try await Bureau.query(on: req.db)
            .filter(\.$id == bureauId)
            .with(\.$resultats)
            .with(\.$participations)
            .first() else {
            throw Abort(.notFound)
        }
        
        let resultatReq = try req.content.decode(UpsertResultatBureauRequest.self)
        
        guard bureau.resultats.count == resultatReq.resultats.count else {
            throw Abort(.badRequest, reason: "Résultat incohérent (nombre de candidats incorrect)")
        }
        
        // Validate all candidates match
        let bureauCandidatIds = Set(bureau.resultats.map { $0.candidatId })
        let requestCandidatIds = Set(resultatReq.resultats.map { $0.candidatId })
        guard bureauCandidatIds == requestCandidatIds else {
            throw Abort(.badRequest, reason: "Résultat incohérent (les candidats ne correspondent pas)")
        }
        
        // Validate total votes don't exceed bulletins counted
        let totalVoix = resultatReq.resultats.reduce(0) { $0 + $1.voix }
        let expectedTotal = resultatReq.bulletinsDepouilles - resultatReq.nuls - resultatReq.blancs
        guard totalVoix == expectedTotal else {
            throw Abort(.badRequest, reason: "Résultat incohérent (total des voix: \(totalVoix), attendu: \(expectedTotal))")
        }
        
        // Use transaction for atomic updates
        try await req.db.transaction { database in
            // Update bureau fields
            bureau.exprimes = resultatReq.bulletinsDepouilles - resultatReq.nuls - resultatReq.blancs
            bureau.bulletinsNuls = resultatReq.nuls
            bureau.bulletinsBlancs = resultatReq.blancs
            bureau.bulletinsDepouilles = resultatReq.bulletinsDepouilles
            bureau.depouillementTermine = resultatReq.estFinal
            try await bureau.save(on: database)
            
            // Update all results
            for resultat in bureau.resultats {
                guard let newVoix = resultatReq.resultats.first(where: { $0.candidatId == resultat.candidatId })?.voix else {
                    throw Abort(.internalServerError, reason: "Candidat introuvable")
                }
                resultat.voix = newVoix
                try await resultat.save(on: database)
            }
        }
        
        // Reload bureau with fresh data
        guard let updatedBureau = try await Bureau.query(on: req.db)
            .filter(\.$id == bureauId)
            .with(\.$resultats)
            .with(\.$participations)
            .first() else {
            throw Abort(.internalServerError)
        }
        
        return toBureauDTO(updatedBureau, withParticipation: true, withResultat: true)
    }
    
    private func toBureauDTO(_ bureau: Bureau, withParticipation: Bool = false, withResultat: Bool = false) -> BureauDTO {
        let participations = !withParticipation ? nil : bureau.participations.map { p -> ParticipationDTO in
            let taux = bureau.inscrits > 0 ? Double(p.votants) / Double(bureau.inscrits) * 100 : 0
            return ParticipationDTO(id: p.id, bureauId: bureau.id!, heure: p.heure, votants: p.votants,
                                   tauxParticipation: taux, createdAt: p.createdAt, updatedAt: p.updatedAt)
        }.sorted { $0.heure < $1.heure }

        let resultats = !withResultat ? nil : bureau.resultats.map { r in
            ResultatDTO(id: r.id, bureauId: bureau.id!, candidatId: r.candidatId,
                       voix: r.voix, updatedAt: r.updatedAt)
        }

        return BureauDTO(
            id: bureau.id,
            numero: bureau.numero,
            nom: bureau.nom,
            adresse: bureau.adresse,
            inscrits: bureau.inscrits,
            votants: bureau.votants,
            exprimes: bureau.exprimes,
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

