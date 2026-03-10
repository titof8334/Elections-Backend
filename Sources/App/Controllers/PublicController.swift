import Vapor
import Fluent

struct PublicController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("elections", ":electionId" ,"synthese", use: getSynthese)
        routes.get("elections", use: getElections)
        routes.get("elections", ":electionId", use: getElection)
        routes.get("elections", ":electionId", "bureaux", use: getBureaux)
        routes.get("elections", ":electionId", "bureaux", ":bureauId", "synthese", use: getSyntheseBureau)
        routes.get("elections", ":electionId", "candidats", use: getCandidats)
    }

    func getSynthese(req: Request) async throws -> SyntheseGlobale {
        guard let electionId = req.parameters.get("electionId", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let bureaux = try await Bureau.query(on: req.db)
            .filter(\.$election.$id == electionId)
            .with(\.$participations)
            .with(\.$resultats)
            .sort(\.$numero)
            .all()

        let candidats = try await Candidat.query(on: req.db)
            .filter(\.$election.$id == electionId)
            .sort(\.$ordre).all()

        let totalInscrits = bureaux.reduce(0) { $0 + $1.inscrits }

        // Collect final participation per bureau
        var totalVotants = 0
        var heuresDict: [String: Int] = [:]

        for bureau in bureaux {
            let finalPart = bureau.participations.filter { $0.heure == "final" }.first
            let lastPart = bureau.participations.sorted { $0.heure < $1.heure }.last
            totalVotants += (finalPart ?? lastPart)?.votants ?? 0

            for part in bureau.participations {
                heuresDict[part.heure, default: 0] += part.votants
            }
        }

        let tauxGlobal = totalInscrits > 0 ? Double(totalVotants) / Double(totalInscrits) * 100 : 0

        // Résultats globaux par candidat
        var voixParCandidat: [UUID: Int] = [:]
        var totalVoixGlobal = 0
        for bureau in bureaux {
            for resultat in bureau.resultats {
                voixParCandidat[resultat.candidatId, default: 0] += resultat.voix
                totalVoixGlobal += resultat.voix
            }
        }

        let resultatsGlobaux: [ResultatGlobal] = candidats.compactMap { candidat in
            guard let id = candidat.id else { return nil }
            let voix = voixParCandidat[id] ?? 0
            let pct = totalVoixGlobal > 0 ? Double(voix) / Double(totalVoixGlobal) * 100 : 0
            return ResultatGlobal(
                candidatId: id,
                candidatNom: candidat.nom,
                candidatPrenom: candidat.prenom,
                candidatListe: candidat.liste,
                couleur: candidat.couleur,
                totalVoix: voix,
                pourcentage: pct
            )
        }.sorted { $0.totalVoix > $1.totalVoix }

        let heuresOrdonnees = ["09:00", "11:00", "14:00", "17:00", "final"]
        let participationsParHeure: [ParticipationHeure] = heuresOrdonnees.compactMap { heure in
            guard let votants = heuresDict[heure] else { return nil }
            let taux = totalInscrits > 0 ? Double(votants) / Double(totalInscrits) * 100 : 0
            return ParticipationHeure(heure: heure, totalVotants: votants, tauxParticipation: taux)
        }

        let bureauResumes: [BureauResume] = bureaux.compactMap { b in
            guard let id = b.id else { return nil }
            return BureauResume(id: id, numero: b.numero, nom: b.nom, inscrits: b.inscrits,
                                bulletinsDepouilles: b.bulletinsDepouilles, depouillementTermine: b.depouillementTermine)
        }

        return SyntheseGlobale(
            totalInscrits: totalInscrits,
            totalVotants: totalVotants,
            tauxParticipationGlobal: tauxGlobal,
            bureaux: bureauResumes,
            resultatsGlobaux: resultatsGlobaux,
            participationsParHeure: participationsParHeure,
            bureauxTermines: bureaux.filter { $0.depouillementTermine }.count,
            totalBureaux: bureaux.count
        )
    }

    func getElections(req: Request) async throws -> [ElectionDTO] {
        let elections = try await Election.query(on: req.db)
            .all()
        if let payload = req.auth.get(UserPayload.self) {
            let userElections = try await UserElection.query(on: req.db)
                .filter(\.$user.$id == payload.userId)
                .all()
            return try elections.map { e in
                let ue = userElections.first(where: { $0.$election.id == e.id})
                return try toElectionDTO(e,userElection: ue)
            }
        } else {
            return try elections.map { try toElectionDTO($0) }
        }
    }
    
    func getElection(req: Request) async throws -> ElectionDTO {
        guard let electionId = req.parameters.get("electionId", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        guard let election = try await Election.find(electionId, on: req.db) else {
            throw Abort(.notFound)
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

    func getBureaux(req: Request) async throws -> [BureauDTO] {
        guard let electionId = req.parameters.get("electionId", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let bureaux = try await Bureau.query(on: req.db)
            .filter(\.$election.$id == electionId)
            .with(\.$participations)
            .with(\.$resultats)
            .sort(\.$numero)
            .all()

        return try bureaux.map { try toBureauDTO($0) }
    }

    func getSyntheseBureau(req: Request) async throws -> BureauDTO {
        guard let id = req.parameters.get("bureauId", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        guard let bureau = try await Bureau.query(on: req.db)
            .filter(\.$id == id)
            .with(\.$participations)
            .with(\.$resultats)
            .first() else {
            throw Abort(.notFound)
        }
        return try toBureauDTO(bureau)
    }

    func getCandidats(req: Request) async throws -> [CandidatDTO] {
        guard let electionId = req.parameters.get("electionId", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let candidats = try await Candidat.query(on: req.db).filter(\.$election.$id == electionId).sort(\.$ordre).all()
        return candidats.map { c in
            CandidatDTO(id: c.id, nom: c.nom, prenom: c.prenom, liste: c.liste, couleur: c.couleur, ordre: c.ordre)
        }
    }

    private func toBureauDTO(_ bureau: Bureau) throws -> BureauDTO {
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
